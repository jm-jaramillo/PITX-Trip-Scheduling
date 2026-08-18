# PITX Bus Bay Booking

Provincial bus operators request a 30-minute bus bay slot; PITX staff review
and approve/reject each request, assigning a specific bay on approval.

- **Operators** submit a request: Route (picked from the fixed list of
  PITX-served provincial routes), Plate No. (picked from their
  approved vehicles), Date, and a 30-minute time slot (12:00-12:30 AM,
  12:30-1:00 AM, ... 48 slots a day, the terminal runs 24/7) - the Operator
  name isn't a form field, it's whatever's on the account (`profiles.operator_name`).
  They can filter their own request list by status (All / Approved / Pending
  / Declined), cancel a request while it's still pending, hand an
  already-booked slot to another operator (see "Transferring a booking"),
  and see their own approved slots with bay assignments on **My schedule**.
- **PITX staff** see every pending request, approve it (picking one of the
  bays not already taken for that slot) or reject it with an optional note,
  view a day-by-day schedule broken into 30-minute slots, manage the bay
  list, browse every operator's company profile, and create or delete
  login accounts (there is no self-signup).

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
16. [`supabase/migrations/0016_transfer_recipient_vehicles.sql`](supabase/migrations/0016_transfer_recipient_vehicles.sql) -
   adds `list_operator_vehicles()`, and validates a transfer's plate
   against the receiving operator's approved vehicles server-side.
17. [`supabase/migrations/0017_operator_profile_contact_email.sql`](supabase/migrations/0017_operator_profile_contact_email.sql) -
   adds `contact1_email`/`contact2_email` to `operator_profiles`.
18. [`supabase/migrations/0018_vehicle_supporting_document.sql`](supabase/migrations/0018_vehicle_supporting_document.sql) -
   adds `supporting_doc_path`/`supporting_doc_name` to `vehicles`.
19. [`supabase/migrations/0019_vehicle_change_supporting_document.sql`](supabase/migrations/0019_vehicle_change_supporting_document.sql) -
   lets `request_vehicle_change()` update the supporting document too.
20. [`supabase/migrations/0020_bay_gates.sql`](supabase/migrations/0020_bay_gates.sql) -
   adds `bays.gate`, tags Gates 2/4's existing bays, and adds the bays
   (21-23, 33-36) the gate guide references that didn't exist yet.
21. [`supabase/seed.sql`](supabase/seed.sql) - optional starter data:
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

### 5. Deploy the account-creation and account-deletion Edge Functions

Staff create accounts from the **Accounts** page, which calls the
[`create-account`](supabase/functions/create-account/index.ts) Edge
Function, and delete them with the
[`delete-account`](supabase/functions/delete-account/index.ts) Edge
Function. Until each is deployed, that page's create/delete action shows
"Could not reach the account-creation/deletion service" and every other
feature still works.

