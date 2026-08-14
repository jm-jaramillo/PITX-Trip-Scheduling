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

2. **Deploy the Edge Function** so staff can create accounts in-app. Not
   done yet (confirmed: the endpoint 404s as of this writing):

   ```bash
   npx supabase login
   npx supabase link --project-ref nuezknlzwfkfxlicrgol
   npx supabase functions deploy create-account
   ```

   Until then, use `npm run create-staff` locally.

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
