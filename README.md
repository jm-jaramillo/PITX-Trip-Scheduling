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

## How it's built

The app is plain HTML/CSS/JS in [`docs/`](docs/) that calls Supabase
directly from the browser. There is **no build step and no server** - GitHub
Pages serves the folder as-is.

Security model: the Supabase **anon key is public by
design** (it's in [`docs/assets/config.js`](docs/assets/config.js)) and only
grants what **Row Level Security** allows - see
[`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql). RLS
is the real access-control boundary; the client-side role checks only decide
which UI to render. The one privileged operation (creating accounts, which
needs the secret service_role key) runs in a Supabase **Edge Function**, so
that key never reaches the browser.

---

## Setup

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and create a free project.
2. In the dashboard, open **Project Settings -> API** and note:
   - **Project URL**
   - **anon / publishable** key (public - safe to commit)
   - **service_role / secret** key (**never** commit or expose to a browser)

### 2. Set up the database

Open the project's **SQL Editor** and run, in order:

1. [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql) -
   creates the `profiles`, `bays`, and `bookings` tables plus RLS policies.
2. [`supabase/seed.sql`](supabase/seed.sql) - optional starter data:
   20 bays named "Bay 1".."Bay 20". Skip it and add bays from the app's
   **Bays** page instead if you prefer.

Or, with the Postgres connection string from **Project Settings -> Database
-> Connection string** (use the **pooler** string unless your network has
IPv6 egress), apply both in one command:

```bash
DATABASE_URL="postgresql://postgres.<ref>:<password>@<pooler-host>:6543/postgres" \
  node scripts/run-migration.mjs --seed
```

### 3. Point the static site at your project

Edit [`docs/assets/config.js`](docs/assets/config.js) with your Project URL
and anon key.

### 4. Create the first staff account

The **Accounts** page needs a staff login to reach it, so bootstrap the
first one from the command line. This needs `.env.local` (copy
`.env.local.example` and fill it in - it is gitignored) plus `npm install`:

```bash
npm run create-staff -- pitx.admin ChangeMe123 "PITX Terminal Ops"
```

### 5. Deploy the account-creation Edge Function

Staff create accounts from the **Accounts** page, which calls the
[`create-account`](supabase/functions/create-account/index.ts) Edge
Function. Until it's deployed, that page shows "Could not reach the
account-creation service" and every other feature still works.

```bash
npm install -g supabase          # or: npx supabase
supabase login                   # opens your browser
supabase link --project-ref <your-project-ref>
supabase functions deploy create-account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected into deployed functions automatically - no secrets to set by hand.

### 6. Publish to GitHub Pages

In the repo: **Settings -> Pages -> Build and deployment**, set
**Source** = `Deploy from a branch`, **Branch** = `main`, **Folder** =
`/docs`, then Save. The site appears at
`https://<user>.github.io/<repo>/` within a minute or two.

---

## Running locally

```bash
npm run serve
```

Then open <http://localhost:3100>. (Opening the HTML files directly via
`file://` will **not** work - ES module imports need a real HTTP origin.)

> On Windows PowerShell, if `npm` is blocked by an execution-policy error,
> use `npm.cmd run serve` or run it from Command Prompt instead.

`npm install` is only needed for the `create-staff` / `migrate` helper
scripts - the site itself has no dependencies to install.

---

## How capacity works

Operators don't pick a specific bay - just a date and hour. When staff
approve a request they assign one of the bays not already taken for that
hour, so the number of **active bays is the cap** on approvals per hour. A
unique index enforces this in the database, so two staff approving at once
can't double-book a bay. The **Bays** page controls the active count; the
**Schedule** page shows approved-vs-capacity per hour for any day.

## Project structure

```
docs/                        THE SITE ITSELF (served by GitHub Pages)
  index.html                 Sign in
  dashboard.html             Operator: request form + own requests
  staff.html                 Staff: pending queue (approve / reject)
  schedule.html              Staff: hourly capacity grid for a date
  bays.html                  Staff: manage the bay list
  accounts.html              Staff: create logins (via Edge Function)
  assets/
    config.js                Supabase URL + public anon key
    app.js                   Shared client, auth guard, nav, helpers
    styles.css               Styles (light-theme only, explicit colors)

supabase/
  migrations/0001_init.sql   Schema + Row Level Security policies
  seed.sql                   Optional starter bays
  functions/create-account/  Edge Function for privileged account creation

scripts/
  create-staff.mjs           Bootstrap the first staff account
  run-migration.mjs          Apply migrations over a Postgres connection
  serve-docs.mjs             Serve docs/ locally, like GitHub Pages does
```
