# PITX Bus Bay Booking

Provincial bus operators request an hourly bus bay slot; PITX staff review
and approve/reject each request, assigning a specific bay on approval.

- **Operators** submit a request: Operator name, Route, Plate No., Date, and
  a one-hour slot (0:00-1:00, 1:00-2:00, ... the terminal runs 24/7). They
  can cancel their own request while it's still pending.
- **PITX staff** see every pending request, approve it (picking one of the
  bays not already taken for that hour) or reject it with an optional note,
  view a day-by-day hourly schedule, manage the bay list, and create login
  accounts (there is no self-signup).

Built with Next.js 16 (App Router) and Supabase (Postgres + Auth).

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and create a free project.
2. In the project dashboard, go to **Project Settings -> API**. You'll need:
   - **Project URL**
   - **anon public** key
   - **service_role** key (secret - keep this out of the browser)

## 2. Configure environment variables

Copy the example file and fill in the three values from step 1:

```bash
cp .env.local.example .env.local
```

## 3. Set up the database

Open your Supabase project's **SQL Editor** and run, in order:

1. [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) -
   creates the `profiles`, `bays`, and `bookings` tables plus Row Level
   Security policies.
2. [`supabase/seed.sql`](supabase/seed.sql) - optional starter data:
   20 bays named "Bay 1".."Bay 20". You can skip this and add bays later
   from the app's **Bays** page instead.

Alternatively, if you have your project's Postgres connection string (from
**Project Settings -> Database -> Connection string**; use the **pooler**
string, not "Direct connection", unless your network has IPv6 egress), you
can apply both files in one go without touching the SQL Editor:

```bash
DATABASE_URL="postgresql://postgres.<ref>:<password>@<pooler-host>:6543/postgres" \
  node scripts/run-migration.mjs --seed
```

## 4. Install dependencies

```bash
npm install
```

## 5. Create the first staff account

Regular accounts are created from the app's **Accounts** page, but that
page itself requires a staff login - so bootstrap the first one from the
command line:

```bash
npm run create-staff -- <username> <password> "Optional display name"
```

Example:

```bash
npm run create-staff -- pitx.admin ChangeMe123 "PITX Terminal Ops"
```

## 6. Run it

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000), sign in with the
staff account you just created, and use **Accounts** to create operator
(and additional staff) logins.

## How capacity works

Operators don't pick a specific bay - just a date and hour. When staff
approve a request they assign one of the bays not already taken for that
hour, so the number of active bays is the natural cap on how many requests
can be approved per hour. The **Bays** page shows/controls the active bay
count; the **Schedule** page shows approved-count-vs-capacity per hour for
any given day.

## Project structure

```
src/
  proxy.ts               Auth session refresh + role-based route protection
  lib/
    supabase/             Browser / Server Component / service-role clients
    auth.ts               getCurrentProfile() / requireRole() guards
    types.ts              Shared domain types + hour-slot helpers
    username.ts           username <-> synthetic-email mapping for login
  app/
    login/                Sign-in page
    dashboard/            Operator: request form + own requests
    staff/                Staff: pending queue (approve/reject)
    staff/schedule/        Staff: hourly capacity grid for a chosen date
    staff/bays/            Staff: manage the bay list
    staff/accounts/        Staff: create operator/staff logins
supabase/
  migrations/0001_init.sql Schema + RLS
  seed.sql                 Optional starter bays
scripts/create-staff.mjs   One-time bootstrap for the first staff account
```
