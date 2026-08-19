# Project log

Build history for the PITX Bus Bay Booking app.
Repo: <https://github.com/jm-jaramillo/PITX-Trip-Scheduling>
Live: <https://jm-jaramillo.github.io/PITX-Trip-Scheduling/>

---

## Requirements as agreed

| Decision | Choice |
|---|---|
| Who requests | Provincial bus operators |
| Who approves | PITX staff |
| Request fields | Operator, Route, Plate No., Date, Hour |
| Slot length | 30 minutes, 24/7 (48 slots/day; originally 1 hour, changed 13 Aug) |
| Bay selection | Operators do **not** pick a bay; staff assign one on approval |
| Capacity | Active bay count caps approvals per hour |
| Accounts | Staff-created only, no self-signup |
| Login | Username + password |
| Conflicts | A bay can't be double-booked for the same hour |
| Modifications | Operators may change a booking; every change needs staff re-approval |
| Vehicle registration | Operators scan or manually enter their LTO OR/CR; needs staff approval |
| Plate selection at booking | Dropdown of the operator's *approved* vehicles only, not free text |
| Visual identity | Matches the PITX Terminal Ops design system (shared logo, palette, type) |
| Device support | Must be readable and usable on mobile, not just desktop |
| Request filtering | Operators can filter their own requests: All / Approved / Pending / Declined |
| Vehicle detail | Matches the official PITX/MWM Terminals paper form exactly (superseded 14 Aug; originally franchise no./body no./seat config, replaced not extended) |
| Operator profile | One-time company details (name, owner, TIN, OR serial no., booking system, 2 contacts), no approval needed |
| Booking lead time | New requests and changes both need at least 4 hours' notice before the scheduled slot |
| Booking transfer | An operator may hand off a booked slot to another operator (internal agreement); needs PITX staff approval; schedule shows the previous operator struck through next to the new one |

---

## Timeline

### 1. `53940bf` — Scaffold (12 Aug)

The machine had **no Node.js, Python, or Docker**, so nothing could be built
or run. Node.js LTS was installed, then Next.js 16 was scaffolded.

Next.js 16 ships a warning that its APIs differ from older versions, so its
bundled docs were read before writing code — this is why the app used
`proxy.ts` (Next 16's rename of `middleware.ts`) and async `cookies()`.

### 2. `86e9e73` — First working app (12 Aug)

Full booking app on Next.js + Supabase: login, operator dashboard, staff
approval queue, schedule grid, bay management, account creation.

Supabase setup along the way:

- Created `profiles`, `bays`, `bookings` with Row Level Security.
- **Direct DB connection failed** (`ENOTFOUND`): Supabase's direct host is
  IPv6-only and this network has no IPv6 route. Switched to the **pooler**
  connection, which is IPv4 — noted in the README so it isn't rediscovered.
- Seeded 20 bays, bootstrapped the first staff account.

Verified end-to-end in a browser against the real database: request →
approve with bay assigned → schedule updated → operator saw the result.
Rejection with a reason verified too.

### 3. `041214c` — Two UI fixes (12 Aug)

- **Bay sort order.** Bays sorted alphabetically, so Bay 10 came before
  Bay 2. Added a numeric-aware comparison.
- **Form text colour.** Inputs had no explicit colour, so in OS dark mode
  they rendered near-white on white. Set black explicitly on the booking
  form, login, Accounts, and the staff approve/reject fields.

### 4. `8cc5d3f` — Rewritten as a static site (12 Aug)

**Why:** the goal was hosting on GitHub Pages, which serves static files
only and cannot run a server. The Next.js app needed one for auth, queries,
and approvals — which is why the Pages URL only ever showed the README.

Rebuilt the UI as plain HTML/CSS/JS in `docs/`, calling Supabase directly
from the browser. No build step, no server.

Security consequence, worth understanding:

- The **anon key is now public** (in `docs/assets/config.js`). This is by
  design — it only grants what **Row Level Security allows**. RLS is now the
  *only* thing protecting the data, so policies matter more than before.
- The **service_role key can never ship to a public page**. Account creation
  needs it, so that moved into a Supabase **Edge Function**
  (`create-account`) which re-verifies the caller is staff before acting.

Added `scripts/serve-docs.mjs` to serve `docs/` locally the way Pages does.

### 5. `bb78c09` — Removed Next.js (12 Aug)

Deleted the parallel Next.js build (**−8,812 lines**) so the repo has one
implementation. `package.json` trimmed from 385 packages to 2 direct
dependencies, now only needed for the helper scripts — the site itself has
no dependencies and no build step.

### 6. `ab3faab` — Operator booking changes (13 Aug)

Operators can now change route, plate, date, or hour via a **Change**
button. Every change re-enters the staff queue:

| Booking was | After the change |
|---|---|
| Pending | stays pending, new details |
| **Approved** | **reverts to pending, bay released** |

The dialog warns before an approved bay is given up. Rejected and cancelled
bookings stay closed. Staff see a **"changed after approval"** badge so a
re-approval is distinguishable from a new request.

Two implementation notes:

- Edits run through a `request_booking_change()` database function, not a
  direct update. Postgres RLS is **row**-level, not **column**-level — any
  policy permissive enough to allow editing would also let an operator write
  `assigned_bay_id` and assign themselves a bay. The function limits changes
  to those four fields and owns the status transition.
- The migration ends with `NOTIFY pgrst, 'reload schema'`. Without it the
  API serves a cached catalogue and rejects the new function with
  *"permission denied"* despite a correct grant. Worth remembering for any
  future function added through the SQL Editor.

### 7. `aa860fa` — Restyled to match PITX Terminal Ops (13 Aug)

A design handoff bundle (`Terminal operator interface-handoff.zip`) showed
the full PITX Terminal Ops design system — six operational roles, a shared
logo, an oklch blue-slate palette, Manrope/Inter type. This app is one
slice of that system (provincial bay booking), so it was restyled to read
as part of the suite rather than a separate tool: the PITX mark in a dark
sticky control bar, the same palette and type pairing, page headers
following the source's eyebrow-plus-title pattern, and a KPI row on the
Schedule page mirroring the ops dashboard.

Deliberately *not* done: the handoff's fuller model (4 gates × 8 bays,
region-locked gate access, RFID/GPS automation, penalty fees) — this app
only builds the bay-booking slice it already had, restyled, not a rebuild
to match every detail of the reference.

### 8. `9156210` — Vehicle registration via on-device OCR (13 Aug)

Operators can register a vehicle by photographing its LTO OR/CR or typing
the details in by hand. Text extraction runs entirely in the browser via
Tesseract.js — no server, no API key, no per-scan cost — traded
deliberately against accuracy: it's raw OCR with no understanding of the
document's layout, so every extracted field is shown as an editable input
next to the raw scanned text, never auto-saved.

Two real bugs found by testing against a synthetic OR/CR image (not just
inspecting the code):

- The duplicate-plate index normalized case but not whitespace, so
  `"NGP 2481"` and `"ngp2481"` registered as different vehicles. Fixed with
  a follow-up migration comparing on letters+digits only.
- The CR-number heuristic matched the document's own title
  (*"CERTIFICATE OF REGISTRATION"*) before reaching the real `"CR NO:"`
  line. Restructured the label search to try specific abbreviations first,
  across every line, with descriptive phrases as a last resort.

### 9. `a186bfa` — Vehicle approval + plate-number dropdown (13 Aug)

Vehicle registrations now need staff approval, the same shape as bookings
(pending → approved/rejected; editing an approved vehicle reverts it to
pending). The booking form's Plate No. field changed from free text to a
dropdown sourced from the operator's *approved* vehicles only — closing
the gap where a request could reference a vehicle nobody had verified.

Verified with a real penetration attempt, not just a policy read-through:
ran a raw SQL `UPDATE ... SET status = 'approved'` as the operator's own
authenticated database role, bypassing the app entirely. **Zero rows
affected** — confirming RLS blocks self-approval at the database level,
not just in the UI.

### 10. `f6a9e4a` — Made tables usable on mobile (13 Aug)

Testing at 375px (not just resizing the window and eyeballing it) found
every data table had columns silently cut off past the first two — on the
Schedule page this meant staff couldn't see who was booked into a slot at
all without scrolling the table sideways in its own tiny viewport, and
rows with hidden multi-line content rendered with large blank gaps.

Below 640px, each table row now stacks into a card with the column header
as a label above its value. The 20-row Bays table is exempted
(`.table-plain`) since it already read fine as a compact table and
stacking it would've meant more scrolling for no benefit.

### 11. `430bad6` — Request filters + expanded vehicle fields (13 Aug)

Two additions:

- **Status filter on the operator's "My requests" list**: All / Approved /
  Pending / Declined tabs above the table. Client-side only - all of an
  operator's own bookings are already fetched (RLS-scoped to just their
  rows), so filtering re-renders from the cached list rather than
  re-querying per tab.
- **Five more fields on vehicle registration**: franchise number, route,
  body number, seat configuration, and number of seats. Entered the same
  way in either registration mode (scan or manual) - not extracted by OCR,
  since these generally aren't printed on an OR/CR the way plate/OR/CR
  numbers are. `request_vehicle_change()`'s signature changed to carry the
  new fields, which required dropping and recreating the function -
  Postgres won't let a function's parameter list change via `CREATE OR
  REPLACE`. Staff now see all five on the Vehicle approvals page too.

Verified end-to-end: registered a vehicle with all five fields, confirmed
they appear on the operator's list, staff's approval queue, prefill
correctly into the edit dialog, and round-trip through
`request_vehicle_change()` on an edit. Verified each status-filter tab
shows exactly the matching subset against a real mixed-status list (2
approved, 2 pending, 2 rejected).

### 12. `ab4466d` — 30-minute time slots (13 Aug)

Bookings switched from hourly slots (24/day) to 30-minute slots (48/day).
`bookings.hour` (0-23) became `bookings.slot` (0-47; slot N covers
`[N*30, N*30+30)` minutes past midnight) - not just a rename, a full
column swap: existing rows were backfilled (`slot = hour * 2`) before the
old `hour` column was dropped, so no booking data was lost in the cutover.

`request_booking_change()`'s signature changed (`p_hour` → `p_slot`),
which meant dropping and recreating the function - same reason 0006 and
0007's vehicle-side counterpart needed it: Postgres won't allow a
parameter-list change via `CREATE OR REPLACE`.

Every page referencing bookings by hour was updated: the request form and
edit dialog (now a 48-option time-slot dropdown), the staff pending queue
(bay-availability grouping key), and the Schedule page, which now renders
48 rows instead of 24 and relabels its KPI from "Hours at capacity" to
"Slots at capacity."

Verified end-to-end against the live database (not just visually): backfill
correctness confirmed directly in Postgres (a booking at 4:00 PM /
`hour = 16` came out as `slot = 32`, matching `16 * 2`); submitted a new
booking at slot 17 and confirmed it rendered as "8:30 AM – 9:00 AM"; edited
it to slot 18 through `request_booking_change()` and confirmed it moved to
"9:00 AM – 9:30 AM"; approved it as staff and confirmed the Schedule page
showed exactly 48 rows with the booking at the correct row, correct
capacity count, and the assigned bay.

### 13. `a801b48` — Vehicle fields match the official PITX/MWM form; operator profile page (14 Aug)

The user supplied a photo of the actual PITX/MWM Terminals paper
registration form. Vehicle registration's field set was **replaced**
(not extended) to match its per-vehicle table exactly: Case No., MV File
#, Route, Bus No., Seating capacity, Seat type (2x2/2x3), Aircon/
Non-aircon, Date granted, Date expiry. Make/model, body type, OR No., CR
No., franchise number, and free-text seat configuration - all added in
earlier sessions - are gone from the vehicle level; the paper form has
no per-vehicle OR/CR, just one operator-level "Serial Number (OR)".

That company-level top section of the form (company name/owner, TIN, OR
serial number, booking system, NAU, two contacts) became a new
**Operator profile** page and `operator_profiles` table - one row per
operator, editable any time with no approval step, since there's nothing
privileged to protect there (unlike a booking's bay or a vehicle's
approval status).

`request_vehicle_change()`'s signature changed completely (new
parameter list for the new fields), meaning drop-and-recreate again -
the fourth time a field-set change in this project has needed it, since
`CREATE OR REPLACE` can't alter a function's parameters.

**Two real problems hit and fixed, not just designed around:**

- **The migration runner itself broke.** `run-migration.mjs` always
  replayed every `.sql` file, including 0001, which still literally says
  `hour` - a column 0007 later renamed to `slot`. Even guarded by `IF
  NOT EXISTS`, Postgres resolves column references during parse/analyze
  *before* checking whether the index already exists, so replaying 0001
  against an already-migrated database failed outright on `column
  "hour" does not exist`. This wasn't a one-off: it's a structural gap
  that would recur on every future rename or drop. Fixed properly with
  a `public._schema_migrations` tracking table so already-applied files
  are skipped on replay, rather than patching around this one instance.
