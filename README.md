# PITX Bus Bay Booking

Provincial bus operators request a 30-minute bus bay slot; PITX staff review
and approve/reject each request, assigning a specific bay on approval.

- **Operators** submit a request: Route, Plate No. (picked from their
  approved vehicles), Date, and a 30-minute time slot (12:00-12:30 AM,
  12:30-1:00 AM, ... 48 slots a day, the terminal runs 24/7) - the Operator
  name isn't a form field, it's whatever's on the account (`profiles.operator_name`).
  They can filter their own request list by status (All / Approved / Pending
  / Declined), cancel a request while it's still pending, and hand an
  already-booked slot to another operator (see "Transferring a booking").
- **PITX staff** see every pending request, approve it (picking one of the
  bays not already taken for that slot) or reject it with an optional note,
  view a day-by-day schedule broken into 30-minute slots, manage the bay
  list, and create login accounts (there is no self-signup).

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
2. [`supabase/migrations/0002_booking_changes.sql`](supabase/migrations/0002_booking_changes.sql) -
   adds operator-initiated booking changes (see "Modifying a booking").
3. [`supabase/migrations/0003_vehicles.sql`](supabase/migrations/0003_vehicles.sql) -
   adds vehicle registration and the private `vehicle-docs` storage bucket.
4. [`supabase/migrations/0004_vehicle_plate_normalization.sql`](supabase/migrations/0004_vehicle_plate_normalization.sql) -
   fixes the duplicate-plate check to ignore case and spacing.
5. [`supabase/migrations/0005_vehicle_approvals.sql`](supabase/migrations/0005_vehicle_approvals.sql) -
   adds staff approval for vehicle registrations.
6. [`supabase/migrations/0006_vehicle_fields.sql`](supabase/migrations/0006_vehicle_fields.sql) -
   adds franchise number, route, body number, seat configuration, and seat
   count to vehicle registration.
7. [`supabase/migrations/0007_thirty_minute_slots.sql`](supabase/migrations/0007_thirty_minute_slots.sql) -
   switches booking time slots from hourly to 30-minute (backfills existing
   rows, no data lost).
8. [`supabase/migrations/0008_official_form_fields.sql`](supabase/migrations/0008_official_form_fields.sql) -
   replaces vehicle registration's field set to match the PITX/MWM
   Terminals paper form exactly, and adds the `operator_profiles` table for
   that form's company-level fields.
9. [`supabase/migrations/0009_four_hour_lockout.sql`](supabase/migrations/0009_four_hour_lockout.sql) -
   requires new/changed bookings to be at least 4 hours ahead of their slot.
10. [`supabase/migrations/0010_booking_transfers.sql`](supabase/migrations/0010_booking_transfers.sql) -
   lets an operator hand off a booking to another operator, subject to
   PITX staff approval (see "Transferring a booking").
11. [`supabase/migrations/0011_operator_directory.sql`](supabase/migrations/0011_operator_directory.sql) -
   adds `list_operator_accounts()`, a narrow read-only lookup so the
   transfer dialog can offer a dropdown of real operator accounts instead
   of a free-text username.
12. [`supabase/migrations/0012_transfer_recipient_confirmation.sql`](supabase/migrations/0012_transfer_recipient_confirmation.sql) -
   requires the receiving operator to confirm a transfer before staff can
   approve it.
13. [`supabase/migrations/0013_transfer_booking_snapshot.sql`](supabase/migrations/0013_transfer_booking_snapshot.sql) -
   snapshots the booking's date/slot/route/plate onto `booking_transfers`
   so the recipient's dashboard can display them without needing RLS
   access to a booking they don't own yet.
14. [`supabase/migrations/0014_transfer_sender_snapshot.sql`](supabase/migrations/0014_transfer_sender_snapshot.sql) -
   same idea for the sender's display name, for the same RLS reason.
15. [`supabase/migrations/0015_vehicle_or_cr_numbers.sql`](supabase/migrations/0015_vehicle_or_cr_numbers.sql) -
   re-adds per-vehicle OR No. and CR No. fields to vehicle registration.
16. [`supabase/seed.sql`](supabase/seed.sql) - optional starter data:
   20 bays named "Bay 1".."Bay 20". Skip it and add bays from the app's
   **Bays** page instead if you prefer.

Or, with the Postgres connection string from **Project Settings -> Database
-> Connection string** (use the **pooler** string unless your network has
IPv6 egress), apply both in one command:

