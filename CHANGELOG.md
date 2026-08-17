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