- **`dashboard.html`'s vehicle dropdown broke silently.** It still
  selected the now-dropped `make_model` column to show alongside each
  plate number, and the browser's own network-level error obscured
  which request was failing - `read_console_messages` reported a bare
  "400", and the network-inspection tool couldn't see the Supabase
  fetch call at all (cross-origin). Found by temporarily wrapping
  `window.fetch` in `app.js` to log failing requests' bodies, which
  surfaced the exact Postgres error
  (`column vehicles.make_model does not exist`); fixed by switching the
  dropdown to `bus_number`, then removed the diagnostic before
  committing.

Verified end-to-end against the live database: registered a vehicle
with all nine new fields, confirmed correct display on the operator
list and staff approval queue (with no dangling separators when a field
is blank), correct prefill into the edit dialog, and a correct
round-trip through `request_vehicle_change()` on an edit (seats
49→51, aircon→non-aircon). Saved an operator profile, reloaded the
page, and confirmed every field persisted. Confirmed a completely fresh
browser tab shows zero console errors on every page.

### 14. `1dd13e5` — Fixed vertical misalignment of row action buttons (14 Aug)

The user pointed out the "Change" link on My requests sat visibly
off-center in its row - closer to the row below than the row it
belonged to. Cause: the action `<td>` has `display: flex` (to lay out
Change/Cancel side by side), and `vertical-align: middle` - the rule
every other cell uses to center its content - has no effect on a flex
container; that property only applies to table-cell/inline boxes. Fixed
with `align-items: center` on `.row-actions` instead, which does the
equivalent job for a flex box. Verified visually: every status/bay/note/
action cell now lines up on the same row, both on My requests and (same
class, same fix) the Vehicles list.

**This fix was incomplete** - the user reported the misalignment was
still there. `align-items: center` was correct as far as it went, but it
was centering content *within* a box that itself wasn't full height:
setting `display: flex` directly on a `<td>` pulls it out of the normal
table-cell box model entirely, so that cell stops stretching to the
row's height and instead sizes to its own content - `align-items` had
nothing taller than its content to center within. Measuring instead of
eyeballing this time: every row's status badge sat exactly at the row's
vertical center, while the action link sat a consistent 5-6px above it
- a fixed offset, not noise, confirming a structural cause rather than a
one-off rendering quirk.

