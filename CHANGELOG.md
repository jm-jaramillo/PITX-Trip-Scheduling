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
| Slot length | Exactly one hour, 24/7 |
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

---

## What the app does now

**Operators** — register vehicles (scan or manual entry); request an hourly
slot by picking a plate from their *approved* vehicles; see status, assigned
bay, and any rejection note; change a booking or a vehicle (back to staff
for approval either way); cancel a pending booking.

**PITX staff** — approve or reject vehicle registrations and booking
requests (assigning an available bay on approval); view a day-by-day hourly
schedule with approved-vs-capacity; add/deactivate bays; create operator and
staff logins.

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
