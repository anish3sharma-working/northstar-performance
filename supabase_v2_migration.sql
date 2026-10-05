-- ============================================================
-- Northstar Performance Management System
-- Version 2 incremental migration
--
-- Use this file ONLY after the original version 1 supabase.sql
-- has already been executed successfully.
--
-- This migration is intentionally idempotent: it can be safely
-- re-run if the SQL editor reports a timeout or partial failure.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Extend existing version 1 tables
-- ------------------------------------------------------------

alter table public.profiles
  add column if not exists title text default 'Team member';

alter table public.review_cycles
  add column if not exists phase text default 'Self-review & manager assessment';

alter table public.performance_reviews
  add column if not exists competency_ratings jsonb not null default '{}'::jsonb;

alter table public.performance_reviews
  add column if not exists submitted_at timestamptz;

-- ------------------------------------------------------------
-- 2. Continuous check-ins
-- ------------------------------------------------------------

create table if not exists public.checkins (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  manager_id uuid references public.profiles(id),
  date date not null default current_date,
  mood text not null default 'good'
    check (mood in ('great', 'good', 'stretched')),
  wins text not null,
  blockers text,
  next_steps text not null,
  private_note text,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3. Development plans and actions
-- ------------------------------------------------------------

create table if not exists public.development_plans (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  focus text not null,
  target_date date,
  status text not null default 'in_progress'
    check (status in ('not_started', 'in_progress', 'completed')),
  progress integer not null default 0
    check (progress between 0 and 100),
  created_at timestamptz not null default now()
);

create table if not exists public.development_actions (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.development_plans(id) on delete cascade,
  action text not null,
  completed boolean not null default false,
  due_date date
);

-- ------------------------------------------------------------
-- 4. 360-degree feedback
-- ------------------------------------------------------------

create table if not exists public.feedback_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  review_id uuid references public.performance_reviews(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'declined')),
  created_at timestamptz not null default now()
);

create table if not exists public.peer_feedback (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  review_id uuid references public.performance_reviews(id) on delete set null,
  feedback_type text not null default 'peer',
  comment text not null,
  shared boolean not null default false,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 5. One-on-one meetings
-- ------------------------------------------------------------

create table if not exists public.one_on_ones (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  manager_id uuid not null references public.profiles(id) on delete cascade,
  meeting_date date not null,
  agenda text,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'completed', 'cancelled')),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 6. Recognition wall
-- ------------------------------------------------------------