```bash
DATABASE_URL="postgresql://postgres.<ref>:<password>@<pooler-host>:6543/postgres" \
  node scripts/run-migration.mjs --seed
```

`run-migration.mjs` tracks which files it's already applied (in a
`public._schema_migrations` table) and skips them on repeat runs - safe to
re-run any time you add a new migration, even against a database that's
already been migrated partway.

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

### 4b. Create operator accounts

Same chicken-and-egg situation as staff accounts until the Edge Function
below is deployed - operators can't self-signup, so bootstrap each one
from the command line:

```bash
npm run create-operator -- jacliner.ops ChangeMe123 "Jac Liner"
```

Every operator account has identical functionality - access is granted by
`role = 'operator'` in `profiles`, not per-account, so a new operator can
book, register vehicles, and transfer bookings exactly like any other the
moment its account exists.

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

## Modifying a booking

Operators can change a booking's route, plate number, date, or time slot
with the **Change** button on their dashboard. Every change goes back
through PITX staff:

| Booking was | After the operator saves a change |
|---|---|
| **Pending** | stays pending, with the new details |
| **Approved** | **reverts to pending and the bay is released** |

The warning about losing the bay is shown in the dialog before saving.
Rejected and cancelled bookings can't be edited - the operator submits a new
request instead.

Staff see a **"changed after approval"** badge on any pending request that
had previously been approved, so they know they're re-confirming a slot the
operator already held rather than granting a new one.

**4-hour lead time.** New requests and changes both need at least 4 hours'
notice before the scheduled slot:

- A new request's slot must be at least 4 hours away at submission time.
- An existing booking can't be changed once its *current* slot is within 4
  hours (the **Change** button disappears - only **Cancel** still shows);
  and whatever new slot is being requested must itself be at least 4 hours
  out.

Enforced in the database (an RLS check on insert, and inside
`request_booking_change()`), not just hidden in the UI - the app just
mirrors the same rule client-side so operators get an immediate answer
instead of a raw database error. Staff approve/reject and operator
cancellation are unaffected by this rule.

The new-request **Time slot** dropdown only ever lists slots that are
still at least 4 hours out for the selected date, so there's nothing to
reject in the first place - picking a date shows "No times left today"
once every remaining slot is too close, and re-picks the list whenever
the date changes.

Edits go through the `request_booking_change()` database function rather
than a direct update. Postgres RLS is row-level, not column-level, so a
policy loose enough to permit editing would also let an operator write
`assigned_bay_id` and assign themselves a bay; the function constrains the
change to those four fields and decides the status/bay transition
server-side.

## Transferring a booking