```bash
npm install -g supabase          # or: npx supabase
supabase login                   # opens your browser
supabase link --project-ref <your-project-ref>
supabase functions deploy create-account
supabase functions deploy delete-account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected into deployed functions automatically - no secrets to set by hand.

Until `delete-account` is deployed, delete an account from the command
line instead (same underlying logic):

```bash
npm run delete-account -- jacliner.ops
```

Deleting an account cascades to that operator's own vehicles, but
**not** to any bookings it made or any approve/reject decisions it made
as staff (`bookings.operator_id`/`decided_by` deliberately don't
cascade) - deleting an account that's still referenced there fails with
a clear "still has bookings ... on record" error rather than silently
orphaning that history. Staff also can't delete their own account (no
"Delete" button next to their own row on **Accounts**, and the Edge
Function rejects it server-side too).

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
`list_operator_accounts()` - migration `0011`), then picks **their plate
no.** from a second dropdown sourced from *that* operator's own approved
vehicles (`list_operator_vehicles()` - migration `0016`) - not free text,
so a transfer can't name a plate the receiving operator hasn't actually
registered and had approved. Plus an optional reason. Same eligibility as
**Change** (pending/approved, at least 4 hours out, and no other transfer
already awaiting review on that booking).

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
the booking's owner or the profile's own account. `request_booking_transfer()`
also re-validates the chosen plate server-side against the receiving
operator's approved vehicles, so a raw RPC call can't submit a plate the
dropdown wouldn't have offered.

## Vehicles database (staff)

A read-only staff page listing **every** registered vehicle across
**every** operator, any status - not just the pending queue on **Vehicle
approvals**. Filterable by status (All / Approved / Pending / Declined)
and searchable by plate no., operator, or bus no. Each row links to
whatever documents that vehicle has on file (OR/CR scan photo,
supporting document), resolved as signed URLs the same way the other
pages that touch the `vehicle-docs` bucket already do. No new RLS
needed - `vehicles`' existing `select` policy already lets staff read
every row regardless of status (`operator_id = auth.uid() or is_staff()`,
migration `0003`); this is simply the first UI built specifically for
browsing the whole fleet rather than only the pending queue.

## Operator profiles (staff)

A read-only staff page listing every operator account's company details
(the same fields the operator fills in on their own **Operator profile**),
plus a search box (username, operator name, or company name). Accounts
that haven't submitted a profile yet still show up in the list - tagged
"no profile yet" rather than being omitted - since knowing *who hasn't*
filled theirs in is as useful to staff as seeing the ones who have. No
new RLS needed: `operator_profiles`' existing `select` policy already
lets staff read every row (`operator_id = auth.uid() or is_staff()`,
migration `0008`), this is just the first UI built on top of it.

Contact person 1/2 also have an **Email** field (migration
`0017_operator_profile_contact_email.sql`) alongside the existing
name/number/position - added when importing the company's real operator
database, which has emails but the paper form's contact fields don't ask
for one.

### Route dropdown

A booking's **Route** is picked from `ROUTES` in
[`docs/assets/app.js`](docs/assets/app.js) rather than typed freehand, so
it can't drift into near-duplicate variants of the same route
(`"PITX - Batangas"` vs `"Batangas"` vs `"pitx batangas"`). Sourced from
the operator database spreadsheet's "Sheet5" (destination/province/region,
filtered to "Operational" status) - **83 routes** covering every region
PITX serves, not just the original 8 Northern Luzon ones. The dropdown
groups them into three `<optgroup>`s matching the gate groups below
("North (Gate 5)", "Cavite/Batangas/Laguna/Quezon/Mindoro (Gate 2)",
"Bicol/Visayas/Mindanao (Gate 4)") rather than one 83-item flat list.

The **Change** dialog preserves a booking's existing route even if it
predates the current list (tagged "(not in the current list)"), same
reasoning as the plate dropdown's "no longer approved" fallback -
re-opening the dialog never silently loses a value it can't otherwise
represent. This also covers the original 8 routes' slightly different
phrasing (e.g. "Tuguegarao City, Cagayan" is now "Tuguegarao, Cagayan") -
existing bookings using the old phrasing aren't renamed, they just show
under that fallback if edited.

### Real operator data import (17 Aug)

The operator accounts' company profiles were populated from a
company-provided "Operator Database" spreadsheet (Operator List / Operator
Profile / Routes sheets). This ran in two passes: first the 23 accounts
that already existed, then - once the user pointed out the spreadsheet had
many more operators than that - **45 more accounts created from scratch**
for every remaining distinct company in the Operator Profile sheet
(bringing the total to 68), same password convention as every other
account here (`TestPass123`).

Several account groupings needed a judgment call, since the spreadsheet
groups companies differently than the app's accounts do - each resolved
with the user before writing anything:

- **Jac Liner / Jam Liner / Jam Liner-LLI** (3 separate accounts) - the
  spreadsheet has one combined row ("JAC LINER INC/ LLI/ JAM LINER") plus
  two standalone JAM LINER rows. Split per the user's direction: Jac Liner
  gets the combined row's manager; Jam Liner gets both standalone rows'
  contacts; Jam Liner/LLI gets the combined row's dispatcher (the only
  contact tied to "LLI" specifically).
- **Amihan / Philtranco** (2 separate accounts) - the spreadsheet has
  standalone rows for each, plus a combined row with 5 more teller/
  dispatcher contacts. Per the user: each account keeps only its own
  standalone-row contacts; the combined row's 5 contacts aren't assigned
  to either.
- **Bataan Transit Co., Inc / First North Luzon Transit, Inc.** and
  **Eastern Metropolitan Bus Corp / Rizal Metrolink Inc** - each pair
  shares identical (or near-identical) contact info in the spreadsheet,
  suggesting the same people running two legally-distinct companies. Per
  the user: kept as separate accounts, each with its own copy of the
  shared contact(s).
- **Elavil Tours Phils Inc / Elavil Transit** - related by name and
  family (Villamonte), but different contacts/regions. Per the user: kept
  as two separate accounts, matching how the spreadsheet already lists
  them as separate rows.
- **San Agustin Trans Service Corp / St. Anthony of Padua Transport
  System, Inc.** - split out from a 3-way combined row that also included
  Batman Starexpress Corporation (already created separately from its own
  standalone row). Per the user: created as their own accounts too, with
  the combined row's 5 contacts split across San Agustin and St. Anthony
  (2 each), leaving Batman Starexpress's already-assigned contacts
  untouched.

No company owner / TIN / OR-serial-number / booking-system / NAU data
exists in the spreadsheet, so those fields are empty for every account -
including clearing Genesis Transport's previous *fictitious test* values
in those fields, since real source data now takes priority over
placeholder test data. Verified afterward that all pre-existing accounts
matched something in the spreadsheet, so no account was left with a
"blank" profile to delete.

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

### Supporting document

Separate from the OR/CR scan photo, an operator can attach one
**supporting document** per vehicle (franchise/CPC, insurance, etc.) -
any image or PDF (migration `0018_vehicle_supporting_document.sql`),
uploaded to the same `vehicle-docs` bucket under
`<operator_id>/supporting/<uuid>.<ext>`, so it's covered by the bucket's
existing per-operator-folder storage policies with no changes needed
there.

Available when registering a new vehicle, and editable afterward -
re-opening **Edit vehicle** shows "Current: `<filename>` - choose a file
below to replace it" if one's already attached, and keeps it unchanged if
no new file is chosen (`request_vehicle_change()`'s signature grew two
parameters for this - migration `0019`, same drop-and-recreate reasoning
as every prior signature change, since operators can only edit a vehicle
through this function, not a direct UPDATE - migration 0005 removed their
direct UPDATE policy entirely). Staff see a **"View supporting document
(`<filename>`)"** link on **Vehicle approvals** alongside the existing
OR/CR photo link, when one was uploaded.

### LTFRB masterlist import

Vehicles can also arrive in bulk from PITX's own official masterlist
rather than being registered one at a time by an operator - `vehicles`
gained an `ltfrb_status` column for this (migration
`0021_vehicle_ltfrb_status.sql`): `active`, `inactive`, `no_record`, or
`ltfrb_verified`, plus a `source = 'masterlist_import'` value alongside
the existing `manual`/`scanned` ones. It's **null** for every vehicle an
operator registers themselves through **My vehicles** - that column only
applies to the bulk import, and a null value is always treated as
eligible.

Imported vehicles insert straight in as `status = 'approved'` (skipping
the normal Vehicle approvals queue, since this masterlist *is* PITX's own
vetting), but only `active`/`ltfrb_verified` ones are eligible for the
booking form's plate dropdown - `inactive`/`no_record` units are excluded
even though `status` says approved. This is enforced in two places that
both need it (migration `0022_ltfrb_status_transfer_eligibility.sql`):
`dashboard.html`'s own vehicle query, and `list_operator_vehicles()` (the
function the transfer dialog's plate dropdown and
`request_booking_transfer()`'s server-side validation both call) - an
inactive/no_record vehicle can't be booked *or* accepted into via a
transfer. **My vehicles** shows each vehicle's LTFRB status as a badge and
a banner explaining why an approved-but-inactive vehicle isn't in the
booking form, so it doesn't look like it silently vanished; **Vehicles**
(the staff fleet database, `vehicles-database.html`) shows the same badge
across every operator.

An import run matches each masterlist row's operator name against
existing operator accounts (normalizing punctuation/case and stripping
common suffixes like "Inc."/"Transport"/"Corp.", plus a short manual
alias list for abbreviations and misspellings a plain string match can't
bridge), creates a new operator account for any real company with no
existing match, and skips rows with no identifiable operator at all. Bulk
inserts use `on conflict (operator_id, <normalized plate>) do nothing`
against the existing per-operator plate unique index, so re-running an
import (or a batch that partially failed) is safe - already-imported
rows are silently skipped rather than duplicated or erroring the whole
batch.

**Fleet database pagination:** `vehicles-database.html`'s query has no
`.range()`, and Supabase/PostgREST caps a single request at 1000 rows by
default - past that, the query silently truncates rather than erroring.
The masterlist import pushed the table past 1000 rows for the first
time, surfacing this; the page now pages through with `.range()` until a
page comes back short, so the count keeps growing correctly. No other
page in the app queries an unbounded table like this (bookings/vehicles
elsewhere are always filtered by date, operator, or pending-status, which
stay well under 1000).

## My schedule (operators)

A read-only **timeline** of the operator's own **approved** bookings -
grouped by day, most recent day first, each day's own slots connected
top-to-bottom by a dot-and-line rail in time order, showing the assigned
bay, route, and plate per slot. "Where do I actually need to show up,"
not a data-entry table. Today is tagged and highlighted; past days
render dimmed but stay in place rather than disappearing. Pending and
declined requests don't
appear here (see **My requests** for the full picture, including
revision/transfer status). Defaults to **Upcoming** (today onward);
switch to **All** to include past days. No new tables or functions -
it's the same `bookings` row RLS already scopes to `operator_id = auth.uid()`,
just filtered to `status = 'approved'` and presented as a timeline rather
than the request-management table on **My requests**.

## How capacity works

Operators don't pick a specific bay - just a date and a 30-minute slot.
When staff approve a request they assign one of the bays not already taken
for that slot, so the number of **active bays is the cap** on approvals per
slot. A unique index enforces this in the database, so two staff approving
at once can't double-book a bay. The **Bays** page controls the active
count; the **Schedule** page shows approved-vs-capacity per slot for any
day (48 slots).

### Gates and route-based bay suggestions

Bays are grouped into gates, matching the terminal's actual layout
(migration `0020_bay_gates.sql`):

| Gate | Bays | Routes |
|---|---|---|
| Gate 2 | 8-11 | Cavite, Batangas, Laguna, Quezon, Mindoro (Regions IV-A/IV-B) |
| Gate 4 | 18-23 | Bicol, Visayas, Mindanao (Regions V-XIII) |
| Gate 5 | 33-36 | North (CAR, Regions I-III) |

`ROUTE_GATES` in [`docs/assets/app.js`](docs/assets/app.js) maps each of
the 83 entries in `ROUTES` to its gate, derived from Sheet5's REGION
column rather than hand-picked per destination - add a route to `ROUTES`
and this map together to keep them in sync. Both **Pending requests**'
approval dropdown and **Schedule**'s bay
reassignment control group bay options into a **Suggested (Gate N)**
group first, then **Other bays** - a suggestion, not a hard restriction,
since staff may need to override it (the suggested gate is full, or the
route has no gate mapped). Bays outside a named gate (1-7, 12-17, 24-32)
are general-purpose and always appear under "Other bays".

On **Pending requests**, the bay dropdown comes **pre-selected** with the
lowest-numbered bay in the suggested gate (or the lowest-numbered
available bay if the route has no gate) - approving is a single click,
no bay has to be picked by hand. Staff can still change the dropdown
first to assign a different bay; the pick is a default, not forced.

Adding these gates' bays (21-23, 33-36 didn't exist before) raised active
bay count from 20 to 27, which directly raises the per-slot approval cap
described above.

On the operator's own booking form ([`docs/dashboard.html`](docs/dashboard.html)),
if the chosen route/date/time combination's gate has no bay left (every
bay in that gate is already assigned to an *approved* booking for that
slot), an amber hint appears under the time slot field naming the
nearest open times that still have room in that gate, each a clickable
button that swaps the slot in place. This is advisory only, not a hard
block - submitting anyway still works, since staff can fall back to a
bay in another gate exactly as described above; the hint just saves the
operator a round trip through a request that would otherwise get bumped
to an unrelated gate. It only fires when the route maps to a real gate
and both a date and slot are already picked; picking a suggested slot
re-runs the check immediately, in case that slot fills up too.

### Reassigning an approved booking's bay (staff)

Staff can move an already-approved booking to a different bay from
**Schedule** - e.g. correcting a mistaken assignment, or freeing a bay up
for an operational reason. Each approved booking's bay tag is replaced
with a small select (grouped the same Suggested/Other way as approval)
plus a **Save** button; picking a bay already taken by another approved
booking in that same slot is impossible from the dropdown itself (it's
excluded from the options), and the same unique-index constraint that
protects approval also protects this as a defense-in-depth backstop.
This is a direct table update (`bookings.assigned_bay_id`), not a new
RPC - staff already have unrestricted UPDATE rights on `bookings`
(migration `0001`).

## Project structure

```
docs/                        THE SITE ITSELF (served by GitHub Pages)
  index.html                 Sign in
  dashboard.html             Operator: request form + own requests
  my-schedule.html           Operator: own approved slots + bay assignments
  vehicles.html              Operator: register/edit vehicles (scan or manual)
  operator-profile.html     Operator: one-time company details (no approval)
  staff.html                 Staff: pending booking queue (approve / reject)
  vehicle-approvals.html     Staff: pending vehicle queue (approve / reject)
  vehicles-database.html     Staff: every registered vehicle, any status, searchable
  transfer-approvals.html    Staff: pending booking-transfer queue (approve / reject)
  schedule.html              Staff: 30-minute-slot capacity grid for a date
  bays.html                  Staff: manage the bay list
  operator-profiles.html     Staff: read-only view of every operator's company profile
  accounts.html              Staff: create/delete logins (via Edge Functions)
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
  functions/delete-account/  Edge Function for privileged account deletion

scripts/
  create-staff.mjs           Bootstrap the first staff account
  create-operator.mjs        Create an operator account (until the Edge Function is deployed)
  delete-account.mjs         Delete an account (until the Edge Function is deployed)
  run-migration.mjs          Apply migrations over a Postgres connection
  serve-docs.mjs             Serve docs/ locally, like GitHub Pages does
```
