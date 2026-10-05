# Northstar Performance

Northstar Performance is a production-oriented performance management system for employees, managers, and People Operations teams. The browser application now runs in **Supabase-only mode**: there are no seeded accounts, demo users, mock records, or localStorage fallback.

## Included workflows

The application supports goals and outcomes, progress and goal health, self-reviews, manager assessments, competency ratings, written feedback, continuous check-ins, one-on-one meetings, development plans, peer feedback, recognition, pulse surveys, notifications, calibration, review-cycle administration, organisation directory, analytics, CSV export, and audit-event storage.

## Configure Supabase

1. Create or open your Supabase project.
2. Run the original Version 1 schema if it has not already been applied.
3. Run `supabase_v2_migration.sql` for an existing Version 1 project.
4. Enable Supabase Email authentication or configure your chosen identity provider.
5. Create users in Supabase Auth.
6. Confirm each user has a matching row in `profiles` with `role`, `department`, `title`, and `manager_id`.
7. Open `config.js` and add the Supabase Project URL and public anon key.
8. Deploy the `app/` folder to Vercel or another static host.

The browser uses the public anon key. Never expose the Supabase service-role key.

## Run locally

```powershell
cd app
python -m http.server 4173
```

Open <http://localhost:4173>. The application will show the secure sign-in screen and will not load a workspace until Supabase is configured and the user has authenticated.

## Production data behaviour

Authentication is handled by Supabase Auth. After sign-in, the application loads profiles, review cycles, goals, performance reviews, feedback, check-ins, development plans, one-on-ones, recognitions, notifications, peer feedback, and pulse surveys from Supabase. Row-level security policies in the Version 1 schema and Version 2 migration control access by role and assignment.

For the remaining write operations, use the Supabase table policies and connect them to your preferred server-side or Edge Function write layer before enabling broad production use. This keeps sensitive review workflows auditable and prevents client-only mutation of performance records.