create table if not exists public.recognitions (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  value text not null,
  message text not null,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 7. Anonymous pulse surveys
-- ------------------------------------------------------------

create table if not exists public.pulse_surveys (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.pulse_responses (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.pulse_surveys(id) on delete cascade,
  score integer not null check (score between 1 and 5),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 8. Notifications and audit events
-- ------------------------------------------------------------

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 9. Enable row-level security on all new tables
-- ------------------------------------------------------------

alter table public.checkins enable row level security;
alter table public.development_plans enable row level security;
alter table public.development_actions enable row level security;
alter table public.feedback_requests enable row level security;
alter table public.peer_feedback enable row level security;
alter table public.one_on_ones enable row level security;
alter table public.recognitions enable row level security;
alter table public.pulse_surveys enable row level security;
alter table public.pulse_responses enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_events enable row level security;

-- ------------------------------------------------------------
-- 10. Replace/create v2 policies safely
-- ------------------------------------------------------------

-- Check-ins
 drop policy if exists "checkins visible to employee and manager" on public.checkins;
 create policy "checkins visible to employee and manager"
   on public.checkins for select to authenticated
   using (
     employee_id = auth.uid()
     or manager_id = auth.uid()
     or public.current_role() = 'hr'
   );

 drop policy if exists "employees create checkins" on public.checkins;
 create policy "employees create checkins"
   on public.checkins for insert to authenticated
   with check (employee_id = auth.uid());

-- Development plans
 drop policy if exists "development plans visible to employee manager hr" on public.development_plans;
 create policy "development plans visible to employee manager hr"
   on public.development_plans for select to authenticated
   using (
     employee_id = auth.uid()
     or exists (
       select 1 from public.profiles p
       where p.id = employee_id and p.manager_id = auth.uid()
     )
     or public.current_role() = 'hr'
   );

 drop policy if exists "employees create development plans" on public.development_plans;
 create policy "employees create development plans"
   on public.development_plans for insert to authenticated
   with check (employee_id = auth.uid());

 drop policy if exists "employees update development plans" on public.development_plans;
 create policy "employees update development plans"
   on public.development_plans for update to authenticated
   using (employee_id = auth.uid())
   with check (employee_id = auth.uid());

-- Feedback requests
 drop policy if exists "feedback requests visible to participants" on public.feedback_requests;
 create policy "feedback requests visible to participants"
   on public.feedback_requests for select to authenticated
   using (
     requester_id = auth.uid()
     or recipient_id = auth.uid()
     or public.current_role() = 'hr'
   );

 drop policy if exists "users create feedback requests" on public.feedback_requests;
 create policy "users create feedback requests"
   on public.feedback_requests for insert to authenticated
   with check (requester_id = auth.uid());

-- Peer feedback
 drop policy if exists "peer feedback visible when shared" on public.peer_feedback;
 create policy "peer feedback visible when shared"
   on public.peer_feedback for select to authenticated
   using (
     from_id = auth.uid()
     or to_id = auth.uid()
     or shared = true
     or public.current_role() = 'hr'
   );

 drop policy if exists "users write peer feedback" on public.peer_feedback;
 create policy "users write peer feedback"
   on public.peer_feedback for insert to authenticated
   with check (from_id = auth.uid());

-- One-on-ones
 drop policy if exists "one on ones visible to participants" on public.one_on_ones;
 create policy "one on ones visible to participants"
   on public.one_on_ones for select to authenticated
   using (
     employee_id = auth.uid()
     or manager_id = auth.uid()
     or public.current_role() = 'hr'
   );

 drop policy if exists "managers create one on ones" on public.one_on_ones;
 create policy "managers create one on ones"
   on public.one_on_ones for insert to authenticated
   with check (manager_id = auth.uid() or employee_id = auth.uid());

-- Recognition
 drop policy if exists "recognitions visible to signed in users" on public.recognitions;
 create policy "recognitions visible to signed in users"
   on public.recognitions for select to authenticated
   using (true);

 drop policy if exists "users create recognitions" on public.recognitions;
 create policy "users create recognitions"
   on public.recognitions for insert to authenticated
   with check (from_id = auth.uid());

-- Pulse surveys
 drop policy if exists "active pulse visible to signed in users" on public.pulse_surveys;
 create policy "active pulse visible to signed in users"
   on public.pulse_surveys for select to authenticated
   using (active = true or public.current_role() = 'hr');

 drop policy if exists "users submit pulse response" on public.pulse_responses;
 create policy "users submit pulse response"
   on public.pulse_responses for insert to authenticated
   with check (true);

-- Notifications
 drop policy if exists "own notifications visible" on public.notifications;
 create policy "own notifications visible"
   on public.notifications for select to authenticated
   using (user_id = auth.uid());

 drop policy if exists "own notifications update" on public.notifications;
 create policy "own notifications update"
   on public.notifications for update to authenticated
   using (user_id = auth.uid())
   with check (user_id = auth.uid());

-- Audit events
 drop policy if exists "hr can view audit events" on public.audit_events;
 create policy "hr can view audit events"
   on public.audit_events for select to authenticated
   using (public.current_role() = 'hr');

-- ------------------------------------------------------------
-- 11. Seed the first active pulse question if none exists
-- ------------------------------------------------------------

insert into public.pulse_surveys (question, active)
select 'I have clarity on what success looks like this quarter.', true
where not exists (
  select 1 from public.pulse_surveys where active = true
);

-- ------------------------------------------------------------
-- 12. Performance indexes
-- ------------------------------------------------------------

create index if not exists goals_employee_cycle_idx
  on public.goals(employee_id, cycle_id);

create index if not exists reviews_status_idx
  on public.performance_reviews(status);

create index if not exists checkins_employee_date_idx
  on public.checkins(employee_id, date desc);

create index if not exists notifications_user_read_idx
  on public.notifications(user_id, read);

create index if not exists development_plans_employee_idx
  on public.development_plans(employee_id, status);

create index if not exists feedback_requests_recipient_idx
  on public.feedback_requests(recipient_id, status);

commit;

-- ============================================================
-- After running this migration:
-- 1. Refresh the Supabase Table Editor.
-- 2. Confirm the new tables are visible.
-- 3. Add/confirm `title` and `manager_id` values in profiles.
-- 4. Refresh the local app at http://127.0.0.1:4173.
-- ============================================================