When one operator can't make a slot and has an internal arrangement for
another operator to cover it, the current owner opens **Transfer** next to
**Change**/**Cancel** on their dashboard and picks the receiving operator
from a dropdown (every other operator account, via
`list_operator_accounts()` - migration `0011`), enters their plate number,
and an optional reason. Same eligibility as **Change** (pending/approved,
at least 4 hours out, and no other transfer already awaiting review on
that booking).

The receiving operator sees it under **Incoming transfer requests** on
their own dashboard and must **Confirm** or **Decline** before anything
else happens - this is the actual "internal agreement" check, not just a
formality:

| Recipient response | Effect |
|---|---|
| **Confirm** | Moves to the **Transfer approvals** staff queue for a decision. |
| **Decline** | Request closed immediately; the booking is untouched and never reaches staff. |

Only once the recipient has confirmed can staff decide:

| Staff decision | Effect |
|---|---|
| **Approve** | Booking's operator, operator name, and plate are swapped to the receiving operator immediately - no further re-approval needed. The bay assignment and slot are untouched. |
| **Reject** | Booking is untouched; the request is closed. |

`approve_booking_transfer()` re-checks the recipient's confirmation
server-side (`recipient_response = 'accepted'`) - staff can't approve
around a missing confirmation even by calling the function directly.

Once approved, the **Schedule** and the receiving operator's **My
requests** both show the previous operator's name struck through, right
before the new one, e.g. ~~Genesis Trans~~ Batangas Star Lines. The
original operator will no longer see the booking in their own list - it
now belongs to the receiving operator's account.

Goes through the `request_booking_transfer()` / `accept_booking_transfer()`
/ `decline_booking_transfer()` / `approve_booking_transfer()` /
`reject_booking_transfer()` database functions (migrations `0010`, `0012`),
since crossing operator accounts needs its own authorization checks that
plain RLS can't express. The recipient's dashboard reads the booking's
date/slot/route and the sender's name off snapshot columns on
`booking_transfers` itself (migrations `0013`, `0014`) rather than joining
to `bookings`/`profiles` - RLS blocks both joins for an operator who isn't
the booking's owner or the profile's own account.

## Vehicle registration

Operators register vehicles from **My vehicles**, either by scanning a photo
of the LTO OR/CR or entering the details by hand. Every field stays
editable afterward regardless of how it was first entered.

The vehicle fields match the PITX/MWM Terminals paper registration form,
plus per-vehicle OR No. and CR No. (migration `0015_vehicle_or_cr_numbers.sql`):
Plate No., Case No., MV File #, OR No., CR No., Route, Bus No., Seating
capacity, Seat type (2x2/2x3), Aircon/Non-aircon, Date granted, and Date
expiry. (The form's company-level fields - name, owner, TIN, OR serial
number, booking system, NAU, two contacts - live separately on **Operator
profile**, one row per operator account, editable any time with no
approval step; that OR serial number is the *company's*, distinct from
each vehicle's own OR No. here.)

Registrations need PITX staff approval (**Vehicle approvals**), the same
shape as bookings:

| Vehicle was | After the operator edits it |
|---|---|
| Pending | stays pending, new details |
| **Approved** | **reverts to pending** - and stops appearing in the booking form until re-approved |

The booking form's Plate No. field is a dropdown sourced from the
operator's *approved* vehicles only - there's no free-text plate entry at
booking time. An operator with no approved vehicle sees a message pointing
them to **My vehicles** instead, with the request button disabled.

The plate number, expiry date, and OR/CR numbers are extracted from a
scanned photo; the rest of the form (case no., MV file #, etc.) isn't
printed on an OR/CR, so it's always typed in. Text extraction runs
entirely in the browser via
[Tesseract.js](https://github.com/naptha/tesseract.js) - no server, no API
key, no per-scan cost. The trade-off: it's raw OCR with no understanding of
the document's layout, so every extracted field is a **best-effort
guess**, always shown as an editable input (never auto-saved) alongside the
raw scanned text, so a wrong guess can be corrected by eye instead of by
re-scanning. The OR/CR guesses are the least reliable of the bunch - they
depend on finding a label like "OR NO." near the value, which varies more
across documents than the plate/expiry patterns do.

A private Supabase Storage bucket (`vehicle-docs`) holds the uploaded
photos, one folder per operator, with the same RLS-style access rule as
everything else: an operator can only reach their own folder, staff can
read all of them.

## How capacity works

Operators don't pick a specific bay - just a date and a 30-minute slot.
When staff approve a request they assign one of the bays not already taken
for that slot, so the number of **active bays is the cap** on approvals per
slot. A unique index enforces this in the database, so two staff approving
at once can't double-book a bay. The **Bays** page controls the active
count; the **Schedule** page shows approved-vs-capacity per slot for any
day (48 slots).

## Project structure

```
docs/                        THE SITE ITSELF (served by GitHub Pages)
  index.html                 Sign in
  dashboard.html             Operator: request form + own requests
  vehicles.html              Operator: register/edit vehicles (scan or manual)
  operator-profile.html     Operator: one-time company details (no approval)
  staff.html                 Staff: pending booking queue (approve / reject)
  vehicle-approvals.html     Staff: pending vehicle queue (approve / reject)
  transfer-approvals.html    Staff: pending booking-transfer queue (approve / reject)
  schedule.html              Staff: 30-minute-slot capacity grid for a date
  bays.html                  Staff: manage the bay list
  accounts.html              Staff: create logins (via Edge Function)
  assets/
    config.js                Supabase URL + public anon key
    app.js                   Shared client, auth guard, nav, helpers
    orcr-parser.js           Client-side OCR + OR/CR field-extraction heuristics
    pitx-logo.webp           PITX mark
    styles.css               Styles (light-theme only, explicit colors)

supabase/
  migrations/                Schema, RLS policies, booking-change function
  seed.sql                   Optional starter bays
  functions/create-account/  Edge Function for privileged account creation

scripts/
  create-staff.mjs           Bootstrap the first staff account
  create-operator.mjs        Create an operator account (until the Edge Function is deployed)
  run-migration.mjs          Apply migrations over a Postgres connection
  serve-docs.mjs             Serve docs/ locally, like GitHub Pages does
```
