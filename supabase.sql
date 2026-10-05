-- Northstar Performance / Supabase schema
create type public.user_role as enum ('employee', 'manager', 'hr');
create type public.review_status as enum ('not_started', 'goals_set', 'in_review', 'completed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  role public.user_role not null default 'employee',
  manager_id uuid references public.profiles(id),
  department text default 'General',
  avatar_color text default '#d2a96c',
  created_at timestamptz not null default now()
);
create table public.review_cycles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  period text not null,
  status text not null default 'open' check (status in ('open','closed')),
  due_date date,
  created_at timestamptz not null default now()
);
create table public.goals (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  cycle_id uuid references public.review_cycles(id),
  title text not null,
  description text,
  target_date date not null,
  progress integer not null default 0 check (progress between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.performance_reviews (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  cycle_id uuid references public.review_cycles(id),
  self_review text,
  manager_rating integer check (manager_rating between 1 and 5),
  status public.review_status not null default 'not_started',
  manager_reviewed_at timestamptz,
  completed_at timestamptz,
  unique(employee_id, cycle_id)
);
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.performance_reviews(id) on delete cascade,
  manager_id uuid not null references public.profiles(id),
  comment text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.review_cycles enable row level security;
alter table public.goals enable row level security;
alter table public.performance_reviews enable row level security;
alter table public.feedback enable row level security;

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path = public as $$ select role from public.profiles where id = auth.uid() $$;
create policy "profiles visible to signed in users" on public.profiles for select to authenticated using (true);
create policy "users update their profile" on public.profiles for update to authenticated using (id = auth.uid());
create policy "cycles visible to signed in users" on public.review_cycles for select to authenticated using (true);
create policy "hr manages cycles" on public.review_cycles for all to authenticated using (public.current_role() = 'hr') with check (public.current_role() = 'hr');
create policy "goals visible to signed in users" on public.goals for select to authenticated using (true);
create policy "employees create their goals" on public.goals for insert to authenticated with check (employee_id = auth.uid());
create policy "employees update their goals" on public.goals for update to authenticated using (employee_id = auth.uid()) with check (employee_id = auth.uid());
create policy "reviews visible to signed in users" on public.performance_reviews for select to authenticated using (true);
create policy "employees create self reviews" on public.performance_reviews for insert to authenticated with check (employee_id = auth.uid());
create policy "employees update self reviews" on public.performance_reviews for update to authenticated using (employee_id = auth.uid());
create policy "managers update assigned reviews" on public.performance_reviews for update to authenticated using (exists (select 1 from public.profiles p where p.id = employee_id and p.manager_id = auth.uid()));
create policy "feedback visible to signed in users" on public.feedback for select to authenticated using (true);
create policy "managers add feedback" on public.feedback for insert to authenticated with check (manager_id = auth.uid());

-- Create a profile row after signup (adjust role/manager_id from the HR console).
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles (id,name,email) values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Industry-standard continuous performance layer
create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  manager_id uuid references public.profiles(id),
  date date not null default current_date,
  mood text not null default 'good' check (mood in ('great','good','stretched')),
  wins text not null,
  blockers text,
  next_steps text not null,
  private_note text,
  created_at timestamptz not null default now()
);
create table public.development_plans (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  focus text not null,
  target_date date,
  status text not null default 'in_progress' check (status in ('not_started','in_progress','completed')),
  progress integer not null default 0 check (progress between 0 and 100),
  created_at timestamptz not null default now()
);
create table public.development_actions (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.development_plans(id) on delete cascade,
  action text not null,
  completed boolean not null default false,
  due_date date
);
create table public.feedback_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  review_id uuid references public.performance_reviews(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','completed','declined')),
  created_at timestamptz not null default now()
);
create table public.peer_feedback (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  review_id uuid references public.performance_reviews(id) on delete set null,
  feedback_type text not null default 'peer',
  comment text not null,
  shared boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.one_on_ones (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  manager_id uuid not null references public.profiles(id) on delete cascade,
  meeting_date date not null,
  agenda text,
  status text not null default 'scheduled' check (status in ('scheduled','completed','cancelled')),
  created_at timestamptz not null default now()
);
create table public.recognitions (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  value text not null,
  message text not null,
  created_at timestamptz not null default now()
);
create table public.pulse_surveys (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.pulse_responses (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.pulse_surveys(id) on delete cascade,
  score integer not null check (score between 1 and 5),
  created_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

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

create policy "checkins visible to employee and manager" on public.checkins for select to authenticated using (employee_id = auth.uid() or manager_id = auth.uid() or public.current_role() = 'hr');
create policy "employees create checkins" on public.checkins for insert to authenticated with check (employee_id = auth.uid());
create policy "development plans visible to employee manager hr" on public.development_plans for select to authenticated using (employee_id = auth.uid() or exists(select 1 from public.profiles p where p.id = employee_id and p.manager_id = auth.uid()) or public.current_role() = 'hr');
create policy "employees create development plans" on public.development_plans for insert to authenticated with check (employee_id = auth.uid());
create policy "feedback requests visible to participants" on public.feedback_requests for select to authenticated using (requester_id = auth.uid() or recipient_id = auth.uid() or public.current_role() = 'hr');
create policy "users create feedback requests" on public.feedback_requests for insert to authenticated with check (requester_id = auth.uid());
create policy "peer feedback visible when shared" on public.peer_feedback for select to authenticated using (from_id = auth.uid() or to_id = auth.uid() or (shared = true) or public.current_role() = 'hr');
create policy "users write peer feedback" on public.peer_feedback for insert to authenticated with check (from_id = auth.uid());
create policy "one on ones visible to participants" on public.one_on_ones for select to authenticated using (employee_id = auth.uid() or manager_id = auth.uid() or public.current_role() = 'hr');
create policy "managers create one on ones" on public.one_on_ones for insert to authenticated with check (manager_id = auth.uid() or employee_id = auth.uid());
create policy "recognitions visible to signed in users" on public.recognitions for select to authenticated using (true);
create policy "users create recognitions" on public.recognitions for insert to authenticated with check (from_id = auth.uid());
create policy "active pulse visible to signed in users" on public.pulse_surveys for select to authenticated using (active = true or public.current_role() = 'hr');
create policy "users submit pulse response" on public.pulse_responses for insert to authenticated with check (true);
create policy "own notifications visible" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "own notifications update" on public.notifications for update to authenticated using (user_id = auth.uid());
create policy "hr can view audit events" on public.audit_events for select to authenticated using (public.current_role() = 'hr');

-- Helpful indexes for dashboards and review queues
create index if not exists goals_employee_cycle_idx on public.goals(employee_id, cycle_id);
create index if not exists reviews_status_idx on public.performance_reviews(status);
create index if not exists checkins_employee_date_idx on public.checkins(employee_id, date desc);
create index if not exists notifications_user_read_idx on public.notifications(user_id, read);