Real fix: keep the `<td>` itself a plain, unstyled table cell (so the
table's normal `vertical-align: middle` still applies to it as a whole)
and move `display: flex` onto a `<div>` wrapper *inside* the cell
instead. Verified by measuring badge-center vs link-center on every row
before and after: `0px` difference on every single row post-fix, not
just a visual check.

### 15. `a1ceaa9` — Actually fixed the row action button alignment (14 Aug)

Continuation of #14 above - see that entry for the full story of what
was wrong and why the first attempt didn't fix it.

### 16. `ec29fa0` — 4-hour lead time on booking creation and changes (14 Aug)

New requests and changes both now need at least 4 hours' notice before
the scheduled slot:

- A new request's slot must be at least 4 hours away at submission time.
- An existing booking can't be changed once its *current* slot is within
  4 hours (the **Change** button disappears from the operator's list -
  **Cancel** is untouched); and whatever new slot is being requested must
  itself be at least 4 hours out.

Enforced at the database level, the actual boundary: the 4-hour check on
new bookings lives in the `bookings_insert_own` RLS policy's `WITH CHECK`
(deliberately not a table-level `CHECK` constraint - that would apply to
*every* write, including staff's approve/reject `UPDATE`, which must stay
unrestricted regardless of how little time is left). The check on changes
lives inside `request_booking_change()`, checked against the booking's
*current* slot before applying anything, plus a second check against the
newly-requested slot. A shared `slot_start_at()` SQL function (the actual
UTC instant a `(booking_date, slot)` pair represents, computed via
Postgres's `timestamp ... AT TIME ZONE 'Asia/Manila'` idiom) backs both.
The client mirrors the same rule (a JS port of `slot_start_at`) purely for
an immediate answer instead of a raw RLS-violation error - the database
is what actually protects this, verified by attempting both a raw insert
and a raw `request_booking_change()` call as the operator's own
authenticated role, bypassing the app entirely, and confirming Postgres
itself rejects both with the same friendly messages the app shows.

Verified end-to-end: a slot ~52 minutes out was rejected client-side and
(via direct SQL, bypassing the app) rejected at the RLS layer too; a slot
~5h52m out succeeded. A booking moved (via direct SQL, simulating one
that aged into the window) to ~52 minutes out lost its **Change** button
while keeping **Cancel**, and a direct RPC call against it was rejected
with *"This booking starts within 4 hours and can no longer be
changed."* A separate RPC call requesting a too-soon *new* slot on an
otherwise-eligible booking was rejected with *"Please choose a time at
least 4 hours from now."*

### 17. `aeb5b37` — Time slot dropdown hides slots already too close (14 Aug)

The 4-hour rule from #16 was previously only enforced on submit - an
operator could still see and pick a too-soon slot, then get told no.
The **Time slot** dropdown on the request form now only lists slots that
are still at least 4 hours out for whatever date is selected, and
re-filters whenever the date changes (the valid set differs per date -
today usually has early slots already too close; any future date starts
from midnight). If every slot for the selected date is too close, the
dropdown shows "No times left today" and disables itself rather than
offering an empty-feeling list.

Verified: for "today" (with ~12:08 PM as current time), the first
listed slot was 4:30 PM (just past the 4-hour mark) through 11:30 PM -
15 valid slots, all earlier ones correctly excluded. Switching the date
to tomorrow immediately repopulated all 48 slots starting from
midnight.

### 18. `db723c2` — Operator-to-operator booking transfer, staff-approved (14 Aug)

Some routes have multiple operators plying them, and one may have an
internal arrangement with another to cover a slot it can't make. Added a
dedicated handoff flow rather than folding it into the existing "Change"
edit, since it crosses operator accounts and the existing edit function is
deliberately scoped to a single operator's own bookings:

- New `booking_transfers` table (migration `0010`) plus three SECURITY
  DEFINER functions: `request_booking_transfer()` (the current owner
  proposes handing off to another operator, identified by username -
  there's no operator directory in the UI, so the two companies already
  know each other from their own arrangement), and staff-only
  `approve_booking_transfer()` / `reject_booking_transfer()`. Approving
  swaps `operator_id`, `operator_name`, and `plate_no` on the booking to
  the receiving operator and stamps `previous_operator_name` with the old
  name; rejecting leaves the booking untouched.
- Reuses the same 4-hour lead time as edits (a handoff is still a change
  to an active booking) and blocks a second transfer request from
  stacking on a booking that already has one pending.
- New **Transfer approvals** staff page (mirrors Vehicle approvals):
  lists pending handoffs with both operators, the plate change, and an
  optional reason; Approve/Reject.
- Operator dashboard: a **Transfer** button next to Change/Cancel on
  eligible bookings, opening a small dialog (receiving operator's
  username, their plate, optional reason). While a transfer is awaiting
  review, Change/Cancel/Transfer are all hidden on that row (shows
  "transfer pending" instead) so it can't be edited out from under the
  review.
- **Schedule** and **My requests** both show `~~Old Operator~~ New
  Operator` once a transfer is approved - the previous operator's name
  struck through, immediately followed by the current one.
- The receiving operator has no in-app acceptance step; PITX staff
  approval is the only gate, matching what was asked for. Noted as a
  known gap below.

Verified against the live database with the same RLS-bypassing SQL
harness used throughout: a non-staff operator calling
`approve_booking_transfer()` directly is rejected ("Only PITX staff can
decide on transfers"); requesting a transfer to one's own username is
rejected ("You can't transfer a booking to yourself"); requesting a
transfer to a nonexistent username is rejected ("No operator account
found with that username"). The struck-through display was verified by
inserting a test booking with `previous_operator_name` set and confirming
the rendered markup and CSS (`<s class="transferred-from">`) render
correctly, then removing the test row.

### 19. `29f2731` — `create-operator` script; bootstrap Jac Liner operator account (14 Aug)

Needed a second operator account to test/demo the transfer feature
(#18) against, and there was no way to create one without the
still-undeployed `create-account` Edge Function. Added
`scripts/create-operator.mjs`, a direct copy of `create-staff.mjs`'s
approach (service-role `auth.admin.createUser` + a matching `profiles`
row) with `role: 'operator'` instead of `'staff'`.

Created a live `jacliner.ops` account (operator name "Jac Liner").
Verified against the database that it has an identical shape to the
existing `genesis.ops` account - both `role = 'operator'` in `profiles` -
confirming access is granted purely by role, so the new account has
every function (booking, vehicles, transfers) with no special-casing
needed.

### 20. `d7b666c` — Booking form drops the Operator field; transfer picks a real account (14 Aug)

Two related cleanups on the booking/transfer flow:

- The booking form had a free-text "Operator" input the operator typed
  their own company name into every time - redundant now that
  `profiles.operator_name` already is the account's identity. Removed
  the field entirely; `operator_name` on a new booking is always read
  from the signed-in account. Submitting is blocked (with a clear
  message) for the edge case of an account with no operator name set,
  rather than hitting a raw NOT NULL error.
- The transfer dialog's "receiving operator" was a free-text username -
  easy to typo, no feedback until the RPC call rejected it. Replaced
  with a `<select>` populated from a new `list_operator_accounts()`
  function (migration `0011_operator_directory.sql`), listing every
  *other* operator account by display name. A narrow SECURITY DEFINER
  lookup (just username + operator_name, self excluded) rather than
  opening the `profiles` table up via RLS, since operators still can't
  read each other's full profile row directly.

Verified live: the booking form has no Operator input and a submitted
booking still gets the account's operator_name; the transfer dropdown
lists only the *other* operator account (confirmed via a raw RLS test
that it excludes self, and that direct `profiles` access is still
restricted to one's own row); a transfer submitted through the dropdown
still goes through the same approval flow from #18.

### 21. `0d1bf94` — Transfer needs the receiving operator's confirmation before staff can approve (14 Aug)

Previously a transfer went straight from the sending operator's request
to the staff queue, taking the "internal agreement" on the sender's
word alone. Now the receiving operator has to actually confirm in-app
first:

- `booking_transfers.recipient_response` (`pending` / `accepted` /
  `declined`). `approve_booking_transfer()` now raises if it isn't
  `accepted` - enforced inside the function, not just hidden in the
  UI, so staff can't approve around a missing confirmation even
  calling the RPC directly.
- New `accept_booking_transfer()` / `decline_booking_transfer()`
  functions, callable only by the transfer's `to_operator_id`.
  Declining closes the request immediately - it never reaches staff.
- `dashboard.html` gained an **Incoming transfer requests** section:
  transfers awaiting this operator's own response, with Confirm/Decline.
- `transfer-approvals.html` only shows Approve/Reject once
  `recipient_response = 'accepted'`; otherwise it shows "Waiting on
  \<name\> to confirm".

Building this surfaced two real RLS bugs, not just missing features:
the recipient's dashboard tried to embed `bookings` (for date/route)
and `profiles` (for the sender's name) through `booking_transfers`, but
RLS blocks both - an operator can only read bookings they own and
profiles rows that are their own, and this booking/profile belongs to
someone else. Fixed by snapshotting `booking_date`/`slot`/`route`/
`previous_plate_no` (migration `0013`) and `from_operator_name`
(migration `0014`) onto `booking_transfers` itself at request time,
readable by both sides with no RLS widening needed.

Verified live end-to-end, including the negative case: submitted a
transfer -> staff queue correctly showed "waiting on Jac Liner to
confirm" with no Approve button -> a raw `approve_booking_transfer()`
RPC call as staff was rejected server-side ("The receiving operator has
not confirmed this transfer yet.") -> confirmed as the recipient, whose
dashboard now correctly showed the sender's name and booking details ->
staff queue then showed Approve/Reject -> approved -> Schedule showed
the struck-through handoff, same as #18.

### 22. `caff799` — Operator profile: TIN No. label drops "(Paranaque)" (14 Aug)

Label-only fix on `operator-profile.html` - "TIN No. (Paranaque)" is now
just "TIN No.". No schema/behavior change.

### 23. `2c16265` — Vehicle registration: OR No. and CR No. fields back (14 Aug)

Migration `0008` had replaced the vehicle field set to match the paper
form exactly, dropping the per-vehicle `or_number`/`cr_number` columns
along the way. Added them back:

- `vehicles.or_number` / `vehicles.cr_number` (migration
  `0015_vehicle_or_cr_numbers.sql`) - distinct from
  `operator_profiles.or_serial_number`, which is a company-level field
  from a different part of the paper form.
- `request_vehicle_change()` signature grows two parameters - dropped
  and recreated, same reason as every prior signature change here
  (Postgres can't alter a function's parameter list in place).
- `vehicles.html`: OR No./CR No. inputs in both the add and edit
  dialogs, and as columns in the vehicle list.
- `vehicle-approvals.html`: shows both in the staff review card when set.
- `orcr-parser.js`: now also guesses OR/CR numbers from the scanned
  photo (looks for an "OR NO."/"CR NO." label near a value) - looser
  than the existing plate/expiry heuristics, so more likely to need a
  manual fix; always shown as an editable field per the same
  never-auto-save rule as the rest of the OCR guesses.

Verified live: added a vehicle with OR No. `OR-0012345` / CR No.
`CR-0067890` filled in by hand, confirmed both values round-tripped
correctly in the database, then removed the test row.

### 24. Bootstrapped 21 operator accounts for the real bus line roster (14 Aug)

Data-only change, no code: created one operator account per bus
line/company on the operator's provided roster, via `create-operator.mjs`
(same mechanism as Jac Liner earlier), all sharing password
`TestPass123` - same as the rest of the test accounts. Usernames are a
lowercased/de-punctuated slug of the company name (e.g. `A&B LINER` ->
`abliner.ops`); `profiles.operator_name` keeps the name as given.

| Username | Operator name |
|---|---|
| `amihan.ops` | AMIHAN |
| `philtranco.ops` | PHILTRANCO |
| `alps.ops` | ALPS |
| `bicolisarog.ops` | BICOL ISAROG |
| `dltb.ops` | DLTB |
| `superlines.ops` | SUPERLINES |
| `raymond.ops` | RAYMOND |
| `tawtrasco.ops` | TAWTRASCO |
| `cagsawa.ops` | CAGSAWA |
| `omtranscoop.ops` | OMTRANSCOOP (Jariv Transport) |
| `rorobus.ops` | RORO BUS |
| `davaometroshuttle.ops` | DAVAO METRO SHUTTLE CORP |
| `ceresgoldstar.ops` | CERES-GOLDSTAR |
| `ndelarosaliner.ops` | N. DELA ROSA LINER |
| `jamliner.ops` | JAM LINER |
| `abliner.ops` | A&B LINER |
| `barneyautoline.ops` | BARNEY AUTO LINE |
| `potransport.ops` | P&O TRANSPORT |
| `jamlinerlli.ops` | JAM LINER/LLI |
| `pangasinansolidnorth.ops` | PANGASINAN SOLID NORTH |
| `delarosaexpress.ops` | DELA ROSA EXPRESS |

Verified against the database: all 21 rows created with
`role = 'operator'`, bringing the total operator account count to 23
(plus the pre-existing `genesis.ops` and `jacliner.ops`).

### 25. `55a6948` — Transfer's plate no. is a dropdown from the receiving operator's vehicles (14 Aug)

"Their plate no." on the transfer dialog was free text - easy to typo,
and nothing stopped naming a plate the receiving operator never
actually registered. Now it's a dropdown sourced from that operator's
own approved vehicles:

- New `list_operator_vehicles(p_username)` function (migration `0016`)
  - narrow SECURITY DEFINER lookup (plate_no + bus_number, approved
    only), same shape as `list_operator_accounts()` (#20). Needed
    because the sender can't query another operator's vehicles table
    directly - RLS only allows reading your own.
- `dashboard.html`: the plate field is a `<select>`, populated on the
  "Receiving operator" dropdown's change - starts disabled ("Pick an
  operator first"), shows "No approved vehicles for this operator" if
  they have none.
- `request_booking_transfer()` also validates the plate server-side
  against the receiving operator's approved vehicles, so a raw RPC
  call can't submit a plate the dropdown wouldn't have offered.

Verified live: picking an operator in the dropdown correctly populated
the plate dropdown with their actual approved vehicle
(`JAC-777 — Bus No. Bus 7` for Jac Liner), and the submission
round-tripped correctly in the database. Also verified server-side: a
raw RPC call with a plate not in the receiving operator's approved
list was rejected ("That plate isn't one of the receiving operator's
approved vehicles.").

### 26. `285f469` — My schedule: operator view of approved bookings + bay assignments (17 Aug)

New `docs/my-schedule.html`, added to the operator nav between My
requests and My vehicles. A read-only list of the operator's own
**approved** bookings only - "where do I actually need to show up" -
sorted chronologically with the bay assigned to each. Defaults to
**Upcoming** (`booking_date >= today`); an **All** tab includes past
slots, shown dimmed. Shows the same transferred-from strikethrough as
My requests/Schedule for handed-off bookings.

No new tables or functions - it's the existing `bookings` RLS
(`operator_id = auth.uid()`) filtered to `status = 'approved'`, just
presented as a simple chronological list rather than the
request-management table on My requests.

Found and fixed a real CSS bug while building this: `tr.muted` alone
didn't actually dim a row - `td`'s own explicit `color: var(--text)`
rule beats an *inherited* color from an ancestor regardless of
selector specificity (any explicit declaration always wins over
inheritance). Added `tr.muted td { color: var(--faint) }` to override
it directly; confirmed via `getComputedStyle` before (same color as
normal rows) and after (correctly the faint gray) the fix.

Verified live: page redirects to login when signed out; Upcoming
correctly showed only the one 2026-08-17-forward booking; All showed
all 5 approved bookings sorted by date, with the 4 past ones visibly
dimmed after the CSS fix; nav highlights "My schedule" as the active page.

### 27. `9e3a3ca` — My schedule: timeline instead of a table (17 Aug)

Rebuilt the page's rendering from a plain table to a chronological
**timeline**: grouped by calendar date, each day heading followed by a
vertical dot-and-line rail connecting that day's approved slots in
order (time, bay tag, route, plate). Today is tagged; past days render
visibly dimmed but stay in place under **All** rather than
disappearing, so the operator can still see what already happened.

New CSS: `.tl-day`/`.tl-day-heading`/`.tl-today-tag` for the day
grouping, `.timeline`/`.timeline-item`/`.timeline-rail`/`.timeline-dot`/
`.timeline-line`/`.timeline-card` for the rail - the connecting line is
hidden on each day's last item so the timeline doesn't dangle past the
final slot of the day.

Verified live: a single-slot day shows just a dot with no trailing
line; a two-slot day (Aug 14) shows the connecting line between dots;
today's slot renders full-color with a "Today" tag; earlier days stay
visible but dimmed under All.

### 28. `803e92c` — My schedule: most recent day first (17 Aug)

Day grouping now sorts descending (today, then backward) instead of
ascending (oldest first) - a one-line query change
(`order("booking_date", { ascending: false })`); each day's own slots
still sort ascending by time, so the rail still reads top-to-bottom
correctly within a day.

Verified live: **All** now lists Aug 17 (today), 15, 14, 12 in that
order, with Aug 14's two slots still 6:30 AM before 4:00 PM.

### 29. `12593fe` — PITX staff can delete accounts (17 Aug)

Added a "Delete" action per row on **Accounts** (hidden on staff's own
row - can't delete yourself, enforced server-side too, not just by
hiding the button):

- New `delete-account` Edge Function, same auth pattern as
  `create-account` (verifies the caller is signed-in staff before
  doing anything privileged).
- New `scripts/delete-account.mjs` CLI fallback (`npm run
  delete-account -- <username>`), same reasoning as
  `create-operator.mjs` - usable until the Edge Function is deployed.

Deleting an account cascades to that operator's own vehicles (existing
FK), but **not** to `bookings.operator_id` or any `decided_by` column -
those deliberately don't cascade, so deleting an account that still
has bookings or approval decisions on record fails with a clear error
instead of silently orphaning that history. Supabase's admin API wraps
the actual Postgres FK violation into a generic "Database error
deleting user" message rather than passing it through, so both the
Edge Function and the CLI script treat *any* `deleteUser` failure as
"still referenced elsewhere" rather than trying to pattern-match a
message they don't control.

Verified against the live database with the CLI script (identical
logic to the Edge Function, so this is a real functional test, not
just a code read): created a disposable test account and deleted it
successfully; then confirmed `genesis.ops` (has bookings) and
`pitx.admin` (has approval decisions) are both correctly blocked with
the friendly error message, and neither account was actually removed
from the database afterward.

### 30. `b8e8f6f` — Staff-only Operator profiles page (17 Aug)

New `docs/operator-profiles.html`, added to the staff nav between Bays
and Accounts - fills a real gap: staff previously had no way to see an
operator's company details (name, owner, TIN, OR serial number,
booking system, NAU, two contacts) without database access.

- Lists **every** operator account, not just ones with a saved
  profile - accounts that haven't submitted one yet are tagged "no
  profile yet" rather than omitted, since staff following up on who
  still needs to fill theirs in is as useful as seeing the ones who
  have.
- A summary line ("N of M operators have submitted a profile") gives
  the at-a-glance count.
- Client-side search over username, operator name, and company name.
- No new migration - `operator_profiles`' existing select policy
  (`operator_id = auth.uid() or is_staff()`, migration `0008`) already
  covers this; it's the first UI built on top of that access.

Verified live: page correctly listed all 23 operator accounts, showed
Genesis Transport's full saved profile with every field rendered
correctly, tagged every other account "no profile yet", the summary
line read "1 of 23 operators have submitted a profile", and the search
box correctly filtered down to a single match.

### 31. `af04f7b` — Route dropdown + real operator profile data, from the operator database (17 Aug)

The user shared "Operator Database.xlsx" (Operator List / Operator
Profile / Routes sheets) and asked for two things: a route dropdown
sourced from it, and the site's operator profiles updated from its real
data.

**Route dropdown.** Added `ROUTES` to `app.js` - the 8 fixed
PITX-served provincial routes from the spreadsheet's Routes sheet.
Both the booking form's Route field and the Change dialog's are now
`<select>`s instead of free text. The Change dialog still preserves a
booking's existing route even if it predates the fixed list (tagged
"(not in the current list)") - same pattern as the plate dropdown's
"no longer approved" fallback, so re-opening the dialog never silently
drops a value it can't otherwise represent.

**Real operator_profiles data.** Populated all 23 existing operator
accounts from the spreadsheet's Operator Profile sheet (company name +
up to 2 contacts: name/position/number/email). Added
`contact1_email`/`contact2_email` columns (migration `0017`) since the
spreadsheet has real emails the paper form's contact fields don't ask
for, and dropping them would lose real data.

Two account groupings needed a judgment call, since the spreadsheet
groups companies differently than this app's accounts do - asked the
user before writing anything, per their own instruction to flag
multiple entries:

- **Jac Liner / Jam Liner / Jam Liner-LLI** (3 separate accounts): the
  spreadsheet has one combined row ("JAC LINER INC/ LLI/ JAM LINER")
  plus two standalone JAM LINER rows. Per the user (kept all three
  genuinely separate): Jac Liner gets the combined row's manager
  (Catherine Flores); Jam Liner gets both standalone rows' contacts
  (Jose Aguilo, Catherine Flores); Jam Liner/LLI gets the combined
  row's dispatcher (Jordan Maligaya) - the only contact tied to "LLI"
  specifically ("Lucena Lines Inc.", per the user's clarification of
  the acronym).
- **Amihan / Philtranco** (2 separate accounts): the spreadsheet has
  standalone rows for each, plus a combined row with 5 more
  teller/dispatcher contacts. Per the user: each account keeps only
  its own standalone-row contacts; the combined row's 5 contacts go to
  neither.

No company owner/TIN/OR-serial/booking-system/NAU data exists in the
spreadsheet, so those fields are empty for all 23 - including clearing
Genesis Transport's previous *fictitious test* values in those fields,
since real source data now takes priority over placeholder test data.

Also checked the user's third ask directly: whether any existing
account had no match in the spreadsheet (in which case its blank
`operator_profiles` row, if any, should be deleted). Confirmed all 23
matched something, so nothing needed deleting.

Verified live: booking form and Change dialog both show the 8-route
dropdown; the Change dialog correctly preserved and labeled a legacy
non-matching route ("Makait (not in the current list)") after bumping
a test booking's date forward to make it editable, then reverted the
date afterward; Genesis Transport's own Operator profile page shows
the imported company name and contact (with email) and confirms the
owner/TIN fields are now empty; the staff Operator profiles page shows
A&B Liner's two contacts including the new email field, with the
summary line now reading "23 of 23 operators have submitted a
profile".

### 32. `7b84713` — Route dropdown: drop the redundant "PITX -" (17 Aug)

Every route is a PITX trip by definition, so showing "PITX" on every
option was redundant. Trimmed each `ROUTES` entry in `app.js` down to
just the other endpoint - `"Baguio via Inner Cities"` instead of
`"PITX - Baguio via Inner Cities"`, `"Tuguegarao City, Cagayan"`
instead of `"Tuguegarao City, Cagayan - PITX"`, etc. Existing bookings'
stored route strings are untouched - already covered by the Change
dialog's "not in the current list" fallback if they don't match.

Verified live: the dropdown now lists all 8 routes as plain endpoint
names with no PITX prefix/suffix.

### 33. `1c699a9` — Dashboard dialogs say "Cancel" instead of "Never mind" (17 Aug)

Wording-only fix on the Change and Transfer dialogs' dismiss button -
matches the wording already used everywhere else (`vehicles.html`'s
add/edit dialogs already said "Cancel"). No schema/behavior change.

### 34. `f8f0df2` — Create accounts for every remaining operator in the spreadsheet (17 Aug)

The earlier import (#31) only populated profiles for the 23 accounts
that already existed - the user pointed out the spreadsheet's Operator
Profile sheet has far more distinct companies than that, and asked for
accounts to be created for every one of them. Fixed properly rather than
patched:

- 37 unambiguous new operators (own standalone row(s) in the
  spreadsheet, no name/identity overlap with any other account), each
  with `company_name` + up to 2 contacts imported the same way as the
  original 23.
- 8 more accounts covering 4 groupings that needed a judgment call
  before creating anything - same category of decision as the earlier
  Jac/Jam/LLI and Amihan/Philtranco calls, asked up front rather than
  guessed: two identical-contact company pairs (Bataan Transit/First
  North Luzon Transit; Eastern Metropolitan Bus/Rizal Metrolink), one
  related-but-distinct pair (Elavil Tours/Elavil Transit), and a 3-way
  combined row overlapping an already-created standalone account (San
  Agustin/St. Anthony of Padua, split out from Batman Starexpress's
  combined row). All four resolved as "keep as separate accounts" - see
  README's "Real operator data import" section for the exact contact
  split used on each.

Every new account: `role = 'operator'`, password `TestPass123` (same
convention as every account in this project), `operator_profiles` row
with `company_name` + contacts - no owner/TIN/OR-serial/booking-system/
NAU, since none of that exists in the spreadsheet for any of them.

Total operator accounts: **68** (up from 23). Verified against the
live database (68 operator accounts, 68 matching `operator_profiles`
rows) and in the staff Operator profiles page, which now reads "68 of
68 operators have submitted a profile" - spot-checked A. Arandia
Line's imported contacts render correctly there too.

### 35. `7cbb6a5` — Vehicle registration: supporting document upload for staff (17 Aug)

Operators can now attach one supporting document per vehicle
(franchise/CPC, insurance, etc.) - any image or PDF, separate from the
existing OR/CR scan photo.

- Migration `0018`: `vehicles.supporting_doc_path` /
  `supporting_doc_name`. Reuses the existing `vehicle-docs` bucket and
  its per-operator-folder storage policies unchanged - new files land
  under `<operator_id>/supporting/<uuid>.<ext>`, still within the same
  folder prefix those policies already cover.
- Migration `0019`: `request_vehicle_change()` grows two parameters to
  carry the document through an edit. Operators can only edit a
  vehicle through this function - migration `0005` removed their
  direct UPDATE policy entirely - so this was the only way to let them
  replace it later. Dropped and recreated, same reasoning as every
  prior signature change in this project.
- `vehicles.html`: file input on both Add and Edit dialogs. Edit shows
  "Current: `<filename>` - choose a file below to replace it" when one
  is attached, and explicitly passes the existing path/name through
  when no new file is chosen, so an unrelated field edit can't wipe it
  out. New "Document" column in the list, linked via a signed URL.
- `vehicle-approvals.html`: staff see a "View supporting document
  (`<filename>`)" link next to the existing OR/CR photo link.

Verified live end-to-end, not just a code read: uploaded a real file
through a vehicle registration, confirmed the exact bytes round-tripped
through a live signed URL (curled it back and got the file's actual
content), saw the Document link and filename in both the operator's
own list and the staff Vehicle approvals queue, then edited the
vehicle without touching the document and confirmed via the database
that the path/name survived rather than being nulled out.

### 36. `5ea6e0d` — Staff-only Vehicles database page (17 Aug)

New `docs/vehicles-database.html`, added to the staff nav between
Vehicle approvals and Transfer approvals. Read-only list of **every**
registered vehicle across **every** operator, any status - Vehicle
approvals only ever showed the pending queue, so there was no way to
browse the whole fleet (an operator's already-approved vehicles, or
ones staff previously rejected).

- Status filter (All / Approved / Pending / Declined) and a search box
  over plate no., operator, and bus no.
- Each row resolves signed URLs for whatever documents that vehicle
  has on file (OR/CR scan photo, supporting document from #35), same
  pattern already used on `vehicles.html`/`vehicle-approvals.html`.
- No new migration - `vehicles`' existing select policy already lets
  staff read every row regardless of status (`operator_id = auth.uid()
  or is_staff()`, migration `0003`); this is the first UI built
  specifically for browsing the whole fleet rather than only the
  pending queue.

Verified live: page lists all registered vehicles with operator names
resolved via the FK embed, status filter tabs work, search correctly
narrowed down to a single plate, nav link renders and highlights
correctly as the active page.

### 37. `27880f9` — Vehicle approvals + Operator profiles: table view instead of cards (17 Aug)

Both pages rendered their list as `.request-card` divs (one per row) -
rewrote both to the same `<table>` + `data-label` pattern the other
list pages already use (`vehicles.html`, `vehicles-database.html`,
`schedule.html`), with the same responsive stacked-card fallback below
640px but a real scannable table at normal widths.

- `vehicle-approvals.html`: columns match `vehicles-database.html`'s
  field set, with Approve/Reject in a trailing action column (same
  `.row-actions` wrapper-div pattern as `dashboard.html`'s
  Change/Transfer/Cancel row).
- `operator-profiles.html`: one column per field, "no profile yet"
  badge now inline in the Operator cell instead of the card header.

No behavior change - same data, same actions, same signed-URL document
resolution; just a denser layout for pages that can have dozens of
rows (68 operators, and any number of pending vehicles).

Verified live: both render as real `<table>`s at desktop width -
inserted a temporary pending vehicle to confirm Approve/Reject render
correctly in the table's action column, then removed it; operator
profiles table correctly shows all 68 rows with contacts and the "no
profile yet" badge inline.

### 38. `a382cd9` — Staff can reassign an approved booking's bay; gate-based bay suggestions (17 Aug)

Two related changes, from the terminal's actual gate layout the user
provided:

```
Gate 2 (Bays 8-11)  - Laguna, Batangas, Quezon, Mindoro routes
Gate 4 (Bays 18-23) - Bicol, Visayas, Mindanao routes
Gate 5 (Bays 33-36) - North routes
```

- Migration `0020`: `bays.gate`, tagging Gate 2/4's existing bays and
  adding the bays that didn't exist yet (21-23, 33-36) - **raises
  active bay count from 20 to 27**, which directly raises the per-slot
  approval capacity ("How capacity works" in the README).
- `ROUTE_GATES` + `gateForRoute()` in `app.js` maps each `ROUTES` entry
  to its gate - every current route is a Northern Luzon destination,
  so all map to Gate 5 today; documented how to extend the map when a
  Laguna/Batangas/Quezon/Mindoro/Bicol/Visayas/Mindanao route is added.
- `staff.html`'s approval bay dropdown now groups options into
  **"Suggested (Gate N)"** first, then **"Other bays"** - a suggestion,
  not a hard restriction, since staff may need to override it (gate
  full, or route has no gate mapped).
- `schedule.html`: staff can now reassign an already-approved booking's
  bay directly - the bay tag on each approved row becomes a select
  (same Suggested/Other grouping) + **Save** button. Options exclude
  bays already taken by another approved booking in that slot, so a
  conflict can't even be picked; the existing unique index (migration
  `0001`) is still the real backstop. Plain table update on
  `bookings.assigned_bay_id` - staff already have unrestricted UPDATE
  rights there, no new RPC needed.

Verified live end-to-end: approved a test booking and confirmed the
dropdown listed Gate 5 bays (33-36) first; reassigned it from Bay 33
to Bay 35 on Schedule and confirmed via the database; inserted a
second approved booking in the same slot at Bay 34 and confirmed the
first booking's dropdown correctly excluded Bay 34 (and vice versa);
confirmed the unique constraint still rejects a double-assignment
attempted directly via SQL, bypassing the UI entirely.

### 39. `39dcd6d` — Route list expanded to all 83 destinations (18 Aug)

The operator database spreadsheet gained a new "Sheet5"
(destination/province/region, filtered to "Operational" status) - a far
more complete route list than the original 8-route "Routes" sheet,
which turned out to already be a subset of it (same 8 places, slightly
different phrasing).

- `ROUTES` in `app.js` replaced with all **83 destinations** from
  Sheet5. Existing bookings using the old phrasing (e.g. "Tuguegarao
  City, Cagayan") aren't renamed - the Change dialog's "not in the
  current list" fallback (#31) already covers a stored route that
  doesn't match an entry here.
- `ROUTE_GATES` now derived from Sheet5's REGION column rather than
  hand-picked per destination: CAR/I/II/III -> Gate 5, IV-A/IV-B ->
  Gate 2, V-VIII/X-XIII -> Gate 4. Every prior route was Northern Luzon
  (Gate 5); this is the first real exercise of the Gate 2/Gate 4
  mapping from #38.
- `dashboard.html`'s route dropdown now groups into 3 `<optgroup>`s
  (North/Gate 5, Cavite-Batangas-Laguna-Quezon-Mindoro/Gate 2, Bicol-
  Visayas-Mindanao/Gate 4) instead of one 83-item flat list - reuses
  `ROUTE_GATES` rather than a separate grouping scheme.

Found and fixed a real bug while verifying live: `GATE_GROUP_LABELS`
was declared with `const` *after* `initForm()` was already being
called at module top-level, so referencing it inside
`routeOptionsHtml()` threw "Cannot access before initialization" the
first time that function ran. Moved the declaration up with the other
module-level state - the file's own top comment already calls out this
exact ordering hazard from an earlier bug.

Verified live: route dropdown renders all 83 options across the 3
correct optgroups with no console errors (confirmed via a completely
fresh tab, since the buggy tab's console had a stale cached error from
before the fix); submitted a real booking with "Legazpi City, Albay"
and confirmed it saved correctly; on Pending requests, that booking
correctly showed "Legazpi City, Albay - Gate 4" with Bay 18-23
suggested first.

---

### 40. Auto-assign a bay on approval (18 Aug)

Staff previously had to manually pick a bay from the dropdown before
every approval, even though the gate-based suggestion (#38) already
narrowed it down to a good default. Now the bay `<select>` on Pending
requests comes **pre-selected** on load: the lowest-numbered available
bay in the route's suggested gate, or the lowest-numbered available bay
overall if the route has no gate or that gate is full. Staff can still
change the dropdown before clicking Approve; the pick is a default, not
forced. No schema or RLS change was needed - `approve()` already had
full staff UPDATE rights via the existing `bookings_staff_update`
policy, so this is a client-side selection-logic change only.

Verified live: inserted a real pending test booking for "Davao City,
Davao del Sur" (maps to Gate 4, bays 18-23), reloaded Pending requests,
and confirmed via the page's own DOM that the bay `<select>` was
pre-selected to "Bay 18" (the lowest bay in that gate) without any
manual interaction. Clicked Approve without touching the dropdown, then
queried the database directly and confirmed `status` became `approved`
with `assigned_bay_id` resolving to Bay 18. Test data cleaned up
afterward.

---

### 41. Suggest a different time slot when the route's gate is full (18 Aug)

Found while stress-testing #40: filling every bay in a route's gate for
a given slot doesn't block the operator from requesting it - staff just
fall back to an unrelated gate at approval time (by design, #38). That's
fine as a safety net, but an operator has no way to know their preferred
gate is already full until after they've submitted and waited on staff.

Added a live check on the booking form
([`docs/dashboard.html`](docs/dashboard.html)): once route, date, and
slot are all picked, if every active bay in that route's gate is
already assigned to an *approved* booking for that slot, an amber hint
appears under the time slot field naming up to 3 nearby times (nearest
first) that still have room in the same gate, each a clickable button
that swaps the slot and re-runs the check. Advisory only - the Request
button stays enabled, since submitting anyway is still perfectly valid
(staff can assign a different gate). New `.hint` style in
`styles.css` (amber, not `.warn`'s red - this never blocks anything).

Verified live: created a throwaway operator with an approved vehicle,
inserted 4 synthetic approved bookings occupying all of Gate 5's bays
(33-36) for one date/slot, then loaded the booking form as that
operator and picked a Gate 5 route for that same date/slot - the hint
appeared naming the correct nearest open times. Clicking a suggested
time swapped the slot and the hint correctly disappeared (that time had
room). Submitted the booking on the suggested slot and confirmed it
saved as `pending` normally. Test data cleaned up afterward.

---

### 42. Import the LTFRB masterlist's PROVL sheet into vehicles (18 Aug)

Imported PITX's official "PROVL" (provincial) vehicle masterlist -
1,910 rows - into `vehicles`, after confirming scope with the user given
the size and irreversibility of the write:

- **Operator matching**: normalized each row's OPERATOR string (strip
  punctuation/case, common suffixes like "Inc."/"Transport"/"Corp.") and
  matched against the 68 existing operator accounts - 1,693 rows matched
  cleanly (plus a handful of hand-verified aliases for abbreviations/
  misspellings a plain match couldn't bridge, e.g. "DMS" -> Davao Metro
  Shuttle, "UNAH KLARRIZE" -> the existing Unahklarizze account).
- **New accounts**: the remaining 217 rows belonged to 12 real companies
  with no existing account (Penafrancia Tours & Travel, Metro Manila Bus
  Co., Bicol Magayon, Legaspi St. Jude, Saulog Transit, and 7 others) -
  created a new operator account for each (`TestPass123`, same convention
  as every other account) rather than dropping their vehicles; 2 rows
  with a blank operator field were skipped as unidentifiable.
- **LTFRB status handling**: added `ltfrb_status` to `vehicles` (migration
  `0021_vehicle_ltfrb_status.sql`) - `active`/`inactive`/`no_record`/
  `ltfrb_verified`, plus a new `masterlist_import` value for `source`.
  Every row imports as `status = 'approved'` regardless of LTFRB status
  (this masterlist *is* PITX's own vetting), but only `active`/
  `ltfrb_verified` vehicles are eligible for the booking form's plate
  list and the transfer dialog's plate list - `list_operator_vehicles()`
  got the same eligibility check (migration
  `0022_ltfrb_status_transfer_eligibility.sql`) so an inactive vehicle
  can't be transferred into either. **My vehicles** and **Vehicles**
  (staff) both show the new LTFRB badge; **My vehicles** adds a banner
  when an approved vehicle is excluded from booking, so it doesn't look
  like it silently vanished.
- **Field mapping**: plate_no, case_number, bus_number, and `route`
  (from the sheet's fuller "FRANCHISE" column, not the shorter "OPERATING
  ROUTE" one) map directly; `date_expiry` comes from "DATE OF VALIDITY
  CPC" (an Excel date serial, converted via `xlsx.SSF.parse_date_code`).
  Chassis no., sticker no., document type, and date-tagged have no
  corresponding column in `vehicles` and weren't imported - out of scope
  for now, not a data-loss bug.
- **Duplicate rows**: bulk inserts used
  `on conflict (operator_id, <normalized plate>) do nothing` against the
  existing per-operator plate unique index, both for resumability after a
  bad-date-value crash mid-import (see below) and because the sheet
  itself has 75 genuine duplicate (operator, plate) rows (re-tagging
  entries for the same unit) - confirmed by recomputing the expected
  unique count independently and matching it exactly against what
  actually inserted (1,833 of 1,908 resolved rows).

Found and fixed two bugs while running this:

- A handful of "DATE OF VALIDITY CPC" cells held invalid serials (e.g.
  one that decoded to "1900-01-00"), which crashed the whole batch
  insert containing them. Fixed the date converter to return null for
  anything that doesn't decode to a real date, and made batch failures
  fall back to inserting that batch's rows one at a time so a single bad
  row can't take out 199 good ones with it.
- **`vehicles-database.html` (staff fleet page) has no `.range()` on its
  query**, and Supabase/PostgREST caps a single request at 1000 rows by
  default - this import pushed the table past 1000 for the first time
  (1,836 total after import, previously 3), silently truncating the page
  to exactly 1000 rows with no error. Fixed by paging through with
  `.range()` until a page comes back short. Hit the same
  temporal-dead-zone bug as #37/#39 while fixing it - `PAGE_SIZE` was
  declared right above the function that uses it, but that function is
  *called* earlier in the module than that declaration executes; moved
  it up with the other early module-level state.

Verified live: reloaded **Vehicles** (staff) after the fix and confirmed
`summary-count` and the actual row count both read 1,836, not 1,000.
Logged in as a newly-created operator (`penafranciatours.ops`, which has
both active and inactive vehicles) and confirmed the booking form's plate
dropdown listed exactly 41 options (its active count) rather than all
63, and that **My vehicles** showed the exclusion banner plus an
`Inactive` badge on the right rows.

---

### 43. Merge two duplicate operator accounts from the masterlist import (18 Aug)

Flagged after #42 as worth a manual look, then confirmed by the user:
two of the 12 new accounts the import created were actually the same
real operator as an existing account, just spelled differently in the
source sheet.

- **Alan R. Arandia** (`alanarandia.ops`, 18 vehicles) merged into the
  existing **A. Arandia Line** (`arandialine.ops`, which had 0 vehicles
  of its own) - all 18 vehicles reassigned, no plate collisions.
- **JVH Tranpost Ltd Co.** (`jvhtranpost.ops`, 1 vehicle) merged into the
  existing **JVH Transport / R. Volante Line** (`jvhtransport.ops`, 36
  vehicles) - its one vehicle collided on plate + case number with a
  vehicle already in the target account (confirmed genuinely the same
  unit), so rather than move it, backfilled the one field it had that
  the kept row didn't (`bus_number`) onto the existing row and dropped
  the duplicate.

Both now-empty duplicate accounts (profile row + auth user) were
deleted. Verified live: `arandialine.ops` and `jvhtransport.ops` show the
correct combined vehicle counts (18 and 36), `alanarandia.ops` and
`jvhtranpost.ops` no longer exist, and total vehicle count dropped by
exactly 1 (the dropped JVH duplicate) to 1,835.

---

### 44. Five more vehicle fields, expiry warnings, and a notification panel for both roles (18 Aug)

Three asks bundled together since they touch the same tables:

**Five new vehicle fields** (migration `0023_vehicle_document_fields.sql`):
Chassis No., Franchise, CPC validity, OR/CR validity, Sticker No. Added to
the **My vehicles** add/edit dialogs and table, **Vehicle approvals**, and
**Vehicles** (staff fleet page); `request_vehicle_change()` grew five more
parameters (same drop-and-recreate as every prior signature change).
Backfilled all five for the 1,832 already-imported masterlist vehicles by
re-reading the source spreadsheet's Chassis No./Franchise/Sticker No./
"DATE OF VALIDITY CPC"/"OR/CR MONITORING" columns (the last two weren't
captured at all in #42 - no field existed for them yet).

**Expiry warnings**: a validity date within 30 days (or already past)
now renders in amber/red on every vehicle table (`expiryCell()` helper in
`app.js`), and feeds the new notification panel below. 100 real vehicles
currently have an OR/CR validity within the next 30 days, 0 have a CPC
validity in that window - confirmed directly against the live data before
calling this done.

**Notification panel, both roles** (migration `0024_notifications.sql`,
`0025_vehicle_pending_notify_on_edit.sql`): a bell icon in the nav, wired
into `renderNav()` so it's on every page for free. Staff get notified of
new booking/vehicle/transfer requests; operators get notified when their
own booking/vehicle/transfer is approved or declined; both get notified
of a CPC/OR-CR expiring within 30 days. Full behavior documented in the
new **Notifications** README section, including the two intentional
simplifications (shared read-state on staff broadcasts, no true
pagination yet).

Found and fixed one bug during verification: `notify_vehicle_pending()`
only had an INSERT trigger, unlike its bookings equivalent
(`notify_booking_pending()`) which also fires when an edit reverts an
already-decided row back to pending - so editing an approved vehicle
correctly reverted it to pending, but staff never got notified there was
something new to review. Migration 0025 adds the missing UPDATE trigger.

Verified live end-to-end with a throwaway operator + staff account: a
seeded vehicle with CPC/OR-CR validity inside the 30-day window produced
both expiry notifications with the correct amber highlighting; clicking a
notification marked it read (badge count dropped) and navigated to its
linked page; editing that vehicle's fields round-tripped correctly
through `request_vehicle_change()`, reverted it to pending, and (after
the fix above) correctly notified staff; approving/rejecting it, and
inserting/approving a test booking, each produced exactly one correctly-
targeted notification. Test accounts, vehicles, bookings, and their
notifications all cleaned up afterward - the 200 real expiry
notifications already generated for real operators/staff from the actual
100 near-expiry vehicles were left in place, since those are correct,
not test data.

Updates README per project convention.

---

### 45. Sortable columns and reordered Status/LTFRB on the fleet pages (18 Aug)

**Vehicles** (staff fleet database): Plate No., Operator, CPC validity,
and OR/CR validity are now sortable - click a header to sort, click
again to flip direction, with an arrow indicator. Nulls always sort
last regardless of direction. **Status** and **LTFRB** moved to sit
immediately right of **Operator**, ahead of every other column, since
those are what staff scan for first. Client-side only - the whole fleet
is already loaded into memory (see #42's pagination fix), so re-sorting
it doesn't touch the network.

**My vehicles** (the operator's own list) got the same sort on Plate
No., CPC validity, and OR/CR validity - no Operator column there, since
that list is already scoped to one operator, so no column reordering
either (nothing to move relative to).

Verified live: clicking Plate No. sorted ascending with an arrow shown,
clicking again flipped to descending; Operator and both validity-date
sorts worked correctly, including nulls sorting last on both directions
(tested with 3 seeded vehicles with a null CPC, a null OR/CR, and both
set, to see the null-handling directly rather than relying on the real
data's incidental gaps). Header order confirmed via the DOM: Plate No.,
Operator, Status, LTFRB, then the rest.

---

### 46. Click a vehicle row for a details card, both roles (18 Aug)

Clicking anywhere on a vehicle row (My vehicles, and the staff fleet
database) now opens a read-only dialog showing every field on that
vehicle at once, rather than scrolling a wide table sideways to see it
all. One shared builder (`vehicleDetailsHtml()` in `app.js`) so the
field list/order can't drift between the two pages - the staff version
passes an extra Operator row up top that the operator's own list
doesn't need, since that list is already scoped to one account.

Clicking the Edit button (My vehicles) or a Documents link (either
page) does its own thing instead of also popping the details card, even
though both sit inside the clickable row - the row's click handler
explicitly excludes clicks that land on a `button` or `a`.

Verified live: clicking a row opens the card with the correct title and
every field populated (confirmed the staff version's extra Operator/
Status/LTFRB fields render, and the operator version correctly omits
Operator); Close works; clicking Edit opens only the edit dialog, not
the details card; a synthetic Documents link inside a row does not open
the details card either. Test accounts and seeded data cleaned up
after.

Updates README per project convention.

---

### 47. Clicking a vehicle notification highlights that row and opens its card (18 Aug)

A CPC/OR-CR expiry notification (or a vehicle approved/declined one)
previously just navigated to My vehicles or the staff fleet page -
correct page, but the reader still had to find the right row themselves
in a table that can run over a thousand rows. Now it takes them straight
to it.

The notification click handler (`app.js`) appends `?vehicle=<id>` to the
link whenever the notification's `related_table` is `vehicles`. Both
`vehicles.html` and `vehicles-database.html` call a new shared function,
`applyVehicleHighlightFromQuery()`, right after their first render: it
reads that query param, scrolls the matching row into view, adds a
`.row-highlighted` amber background, and opens that row's details card
(#46) automatically.

Verified live: seeded a vehicle with a CPC expiring within 30 days,
confirmed both its operator-side and staff-side expiry notifications
carry the correct `related_table`/`related_id`, and clicking either one
landed on the right page with the URL carrying `?vehicle=<id>`, the
correct row highlighted, and its details card already open showing the
right plate number. Test accounts and data cleaned up after.

Updates README per project convention.

---

### 48. Group the booking form's vehicle list by route (18 Aug)

Once a route is picked, the Plate No. dropdown on the booking form (and
the Change dialog) now groups the operator's vehicles into **Registered
for this route** and **Other vehicles** - a suggestion, not a hard
filter, matching the same non-blocking philosophy as the gate/bay
suggestions elsewhere in the app (#38, #40). Matching compares
significant word overlap between the canonical booking route ("Tabaco
City, Albay") and the vehicle's own free-text `route` field, ignoring
generic filler words ("CITY", "VIA", etc.) that don't mean anything on
their own. If nothing matches, the dropdown falls back to one flat list
- exactly as if no route were picked - since a franchise description
and a canonical route name can be worded differently enough that no
overlap exists (e.g. "Ilo-Ilo" vs "Iloilo"), and a vehicle should never
become unselectable because of that.

Verified live with a throwaway operator and 3 vehicles (one with a
route matching the picked booking route, one with an unrelated route,
one with no route set): picking a matching route correctly grouped the
matching vehicle alone under "Registered for this route"; picking a
route nothing matched correctly fell back to the flat list; the Change
dialog grouped and re-grouped live the same way, preserving the already-
selected plate through the switch. Test data cleaned up after.

Updates README per project convention.

---

### 49. Link masterlist vehicles' `route` to a canonical route (18 Aug)

#48's route-based vehicle grouping is only as good as `vehicles.route`
actually corresponding to a real canonical route - and for every
masterlist-imported vehicle, it didn't: `route` was set to the same
franchise-description text as the new `franchise` field (#44), a full
sentence like "TABACO, ALBAY- PASAY CITY" that the live word-overlap
matcher could only catch by accident. Re-matched all 1,832 masterlist
vehicles' original "OPERATING ROUTE" column (captured in the source
spreadsheet but never stored anywhere - #42's import used the fuller
FRANCHISE column for both `route` and `franchise`) against the 83
canonical routes, and set `route` to the matched canonical string for
any confident match - `franchise` is untouched, so the original
full-sentence description isn't lost either way.

**Two real matching bugs found and fixed before writing anything**,
both from generic words that happen to double as a place name:

- A canonical place that reduces to a single word after stripping
  filler ("Batangas City" → just "BATANGAS" once "City" is stripped)
  coincidentally equals the *province* name mentioned in nearly every
  other same-province entry ("Nasugbu, Batangas", "Calatagan,
  Batangas", ...) - a naive word-overlap match kept assigning all of
  them to Batangas City. Fixed by matching the town and province
  segments of each string separately, never letting a stray province
  mention count as the town.
- The same failure mode one level up: "Camarines" alone is shared by
  both Camarines Sur and Camarines Norte, so "Naga, Camarines Norte"
  matched Naga City, Camarines *Sur* on that shared word alone - caught
  by the user pointing out there's no real "Naga, Camarines Norte" (Naga
  City is in Camarines Sur). Fixed by only trusting a province word
  that's unique to exactly one canonical province, with a strict
  (not lenient) fallback when no word is unique - and left that specific
  row's `route` untouched, since the source data's province is simply
  wrong and guessing which real place was meant isn't safe.

Matching **never guesses**: a route is only linked when unambiguous
(exactly one canonical route qualifies); anything ambiguous (e.g. bare
"Nasugbu" - two canonical Nasugbu routes exist) or not in the canonical
list at all (Palawan, Cebu City, Guimaras - real places PITX just
doesn't have a canonical route for) is left as-is with no data lost,
since `franchise` still holds the full original text either way.

**Result**: 1,443 of 1,908 resolved rows matched confidently and got
`route` updated; 1,379 of those actually changed value (some already
happened to equal their match). Verified directly against the database
after writing: the flagged Naga/Camarines Norte rows are confirmed
still unlinked (route == franchise, untouched), and a sample of newly-
linked rows shows the clean canonical route alongside the original
franchise description intact.

---

### 50. Only link routes at city/municipality level, and stop falling back to the franchise sentence (18 Aug)

Two corrections to #49, both from user review:

**Never link on a bare province/island-level mention.** A canonical
place name that reduces to a single word which *also* happens to be a
province name (Batangas City → "BATANGAS", also the province in every
other Batangas-area entry; likewise Sorsogon City, Masbate City, Iloilo
City, Davao City) let a bare province mention alone ("MASBATE",
"BATANGAS", no city qualifier) satisfy that lone place-token and count
as a specific city match - which is exactly the province-level linking
the user asked not to do. Fixed by requiring the literal word "CITY" in
the operating route text for these five specific canonical routes
before accepting a match; a bare province/island name with no "CITY"
now falls through instead.

**Stop falling back to the franchise sentence.** When no confident
city-level match exists, `route` was reverting to `franchise` - the
full descriptive sentence ("SORSOGON CITY-PASAY CITY"). The user
pointed out the sheet's own "OPERATING ROUTE" column (already read for
matching, but only ever used to *derive* a canonical match, never
stored on its own) is the better fallback - shorter, closer to a real
route name, and it's what the match attempt was already based on
anyway. Re-ran the whole linking pass for all 1,832 masterlist vehicles
with both fixes together: `route` is now either the matched canonical
value, or the raw OPERATING ROUTE text - never the franchise sentence.

Result: 1,409 rows matched at confirmed city/municipality level (down
from 1,443 - the difference is exactly the bare province/island
mentions the stricter rule now correctly declines to guess at); 473
fell back to their own OPERATING ROUTE text instead of franchise.

Verified directly against the database: a bare "MASBATE" operating
route no longer links to Masbate City (none remain); "SORSOGON CITY-
PASAY CITY" franchise rows whose OPERATING ROUTE cell is itself just
bare "SORSOGON" (no "CITY") correctly stayed unlinked, with `route` now
showing that short text instead of the long franchise sentence; the
Naga/Camarines Norte rows from #49 still correctly show their own
operating-route text, not franchise, and remain unlinked.

---

### 51. A vehicle must actually be registered for the route it books (18 Aug)

#48's route-based vehicle grouping was a suggestion, not a requirement -
an operator could still pick any of their vehicles for any route. Now
it's a hard requirement: the Plate No. dropdown only offers vehicles
whose own route matches the one picked (same word-overlap matching as
#48); with none, the dropdown and Request button both disable with an
explanatory note. Same rule in the Change dialog.

**Enforced server-side, not just in the dropdown** (migration
`0026_vehicle_route_required.sql`): ported the client-side matching
function to SQL (`vehicle_matches_route()`/`route_tokens()`, kept in
lockstep with the JS version) and added it to `bookings_insert_own`'s
RLS check and to `request_booking_change()` - the dropdown filter is UX
only, same as everywhere else in this app; RLS is the real gate.

**Found a real bug in the first version while verifying live**: inside
the RLS policy's correlated `EXISTS` subquery, the bare `plate_no`/
`route` references (meant to mean the row being inserted) got shadowed
by the subquery's own `vehicles.plate_no`/`vehicles.route` columns of
the same name - Postgres resolved them to the innermost scope, silently
turning the check into "does this vehicle's plate/route equal itself,"
which is always true. Caught by deliberately bypassing the UI and
inserting a mismatched booking directly through the Supabase client -
it went through with no error. Fixed in migration `0027` by qualifying
the outer row explicitly as `bookings.plate_no`/`bookings.route` (the
table name itself works as the row's own qualifier in a `WITH CHECK`
expression when no alias was given).

Verified live end-to-end: the Plate No. dropdown correctly showed only
the one matching vehicle out of two, and correctly disabled with the
explanatory note (and a disabled Request button) when neither vehicle
matched the picked route. Then, bypassing the UI entirely: the same
mismatched insert that had silently succeeded under the buggy `0026`
policy came back with a `42501` RLS violation after `0027`'s fix, while
a matching insert still succeeded normally; `request_booking_change()`
correctly rejected a mismatched edit with a friendly error message.
Test data cleaned up after.

Updates README per project convention.

---

### 52. Route dropdown narrowed to the operator's own registered routes (18 Aug)

The Route field on the booking form now only lists routes at least one
of the operator's own vehicles is registered for - e.g. Genesis
Transport (vehicles registered only for Balanga, Clark, and Mariveles,
confirmed against the live data before building this) only ever sees
those three, not the other 80. Falls back to the full list rather than
showing nothing if the operator has vehicles but none match any
canonical route at all, so this can never lock someone out entirely.
Same narrowing in the **Change** dialog, still preserving a booking's
current route as an option even if it's since fallen outside the
matched set. (`routesWithRegisteredVehicle()` in `docs/dashboard.html`.)

**Found and fixed two real bugs while verifying this live:**

- **A temporal-dead-zone bug**, the same class this codebase has hit
  before (#37/#39/#46): `initForm()` (called at module top-level) now
  calls the new function, which needs `ROUTE_STOPWORDS` - but that
  `const` was declared later in the file than where the call actually
  executes. Symptom: the Route dropdown rendered completely empty, with
  a `ReferenceError: Cannot access 'ROUTE_STOPWORDS' before
  initialization` in the console. Fixed by moving the declaration up
  into the file's existing early-module-state block, same fix pattern
  as every prior occurrence of this bug.
- **A real province-vs-city matching bug**, on both sides: comparing
  *full* route token sets let two different towns in the same province
  match each other purely on the shared province word - "Mariveles,
  Bataan" was incorrectly offered as a valid vehicle for a "Balanga,
  Bataan" booking, both client-side (the plate dropdown) and
  server-side (`bookings_insert_own`, `request_booking_change()`),
  since neither had been updated when the *data* got the equivalent fix
  in #50. Fixed both: `routeTownPart()`/`vehicleMatchesRoute()` in
  `docs/dashboard.html`, and `route_town_part()`/`vehicle_matches_route()`
  in migration `0028` - matching now compares only the town segment
  (before the first comma) of each route, never the full string.

Verified live with a test operator seeded with vehicles for Balanga,
Clark, and Mariveles (mirroring Genesis Transport's real registrations,
confirmed directly against the database first): the Route dropdown
showed exactly those three; after the TDZ fix, no console errors;
before the town-vs-province fix, the Mariveles vehicle wrongly appeared
as an option for a Balanga booking and a direct bypass insert with that
mismatch silently succeeded - after the fix, the dropdown correctly
excluded it and the same bypass insert correctly got a `42501` RLS
violation, while a legitimate matching insert still succeeded. Test
data cleaned up after.

Updates README per project convention.

---

### 53. Re-check every operator for missed route links (18 Aug)

User report: Jam Liner was missing routes it should have had (some of
its Lucena City vehicles weren't showing up under that route). Audited
every operator's vehicles for the same class of problem - vehicles
whose `route` never got linked to a canonical route during #49/#50/#52,
even though a link should have been possible - and fixed four real gaps
in the matching logic that were causing correctable cases to be missed
across many operators, not just Jam Liner:

- **Multiple parenthetical asides confused the town/province split**:
  "TABACO (ALBAY) - CUBAO (QUEZON CITY)" has two `(...)` groups: the
  old code anchored to the *last* one (`QUEZON CITY`, unrelated) instead
  of the first (`ALBAY`, the actual province), so the province check
  always failed. Now takes the first parenthetical group.
- **The risky-place "needs CITY" check didn't require adjacency**:
  "LIPA CITY BATANGAS" contains the word "CITY" *somewhere*, which was
  enough to let Batangas City wrongly tie with Lipa City for the match,
  making the whole row ambiguous and unmatched. Now requires "CITY"
  immediately next to the specific risky place name ("BATANGAS CITY",
  not just "CITY" anywhere in the string).
- **Bare province mentions couldn't disambiguate multi-way ties**: "SAN
  JOSE, MINDORO" (no Occidental/Oriental qualifier) was rejected because
  the distinctive-province-token check was computed against *all 83
  routes*, where "MINDORO" isn't unique enough - even though, among just
  the 5 "San Jose" candidates specifically, only one is in Mindoro at
  all. Now computes distinctiveness within the tied candidate set, not
  globally.
- **A new explicit-conflict rule replaces the old blanket province
  check**: directional/type qualifiers (NORTE/SUR, OCCIDENTAL/ORIENTAL,
  NORTHERN/EASTERN/SOUTHERN/WESTERN) now only reject a candidate when
  they *actively contradict* it (still correctly rejects "NAGA,
  CAMARINES NORTE" against the real Naga City, Camarines *Sur* -
  verified no regression), rather than requiring an exact word match
  that abbreviations or bare mentions couldn't satisfy.
- **One manual sub-locality alias**: "COTTA" is a district within Lucena
  City (confirmed by manual review, not an algorithmic guess) with no
  shared words with "Lucena" at all - added as an explicit alias so
  "COTTA( LUCENA QUEZON)" links to Lucena City, Quezon.

Re-ran the linking pass across every operator's masterlist vehicles
(only re-attempting rows not already linked - nothing already-canonical
was touched). Verified directly against the database: Lipa City
Batangas, San Jose Occidental Mindoro, Maasin City Southern Leyte,
Catarman Northern Samar, Tabaco City Albay, and Gubat Sorsogon cases
across several different operators are now all correctly linked; the
Naga/Camarines Norte rows are confirmed still correctly unlinked (no
regression on the fix from #49). Jam Liner specifically: its Lucena
City, Quezon vehicle count went from 29 to 36 once its Cotta-district
vehicles linked correctly.

**Separate finding, not fixed here**: Jam Liner (and several other
operators) also has vehicles for Bauan (Batangas), Biñan (Laguna), Boac
(Marinduque), Pacita Complex (Laguna), and Santa Rosa (Laguna) - real
destinations that simply aren't among PITX's 83 canonical routes at
all. No amount of matching-logic improvement links these, since there's
nothing to link to; adding a new canonical route is a bigger decision
(new gate assignment, etc.) than a data-linking fix, so these are left
as-is pending that decision rather than invented unilaterally.

No app code changed for this pass - only the one-off data-linking
script's matching logic, since the live runtime matcher (`dashboard.html`,
migration `0028`) already works correctly once `vehicles.route` holds an
exact canonical string; the improvements only mattered for this one-time
re-linking pass itself.

---

### 54. Re-link routes from the cleaned masterlist instead of fuzzy text matching (18 Aug)

User: "For the routes, use the cleaned data of the vehicle masterlist for
your reference as to reduce confusion" - handed over a cleaned version
of the vehicle masterlist workbook whose `PROVL` sheet has previously-empty
`City / Municipality` and `Province` columns now properly filled in per
vehicle (the original workbook had these columns present but 100% empty,
so #49/#50/#53 had no choice but to fuzzy-match the free-text "OPERATING
ROUTE"/"FRANCHISE" columns).

Replaced the one-off data-linking script's approach entirely: instead of
parsing free text with word-token matching, each row's `City /
Municipality, Province` pair is looked up directly against the 83
canonical routes (normalizing only "Sta./Sto." &#8594; "Santa/Santo" and an
optional "City" suffix - not fuzzy matching). Vehicles are matched to
their DB row by **plate number** (unique and already in both the
masterlist and the `vehicles` table), not by resolving operator names,
which sidesteps the operator-name-alias matching entirely for this pass.

Of 1,832 vehicles: 1,413 already had the correct canonical route; 117
were corrected, including several rows previously stuck with obviously
wrong text like `"SORSOGON"`, `"MASBATE"`, `"SABANG"`, and - notably -
confirms and fully resolves the `"NAGA, CAMARINES NORTE"` cases flagged
in #49/#53 as not a real place: the cleaned data independently confirms
those vehicles are actually Naga City, Camarines **Sur**, and all 47 are
now linked there. 87 "Nasugbu, Batangas" vehicles remain unresolved
because the cleaned data (and the operators' own route/franchise text)
doesn't say whether they run via Aguinaldo or via Kaybiang Tunnel - the
two canonical Nasugbu routes are only distinguished by that detail, so
these were left untouched rather than guessed. 63 vehicles had no
City/Municipality or Province in the cleaned sheet at all and were also
left untouched.

**Separate finding, expanded**: 152 vehicles (up from the partial list
noted in #53) have a clean, confidently-identified City/Municipality +
Province that simply isn't among PITX's 83 canonical routes - the fuller
list, now backed by clean data instead of guesses: Mabalacat City
(Pampanga), San Pedro (Laguna), Guiuan (Eastern Samar), Placer (Masbate),
Cebu City (Cebu), Caramoan (Camarines Sur), Biñan (Laguna), Maragondon
(Cavite), Pasacao (Camarines Sur), Boac (Marinduque), Presentacion
(Camarines Sur), Garchitorena (Camarines Sur), Donsol (Sorsogon), Santa
Rosa (Laguna), Prieto Diaz (Sorsogon), Bauan (Batangas), Muntinlupa City
(Metro Manila), Mandaon (Masbate). As before, adding a canonical route is
a bigger decision (new gate assignment, etc.) than a data-linking fix, so
these are left as-is pending that decision.

Verified directly against the database: `route ILIKE '%NAGA%CAMARINES
NORTE%'` now returns 0 rows (was silently wrong before); `route =
'Naga City, Camarines Sur'` returns 47; spot-checked plates NKK8480 -&gt;
Masbate City, Masbate, ARA5827 -&gt; Buhi, Camarines Sur, TYZ138 -&gt; Mendez
(Mendez-Nuñez), Cavite all confirmed correct post-update.

No app code changed - same as #53, this was purely a one-time data
correction; the live runtime matcher already works correctly once
`vehicles.route` holds an exact canonical string. `vehicles.franchise`
was left untouched throughout, as always.

---

### 55. Merge the Nasugbu routes, add the 18 missing destinations (18 Aug)

User: "Merge all Nasugbu, Batangas as one Nasugbu Batangas and add the
152 vehicles with real destination then update the canonical routes" -
direct follow-up to #54's two open items.

**`ROUTES` in `docs/assets/app.js` (and its `ROUTE_GATES` map) updated,
83 &#8594; 100 entries:**

- `"Nasugbu Via Aguinaldo, Batangas"` and `"Nasugbu Via Kaybiang Tunnel,
  Batangas"` merged into one `"Nasugbu, Batangas"` - the cleaned
  masterlist (and the operators' own route text) can't say which via a
  vehicle actually runs, so keeping two entries was manufacturing a
  distinction the data can't support.
- 18 new canonical routes added for the real destinations #54 found with
  registered vehicles but no matching canonical route: Mabalacat City
  (Pampanga, Gate 5), San Pedro, Biñan, Santa Rosa (Laguna, Gate 2),
  Maragondon (Cavite, Gate 2), Bauan (Batangas, Gate 2), Boac
  (Marinduque, Gate 2), Caramoan, Pasacao, Presentacion, Garchitorena
  (Camarines Sur, Gate 4), Donsol, Prieto Diaz (Sorsogon, Gate 4),
  Placer, Mandaon (Masbate, Gate 4), Cebu City (Cebu, Gate 4), Guiuan
  (Eastern Samar, Gate 4), and Muntinlupa City (Metro Manila).
- **Muntinlupa City, Metro Manila is flagged, not just added quietly**:
  every other route in this list is provincial (matching the app's whole
  premise of provincial operators booking a bay at PITX); Muntinlupa is
  in NCR, same as PITX itself, and only 1 of 1,832 vehicles maps there.
  It doesn't fit the Gate 2/4/5 scheme at all, so it's deliberately left
  out of `ROUTE_GATES` (falls back to "show every bay" per
  `gateForRoute()`'s existing null-handling) rather than assigning it a
  made-up gate. Worth a staff double-check on whether this one vehicle's
  data is real or a masterlist error - not corrected unilaterally, same
  standard applied to the Naga/Camarines Norte case in #49/#54.

**Data re-linked against the DB** using the same cleaned-masterlist
lookup as #54, re-run against the expanded 100-route list: 239 vehicles
updated (87 Nasugbu vehicles merged onto the single new entry, 152 onto
the 18 new routes), 1,530 already correct, 63 still without clean
City/Municipality/Province data left untouched. Zero ambiguous or
unmatched rows remained after the expansion - verified directly against
the database (`route ILIKE '%via aguinaldo%' or '%via kaybiang%'` now
returns 0 rows; each of the 18 new routes' vehicle counts confirmed
against the per-plate cleaned-data lookup).

No RLS/migration changes needed - `ROUTES` is a UI-only picklist (nothing
in the database enforces it against a fixed enum), so the live matching
functions (`vehicle_matches_route()`, `route_town_part()` from migration
`0028`) work unchanged against the new route strings.

---

### 56. Fix a live bug: accented town names could never match themselves (18 Aug)

User report: "Why is there no Biñan Laguna in Jam Liner". Jam Liner's
vehicles *were* correctly linked to `"Biñan, Laguna"` in the database
(#54/#55) - the bug was in the matching logic itself, both client-side
and, more seriously, in the RLS check that actually enforces #51's "must
have a matching vehicle" rule.

`routeTokens()` (`dashboard.html`) and its SQL port `route_tokens()`
(migration `0026`) strip every character outside `[A-Za-z0-9 ]` in one
blanket pass - including accented letters. `"BIÑAN"` has its `"Ñ"`
replaced with a bare space, becoming `"BI AN"`: two 2-letter fragments
that the `length >= 3` significant-word filter then throws away
entirely. `route_tokens('Biñan, Laguna')` returned zero tokens for the
town part, so `vehicle_matches_route('Biñan, Laguna', 'Biñan, Laguna')`
returned **false** - confirmed directly against the database. Any route
whose town name contains an accented letter can never match itself this
way; Biñan is the only one currently on the list, but the bug is generic
(not name-specific).

This isn't just a dropdown cosmetic gap - `vehicle_matches_route()` is
what `bookings_insert_own`'s RLS `WITH CHECK` and `request_booking_change()`
actually enforce (#51). A Jam Liner vehicle correctly registered for
Biñan, Laguna would be **rejected outright** trying to book that exact
route, with no way around it from the UI.

Fixed both sides the same way: map each accented letter to its base
letter (`Ñ`&#8594;`N`, `Á`&#8594;`A`, etc.) *before* the non-alphanumeric strip,
instead of letting that strip erase it as if it carried no letter at
all. JS fix in `routeTokens()`; SQL fix via `CREATE OR REPLACE` in new
migration `0029_route_tokens_diacritics.sql` (same signature, no `DROP`
needed).

Verified directly against the database post-migration:
`route_tokens('Biñan, Laguna')` now returns `{BINAN, LAGUNA}`;
`vehicle_matches_route('Biñan, Laguna', 'Biñan, Laguna')` now returns
`true`; all 7 of Jam Liner's Biñan vehicles now match; re-checked
`vehicle_matches_route('Mariveles, Bataan', 'Balanga, Bataan')` still
returns `false` - no regression on the town-vs-province fix from #51.

---

### 57. Search the fleet database by route (18 Aug)

User: "Allow searching of routes in the searchbar of the vehicle
database page of Staff" - `vehicles-database.html`'s search box already
matched plate no., bus no., operator name, and username, but not a
vehicle's `route`, even though Route is one of the visible table
columns. Added `v.route` to the filtered fields and updated the search
box's placeholder text ("Plate no., operator, bus no., or route…") to
match. No new UI, no schema change - `route` was already selected by the
page's existing query.

---

### 58. Rebuild the canonical route list from the masterlist, not Sheet5 (18 Aug)

User: "For the request bus bay slots, forget the initial canonical
routes delete that and don't recall that anymore. Use the Column J,K for
the routes for example 'Santa Rosa, Laguna'. Also update the vehicle
database operating route with 'Santa Rosa, Laguna' to avoid confusion" -
a deliberate pivot, not another patch: stop treating the operator
database's "Sheet5" as the source of truth for what routes exist at all,
and derive `ROUTES` purely from the cleaned vehicle masterlist's own
City/Municipality (column J) and Province (column K) columns instead.

**`ROUTES` and `ROUTE_GATES` in `docs/assets/app.js` fully replaced**,
83/100 entries &#8594; **91 entries** - every one of them exactly the
masterlist's own spelling, with only "Sta./Sto." abbreviations expanded
to "Santa/Santo" (matching the user's own example: the masterlist has
"Sta. Rosa, Laguna", expanded here to "Santa Rosa, Laguna"). Notable
consequences of switching sources entirely:

- **Some Sheet5 routes are gone** because zero vehicles in the
  masterlist are actually registered for them - there was nothing to
  link and no reason to keep offering them: "Tagaytay City, Cavite",
  "Amadeo, Cavite", "Naval, Biliran", "Pintuyan, Southern Leyte", "San
  Jose, Antique", "Clark, Pampanga", "Junction Luna (Abulug), Cagayan",
  "Roxas, Oriental Mindoro", "Nabua, Camarines Sur".
- **Several routes changed spelling** to match the masterlist exactly
  instead of Sheet5's phrasing: "Balanga, Bataan" &#8594; "Balanga City,
  Bataan", "Tuguegarao, Cagayan" &#8594; "Tuguegarao City, Cagayan", "San
  Jose, Nueva Ecija" &#8594; "San Jose City, Nueva Ecija", "San Carlos,
  Pangasinan" &#8594; "San Carlos City, Pangasinan", "Dagupan, Pangasinan"
  &#8594; "Dagupan City, Pangasinan", "Laoag, Ilocos Norte" &#8594; "Laoag City,
  Ilocos Norte", "General Santos, South Cotabato" &#8594; "General Santos
  City, South Cotabato", "Mendez (Mendez-Nuñez), Cavite" &#8594; "Mendez,
  Cavite", "Sta.Ana, Cagayan" &#8594; "Santa Ana, Cagayan".
- Gates re-derived from each route's own province using the same
  Gate 2/4/5 grouping as before (Cavite/Batangas/Laguna/Quezon/Mindoro,
  Bicol/Visayas/Mindanao, CAR/Regions I-III) - not carried over from the
  old map, since several routes' spelling changed.

**Vehicle data re-linked to match** ("update the vehicle database
operating route... to avoid confusion"): re-ran the plate-number lookup
against the masterlist one more time, this time writing the *exact*
`{City/Municipality}, {Province}` text (after the same Sta./Sto.
expansion) with no other normalization - 122 vehicles updated (mostly
the spelling changes above), 1,656 already matching, 54 still without
clean masterlist data left untouched as before. Verified directly:
`vehicles.route = 'Santa Rosa, Laguna'` now returns the 2 vehicles the
user's example was about; zero leftover "Sta. Rosa"-style abbreviations
remain in the vehicles table; confirmed only 4 pre-existing vehicles
still carry non-canonical raw text (`SAN JOSE`, `NEGROS OCCI.`,
`PALAWAN`, `GUIMARAS ISLAND` - real gaps in the masterlist's own data,
not something this pass can fix) and 13 pre-existing bookings use
free-text or now-dropped route names, both already covered by the
Change dialog's existing "not in the current list" fallback.

No RLS/migration changes needed, same as #55 - `ROUTES` is a UI-only
picklist.

---

### 59. Fix "Santa X" routes bleeding into each other via the shared honorific (18 Aug)

User report (screenshots): an operator whose vehicles are all "Santa
Cruz, Laguna" saw "Santa Rosa, Laguna" offered in the Route dropdown too,
despite having no vehicle registered for it - same bug class as #56,
same root cause: `routeTokens()`'s significant-word matching treats
`"SANTA"` as just another word, not a filler. `"Santa Cruz"` and `"Santa
Rosa"` tokenize to `{SANTA, CRUZ}` and `{SANTA, ROSA}`, which overlap on
`"SANTA"` - `vehicle_matches_route('Santa Cruz, Laguna', 'Santa Rosa,
Laguna')` returned **true**. Confirmed directly against the database.
This hit the RLS enforcement (#51), not just the dropdown - the actual
booking-time check would let a Santa Cruz vehicle through for a Santa
Rosa slot.

Fixed by adding `"SAN"`, `"SANTA"`, `"SANTO"` to the stopword list
already used to drop generic filler like `"CITY"`/`"VIA"` - the same
place other filler words are filtered, not a special case. Checked all
91 routes in the current list first: every "San "/"Santa "/"Santo "
route has a second, distinguishing word (Cruz, Rosa, Jose, Juan, Andres,
Pedro, Elena, Ana, Carlos...), so none collapse to zero tokens once the
honorific itself is dropped - same safety check done for the diacritics
fix in #56. JS fix in `routeTokens()`; SQL fix via migration
`0030_route_tokens_san_santa_stopwords.sql` (`CREATE OR REPLACE`, same
signature as before).

Verified directly against the database post-migration:
`vehicle_matches_route('Santa Cruz, Laguna', 'Santa Rosa, Laguna')` now
`false`; `vehicle_matches_route('Santa Rosa, Laguna', 'Santa Rosa,
Laguna')` still `true`; re-checked #56's Biñan fix and #51's Balanga/
Mariveles town-vs-province fix both still hold, no regressions.

**Noted but not fixed here** (pre-existing, unrelated to this bug): four
different routes are literally named "San Jose" in different provinces
(Nueva Ecija, Occidental Mindoro, Camarines Sur, Dinagat Islands) and
always collided with each other via the shared "JOSE" town-part token,
both before and after this fix - town-only matching can't distinguish
same-named towns in different provinces. Not introduced or resolved by
this change.

---

### 60. Restart vehicle-route matching as plain equality, not fuzzy word overlap (18 Aug)

User: "For the bus bay slot reservation, I need you to restart. The
operator should only see the routes where they have registered vehicles
in it then the vehicles plate number will be filtered based on the
route." Both halves of this were already built (#51/#52 for the route
narrowing, #48 for the plate filter) - but every refinement to the
underlying matching rule kept surfacing a new false-positive bug
(#56 diacritics, #59 SAN/SANTA/SANTO), because the rule itself - word-
overlap between a vehicle's free-text route and a canonical booking
route - was the wrong tool for data that's no longer free text.

Since #58 rebuilt `ROUTES` directly from the cleaned masterlist and
re-linked vehicles against it, `vehicles.route` holds the *exact*
canonical string for the overwhelming majority of vehicles (checked
directly: 1,778 of 1,832, and - the number that actually matters -
every operator with at least one approved vehicle has at least one
exact canonical match, so nobody falls through to the "no matches, show
everything" fallback). Fuzzy matching was solving a problem that no
longer exists.

Replaced `vehicleMatchesRoute()` with plain equality
(`vehicle.route === bookingRoute`), deleting `routeTokens()`,
`routeTownPart()`, and `ROUTE_STOPWORDS` entirely - three rounds of
increasingly-specific-case patches (#48, #51, #56, #59) collapse into
one line. Mirrored server-side: `vehicle_matches_route()` (the function
`bookings_insert_own`'s RLS `WITH CHECK` and `request_booking_change()`
actually enforce) is now `p_vehicle_route IS NOT DISTINCT FROM
p_booking_route AND p_vehicle_route IS NOT NULL` via migration
`0031_vehicle_matches_route_exact.sql`; `route_tokens()` and
`route_town_part()` are dropped outright rather than left as dead code,
since nothing else in the schema calls them.

The two operator-facing behaviors themselves are unchanged - Route
dropdown narrowed to the operator's own registered routes
(`routesWithRegisteredVehicle()`), Plate No. dropdown hard-filtered to
vehicles matching the selected route (`plateOptionsHtml()`) - only the
matching rule underneath changed.

Verified directly against the database post-migration:
`vehicle_matches_route('Santa Rosa, Laguna', 'Santa Rosa, Laguna')` true,
`vehicle_matches_route('Santa Cruz, Laguna', 'Santa Rosa, Laguna')` now
false, Biñan and Balanga/Mariveles cases from #56/#51 still correct,
`route_tokens`/`route_town_part` confirmed dropped, Jam Liner's 7 Biñan
vehicles still match.

---

### 61. Transfers now require the receiving operator to match the route too (18 Aug)

User: "For the transfer option, they may only select operators with the
same route and vehicles must also be filtered based on the route." The
transfer dialog (#10/#16) let a sender pick *any* other operator account
and *any* of that operator's approved vehicles, with no route check at
all - a "Batangas City, Batangas" booking could be handed to an operator
(and a specific vehicle) with nothing to do with that route. Applied the
same "must be registered for the route it books" rule #51/#60 already
enforce for the original operator, to the receiving side too.

- `list_operator_accounts()` now takes the booking's route and only
  returns operators with at least one approved, LTFRB-eligible vehicle
  registered for it - no point offering an operator who could never
  actually take the booking. Since which route applies depends on which
  specific booking is being transferred, this is no longer preloaded
  once at page load - it's loaded fresh each time the transfer dialog
  opens, for that booking's route.
- `list_operator_vehicles()` now also takes that route and only returns
  the chosen operator's vehicles registered for it - same narrowing the
  booking form already applies to the sender's own plate dropdown.
- `request_booking_transfer()` re-validates the route match server-side
  (migration `0032_transfer_recipient_route_match.sql`) - the dropdowns
  above are UX only, same as everywhere else in this app. Both `list_*`
  functions change their parameter list (route added), so they're
  `DROP FUNCTION` + `CREATE`, not `CREATE OR REPLACE`. All three reuse
  `vehicle_matches_route()` (#60's plain-equality rule) rather than a
  separate check - one source of truth for "is this vehicle registered
  for this route," used everywhere it's asked.

Verified with a full authenticated round-trip using three throwaway test
operators (cleaned up after): A and B each with an approved vehicle on
"Santa Rosa, Laguna", C with one on "Batangas City, Batangas" only, and
a real booking by A for "Santa Rosa, Laguna". Signed in as A:
`list_operator_accounts` correctly returned B (and any other Santa
Rosa-registered operator) but not C and not A itself;
`list_operator_vehicles` correctly returned B's matching vehicle and an
empty list for C; `request_booking_transfer` to B's vehicle succeeded;
a direct bypass attempt - calling `request_booking_transfer` straight at
C's wrong-route plate, skipping the dropdowns entirely - was correctly
rejected server-side with "That plate isn't one of the receiving
operator's approved vehicles registered for this booking's route."

---

### 62. Day and Week views for both schedule pages (19 Aug)

User: "For the schedule, I want to have a weekly view and a daily view.
Do this for all accounts." Added a **Day / Week** toggle to both
schedule pages - `schedule.html` (staff) and `my-schedule.html`
(operators) - so "all accounts" means both roles, not just one.

Added `startOfWeek()`/`weekDates()` to `docs/assets/app.js` (Monday-start
weeks) so both pages derive week boundaries the same way instead of each
re-implementing it.

**Staff (`schedule.html`)**: Day view is unchanged - the full per-slot
capacity grid for one date, with every booking listed and the
bay-reassignment control. Week view is a new 7-row summary table (one
row per day of the week containing the selected date: approved,
awaiting review, slots at capacity), not the full per-slot detail -
a 48-row-by-7-column grid would be unusably dense, so Week trades detail
for an at-a-glance view of the whole week, with a **View day** link on
each row that jumps straight into Day view already on that date. Prev/
Next step by a day or a week depending on which mode is active.

**Operators (`my-schedule.html`)**: replaced the old "Upcoming / All"
filter with the same Day/Week toggle - Week (the new default) shows all
7 days of the week, *including empty ones* (each showing "No approved
slots" so the week's shape stays visible, same reasoning as the old
"show every day" behavior just scoped to a week instead of everything at
once), Day shows a single date. Both reuse the existing per-booking
timeline card layout, just repeated once per date shown.

Verified with a full authenticated visual walkthrough (throwaway staff +
operator test accounts, cleaned up after): seeded bookings across
several days of one week, confirmed both pages' Week view correctly
showed empty days, today highlighted, and per-day figures matching the
seeded data; confirmed Day view unchanged for both roles; confirmed
staff's "View day" link switches into Day view on the exact date
clicked, with matching figures.

---

## What the app does now

**Operators** — fill in a one-time company profile (name, owner, TIN, OR
serial number, booking system, two contacts); register vehicles (scan or
manual entry) with fields matching the PITX/MWM Terminals paper form
exactly (Case No., MV File #, Route, Bus No., Seating capacity, Seat type,
Aircon, Date granted, Date expiry); request a 30-minute slot by picking a
plate from their *approved* vehicles; see status, assigned bay, and any
rejection note; filter their own requests by status; change a booking or a
vehicle (back to staff for approval either way); cancel a pending booking.

**PITX staff** — approve or reject vehicle registrations and booking
requests (assigning an available bay on approval); view a day-by-day
30-minute-slot schedule with approved-vs-capacity; add/deactivate bays;
create operator and staff logins.

**Enforced by the database, not just the UI**

- Operators can only ever see and act on their own bookings and vehicles
  (RLS).
- Only staff can approve, reject, manage bays, or read all profiles.
- A unique index prevents two staff from approving the same bay for the
  same hour.
- Operators cannot assign themselves a bay, or approve their own vehicle,
  even by crafting a request directly against the database — verified with
  a live penetration attempt, not just a policy read-through (see `a186bfa`
  below).

---

## Verified by testing

Each of these was exercised in a browser against the live Supabase project:

- Login for both roles, and redirect to the correct home page
- Signed-out visitors bounced to login; operators blocked from staff pages
- Submitting a booking request
- Approving with a bay assigned; rejecting with a reason
- Operator seeing approved status, assigned bay, and rejection note
- Cancelling a pending request
- Changing an approved booking → reverts to pending, bay released
- Staff seeing the "changed after approval" badge, then re-approving
- Schedule reflecting the moved booking and correct capacity counts
- Bays listing in ascending order; Accounts listing existing users
- Form text rendering black; no console errors on any page
- Registering a vehicle by scan (real OCR pipeline, synthetic OR/CR image)
  and by manual entry; duplicate-plate rejection
- Vehicle approve/reject; edited-after-approval reverting to pending and
  disappearing from the booking dropdown, then reappearing once
  re-approved
- RLS penetration test: an authenticated operator's raw SQL attempt to
  self-approve a vehicle affects zero rows
- Every page's tables and forms at 375px width: no hidden columns, no
  page-level horizontal scroll, desktop layout unchanged

**Not yet verifiable:** creating accounts from the Accounts page, which
needs the Edge Function deployed (see below). It currently shows a clear
error rather than failing silently.

---

## Outstanding — needs your account access

1. ~~Point GitHub Pages at `/docs`.~~ **Done** — live at
   <https://jm-jaramillo.github.io/PITX-Trip-Scheduling/>.

2. **Deploy the Edge Functions** so staff can create *and delete* accounts
   in-app. Not done yet (confirmed: the `create-account` endpoint 404s as
   of this writing; `delete-account` is new as of #29 and hasn't been
   attempted):

   ```bash
   npx supabase login
   npx supabase link --project-ref nuezknlzwfkfxlicrgol
   npx supabase functions deploy create-account
   npx supabase functions deploy delete-account
   ```

   Until then, use `npm run create-staff` / `npm run create-operator` /
   `npm run delete-account` locally.

---

## Known gaps

- **Operators can't cancel an *approved* booking** — only pending ones. If a
  bus won't arrive for a confirmed slot, there's no operator-side way to
  release that bay.
- **No forced password change** on first login; staff-set temporary
  passwords stay valid indefinitely and are visible on-screen when created.
- **Test data and test accounts** (`pitx.admin`, `genesis.ops`, and sample
  bookings/vehicles) are still in the database, and their credentials have
  been shared in this chat. Change those passwords or remove the accounts
  before real use.
- **No audit trail** beyond `decided_by` / `decided_at` and a revision
  counter — there's no history of what a booking's or vehicle's previous
  values were.
- **No notifications** — operators must open the app to see a decision on
  a booking or a vehicle.
- **A booking's plate number is plain text, not linked to a vehicle
  record.** If the vehicle it came from is later edited or rejected, the
  booking itself is untouched — there's no way to see which bookings used
  which vehicle registration.
- **No limit on vehicles per operator**, and no per-operator cap on
  concurrent pending vehicle submissions.
- **The receiving operator has no in-app acceptance step for a transfer.**
  Whoever currently owns the booking just types in the other operator's
  username and plate; PITX staff are the only check that the "internal
  agreement" is real before the booking silently moves to a different
  account. There's also no notice to the *original* operator once staff
  approve it — the booking simply stops appearing in their "My requests"
  list.
- **A transfer only remembers one hop back.** If a booking is transferred
  twice, the schedule/dashboard strikethrough shows only the immediately
  preceding operator, not the full chain.
- **OCR accuracy depends entirely on photo quality.** It was verified
  against a clean, straight-on synthetic image; real photos — glare, skew,
  worn print — will do meaningfully worse. That's inherent to running OCR
  client-side for free, not a bug to fix later.
- **Fonts load from Google Fonts at runtime** (Manrope/Inter) — an external
  dependency GitHub Pages doesn't control. Fine unless the terminal network
  blocks it, in which case pages fall back to the system font.
- **The Edge Function still isn't deployed** (see "Outstanding" below), so
  account creation from the in-app Accounts page doesn't work yet — use
  `npm run create-staff` locally in the meantime.
- **No staff-facing view of operator profiles.** Staff can read the
  `operator_profiles` table (RLS already allows it), but there's no page
  showing it yet — only the operator who owns a profile can currently see
  it in the UI.
- **Vehicle fields changed twice in one day** (0006 added franchise
  number/body number/seat configuration; 0008 replaced them). Anyone who
  registered a vehicle under the old field set lost that data on the 0008
  cutover — there was no real data to preserve at the time, but worth
  knowing if this pattern recurs: an additive migration followed by a
  replacing one, both against a live database, is a data-loss risk on
  the second migration if real records exist by then.
- **The 4-hour lead time only restricts operators.** Staff can still
  approve or reject a request with any amount of time left (by design -
  otherwise a request submitted with 4h01m of notice could become
  unapprovable the moment staff get to it), and operators can still
  cancel a pending booking inside the 4-hour window (also by design -
  only asked to restrict creation and modification, not cancellation).
  Worth deciding whether cancellation should eventually have its own
  cutoff too.
