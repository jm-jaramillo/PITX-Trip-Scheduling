// Shared helpers for the static PITX bus bay booking pages.
//
// Each page is a plain HTML document that imports this module, calls
// `guardPage()` to enforce auth/role, then renders itself by querying
// Supabase directly from the browser. Row Level Security is the real
// access-control boundary - these client-side role checks only decide what
// UI to show, and a tampered client still can't read or write anything RLS
// forbids.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.3";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/** Supabase Auth needs an email; accounts here log in with a username. */
const USERNAME_DOMAIN = "pitx.local";

export function usernameToEmail(username) {
  return `${username.trim().toLowerCase()}@${USERNAME_DOMAIN}`;
}

/* ---------------------------------------------------------------- routes */

// The fixed set of PITX-served provincial routes - a booking's route is
// picked from this list rather than typed freehand, so it can't drift
// into near-duplicate variants of the same route. Sourced from the
// operator database spreadsheet's "Sheet5" (destination/province/region,
// filtered to "Operational" status), which supersedes the original
// 8-route "Routes" sheet - those 8 were already a subset of this list,
// just with slightly different phrasing (e.g. "Tuguegarao City, Cagayan"
// here is "Tuguegarao, Cagayan"). Existing bookings using the old
// phrasing aren't renamed; the Change dialog's "not in the current list"
// fallback (see dashboard.html) already handles a stored route that
// doesn't match an entry here.
export const ROUTES = [
  "Baguio City, Benguet",
  "Lagangilang, Abra",
  "Banaue, Ifugao",
  "San Carlos, Pangasinan",
  "Dagupan, Pangasinan",
  "Laoag, Ilocos Norte",
  "Tuguegarao, Cagayan",
  "Sta.Ana, Cagayan",
  "Junction Luna (Abulug), Cagayan",
  "Olongapo City, Zambales",
  "San Jose, Nueva Ecija",
  "Balanga, Bataan",
  "Clark, Pampanga",
  "Mariveles, Bataan",
  "Alfonso, Cavite",
  "Amadeo, Cavite",
  "Mendez (Mendez-Nuñez), Cavite",
  "Tagaytay City, Cavite",
  "Ternate, Cavite",
  "Balayan, Batangas",
  "Batangas City, Batangas",
  "Calatagan, Batangas",
  "Lemery, Batangas",
  "Lipa City, Batangas",
  "Nasugbu Via Aguinaldo, Batangas",
  "Nasugbu Via Kaybiang Tunnel, Batangas",
  "San Juan, Batangas",
  "Santa Cruz, Laguna",
  "Calauag, Quezon",
  "Guinayangan, Quezon",
  "Lucena City, Quezon",
  "San Andres, Quezon",
  "Tagkawayan, Quezon",
  "San Jose, Occidental Mindoro",
  "Roxas, Oriental Mindoro",
  "Legazpi City, Albay",
  "Pio Duran, Albay",
  "Tabaco City, Albay",
  "Tiwi, Albay",
  "Daet, Camarines Norte",
  "Jose Panganiban, Camarines Norte",
  "Paracale, Camarines Norte",
  "Santa Elena, Camarines Norte",
  "Balatan, Camarines Sur",
  "Buhi, Camarines Sur",
  "Iriga City, Camarines Sur",
  "Lagonoy, Camarines Sur",
  "Nabua, Camarines Sur",
  "Naga City, Camarines Sur",
  "San Jose, Camarines Sur",
  "Bagamanoc, Catanduanes",
  "Baras, Catanduanes",
  "Viga, Catanduanes",
  "Virac, Catanduanes",
  "Bulan, Sorsogon",
  "Gubat, Sorsogon",
  "Magallanes, Sorsogon",
  "Matnog, Sorsogon",
  "Pilar, Sorsogon",
  "Sorsogon City, Sorsogon",
  "Masbate City, Masbate",
  "San Jose, Antique",
  "Iloilo City, Iloilo",
  "Tagbilaran City, Bohol",
  "Naval, Biliran",
  "Borongan City, Eastern Samar",
  "Oras, Eastern Samar",
  "Ormoc City, Leyte",
  "Palompon, Leyte",
  "Tacloban City, Leyte",
  "Catarman, Northern Samar",
  "Laoang, Northern Samar",
  "Calbayog City, Samar",
  "Liloan, Southern Leyte",
  "Maasin City, Southern Leyte",
  "Pintuyan, Southern Leyte",
  "Silago, Southern Leyte",
  "Cagayan de Oro City, Misamis Oriental",
  "Davao City, Davao del Sur",
  "Tagum City, Davao del Norte",
  "General Santos, South Cotabato",
  "San Jose, Dinagat Islands",
  "Butuan City, Agusan del Norte",
];

/** Each route's default gate, per PITX's terminal layout:
 *    Gate 2 (Bays 8-11)  - Cavite, Batangas, Laguna, Quezon, Mindoro (IV-A/IV-B)
 *    Gate 4 (Bays 18-23) - Bicol, Visayas, Mindanao (Regions V-XIII)
 *    Gate 5 (Bays 33-36) - North (CAR, Regions I-III)
 * Derived from Sheet5's REGION column, not hand-picked per destination -
 * add a route to ROUTES and this map together to keep them in sync. */
export const ROUTE_GATES = {
  "Baguio City, Benguet": "Gate 5",
  "Lagangilang, Abra": "Gate 5",
  "Banaue, Ifugao": "Gate 5",
  "San Carlos, Pangasinan": "Gate 5",
  "Dagupan, Pangasinan": "Gate 5",
  "Laoag, Ilocos Norte": "Gate 5",
  "Tuguegarao, Cagayan": "Gate 5",
  "Sta.Ana, Cagayan": "Gate 5",
  "Junction Luna (Abulug), Cagayan": "Gate 5",
  "Olongapo City, Zambales": "Gate 5",
  "San Jose, Nueva Ecija": "Gate 5",
  "Balanga, Bataan": "Gate 5",
  "Clark, Pampanga": "Gate 5",
  "Mariveles, Bataan": "Gate 5",
  "Alfonso, Cavite": "Gate 2",
  "Amadeo, Cavite": "Gate 2",
  "Mendez (Mendez-Nuñez), Cavite": "Gate 2",
  "Tagaytay City, Cavite": "Gate 2",
  "Ternate, Cavite": "Gate 2",
  "Balayan, Batangas": "Gate 2",
  "Batangas City, Batangas": "Gate 2",
  "Calatagan, Batangas": "Gate 2",
  "Lemery, Batangas": "Gate 2",
  "Lipa City, Batangas": "Gate 2",
  "Nasugbu Via Aguinaldo, Batangas": "Gate 2",
  "Nasugbu Via Kaybiang Tunnel, Batangas": "Gate 2",
  "San Juan, Batangas": "Gate 2",
  "Santa Cruz, Laguna": "Gate 2",
  "Calauag, Quezon": "Gate 2",
  "Guinayangan, Quezon": "Gate 2",
  "Lucena City, Quezon": "Gate 2",
  "San Andres, Quezon": "Gate 2",
  "Tagkawayan, Quezon": "Gate 2",
  "San Jose, Occidental Mindoro": "Gate 2",
  "Roxas, Oriental Mindoro": "Gate 2",
  "Legazpi City, Albay": "Gate 4",
  "Pio Duran, Albay": "Gate 4",
  "Tabaco City, Albay": "Gate 4",
  "Tiwi, Albay": "Gate 4",
  "Daet, Camarines Norte": "Gate 4",
  "Jose Panganiban, Camarines Norte": "Gate 4",
  "Paracale, Camarines Norte": "Gate 4",
  "Santa Elena, Camarines Norte": "Gate 4",
  "Balatan, Camarines Sur": "Gate 4",
  "Buhi, Camarines Sur": "Gate 4",
  "Iriga City, Camarines Sur": "Gate 4",
  "Lagonoy, Camarines Sur": "Gate 4",
  "Nabua, Camarines Sur": "Gate 4",
  "Naga City, Camarines Sur": "Gate 4",
  "San Jose, Camarines Sur": "Gate 4",
  "Bagamanoc, Catanduanes": "Gate 4",
  "Baras, Catanduanes": "Gate 4",
  "Viga, Catanduanes": "Gate 4",
  "Virac, Catanduanes": "Gate 4",
  "Bulan, Sorsogon": "Gate 4",
  "Gubat, Sorsogon": "Gate 4",
  "Magallanes, Sorsogon": "Gate 4",
  "Matnog, Sorsogon": "Gate 4",
  "Pilar, Sorsogon": "Gate 4",
  "Sorsogon City, Sorsogon": "Gate 4",
  "Masbate City, Masbate": "Gate 4",
  "San Jose, Antique": "Gate 4",
  "Iloilo City, Iloilo": "Gate 4",
  "Tagbilaran City, Bohol": "Gate 4",
  "Naval, Biliran": "Gate 4",
  "Borongan City, Eastern Samar": "Gate 4",
  "Oras, Eastern Samar": "Gate 4",
  "Ormoc City, Leyte": "Gate 4",
  "Palompon, Leyte": "Gate 4",
  "Tacloban City, Leyte": "Gate 4",
  "Catarman, Northern Samar": "Gate 4",
  "Laoang, Northern Samar": "Gate 4",
  "Calbayog City, Samar": "Gate 4",
  "Liloan, Southern Leyte": "Gate 4",
  "Maasin City, Southern Leyte": "Gate 4",
  "Pintuyan, Southern Leyte": "Gate 4",
  "Silago, Southern Leyte": "Gate 4",
  "Cagayan de Oro City, Misamis Oriental": "Gate 4",
  "Davao City, Davao del Sur": "Gate 4",
  "Tagum City, Davao del Norte": "Gate 4",
  "General Santos, South Cotabato": "Gate 4",
  "San Jose, Dinagat Islands": "Gate 4",
  "Butuan City, Agusan del Norte": "Gate 4",
};

/** The gate a booking's route should be assigned into, or null if the
 * route has no configured gate (falls back to showing every bay). */
export function gateForRoute(route) {
  return ROUTE_GATES[route] ?? null;
}

/* ------------------------------------------------------------------ time */

// 48 half-hour slots per day. Slot N covers [N*30, N*30+30) minutes past
// midnight - slot 0 is 12:00-12:30 AM, slot 47 is 11:30 PM-12:00 AM.
export const SLOTS = Array.from({ length: 48 }, (_, i) => i);

function formatClock(totalMinutes) {
  const hour24 = Math.floor(totalMinutes / 60) % 24;
  const minute = totalMinutes % 60;
  const period = hour24 < 12 ? "AM" : "PM";
  const displayHour = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${displayHour}:${String(minute).padStart(2, "0")} ${period}`;
}

export function formatSlot(slot) {
  const start = slot * 30;
  const end = start + 30;
  return `${formatClock(start)} – ${formatClock(end % (24 * 60))}`;
}

/** Bookings must be made/changed at least this far ahead of their slot -
 * mirrors the same rule enforced server-side (see migration 0009). This
 * copy is for immediate UI feedback only; the database is still the real
 * boundary, since a client can always be bypassed. */
export const BOOKING_LEAD_TIME_MS = 4 * 60 * 60 * 1000;

/**
 * The real UTC instant a (bookingDate, slot) pair represents. PITX runs on
 * Philippine time (UTC+8, no DST), so this treats bookingDate/slot as
 * local Manila time and converts to a plain UTC epoch millis for
 * comparison against Date.now() - mirrors public.slot_start_at() in
 * migration 0009.
 */
export function slotStartMillis(bookingDate, slot) {
  const [y, m, d] = bookingDate.split("-").map(Number);
  const totalMinutes = slot * 30;
  const hour = Math.floor(totalMinutes / 60);
  const minute = totalMinutes % 60;
  return Date.UTC(y, m - 1, d, hour, minute) - 8 * 60 * 60 * 1000;
}

export function todayISO() {
  const now = new Date();
  return [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0"),
  ].join("-");
}

// Marks a CPC/OR-CR validity date (or any date) that's already past, or
// within 30 days - same window sync_expiry_notifications() (migration
// 0024) uses for the notification panel, so a highlighted cell always
// matches what triggered a notification. Plain string comparison works
// since both sides are "YYYY-MM-DD".
export function expiryCell(dateStr, escapeHtmlFn) {
  if (!dateStr) return "—";
  const today = todayISO();
  const soon = addDays(today, 30);
  const label = escapeHtmlFn(dateStr);
  if (dateStr < today) return `<span class="expiry-overdue">${label}</span>`;
  if (dateStr <= soon) return `<span class="expiry-soon">${label}</span>`;
  return label;
}

export function addDays(iso, days) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/**
 * Sorts bay names numerically ascending (Bay 1, Bay 2, ... Bay 20) rather
 * than alphabetically (Bay 1, Bay 10, ... Bay 2, Bay 20).
 */
export function compareBayNames(a, b) {
  const numA = Number(a.match(/\d+/)?.[0]);
  const numB = Number(b.match(/\d+/)?.[0]);
  if (!Number.isNaN(numA) && !Number.isNaN(numB) && numA !== numB) {
    return numA - numB;
  }
  return a.localeCompare(b, undefined, { numeric: true });
}

/* ------------------------------------------------------------------ auth */

export async function getProfile() {
  const { data: userData } = await supabase.auth.getUser();
  if (!userData?.user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, username, role, operator_name, created_at")
    .eq("id", userData.user.id)
    .single();

  return profile ?? null;
}

/**
 * Enforces that a signed-in user with the required role is viewing this
 * page. Redirects to login (or to the other role's home) when not, and
 * resolves with the profile when the page may proceed.
 */
export async function guardPage(requiredRole) {
  const profile = await getProfile();

  if (!profile) {
    location.replace("index.html");
    return null;
  }
  if (profile.role !== requiredRole) {
    location.replace(profile.role === "staff" ? "staff.html" : "dashboard.html");
    return null;
  }
  return profile;
}

export async function signOut() {
  await supabase.auth.signOut();
  location.replace("index.html");
}

/* -------------------------------------------------------------------- nav */

const OPERATOR_LINKS = [
  { href: "dashboard.html", label: "My requests" },
  { href: "my-schedule.html", label: "My schedule" },
  { href: "vehicles.html", label: "My vehicles" },
  { href: "operator-profile.html", label: "Operator profile" },
];

const STAFF_LINKS = [
  { href: "staff.html", label: "Pending requests" },
  { href: "vehicle-approvals.html", label: "Vehicle approvals" },
  { href: "vehicles-database.html", label: "Vehicles" },
  { href: "transfer-approvals.html", label: "Transfer approvals" },
  { href: "schedule.html", label: "Schedule" },
  { href: "bays.html", label: "Bays" },
  { href: "operator-profiles.html", label: "Operator profiles" },
  { href: "accounts.html", label: "Accounts" },
];

export function renderNav(profile) {
  const host = document.getElementById("nav");
  if (!host) return;

  const links = profile.role === "staff" ? STAFF_LINKS : OPERATOR_LINKS;
  const here = location.pathname.split("/").pop() || "index.html";

  // Flat children (not nested groups) so the bar collapses to tidy rows
  // rather than three ragged ones when the viewport is narrow.
  host.innerHTML = `
    <div class="nav-inner">
      <div class="nav-brand">
        <img src="assets/pitx-logo.webp" alt="PITX" />
        <span class="unit">Bay Booking</span>
      </div>
      <nav class="nav-links">
        ${links
          .map(
            (l) =>
              `<a href="${l.href}"${
                l.href === here ? ' aria-current="page"' : ""
              }>${escapeHtml(l.label)}</a>`
          )
          .join("")}
      </nav>
      <div class="nav-right">
        <div class="notif-wrap">
          <button type="button" class="notif-bell" id="notif-bell" aria-label="Notifications">
            &#128276;<span class="notif-badge hidden" id="notif-badge">0</span>
          </button>
          <div class="notif-panel hidden" id="notif-panel"></div>
        </div>
        <span class="whoami">${escapeHtml(
          profile.operator_name || profile.username
        )} <span class="role">${escapeHtml(profile.role)}</span></span>
        <button type="button" class="btn-outline" id="sign-out">Sign out</button>
      </div>
    </div>
  `;

  document.getElementById("sign-out").addEventListener("click", signOut);
  initNotifications(profile);
}

/* --------------------------------------------------------- notifications */

const NOTIF_LIMIT = 30;

// Relative "3h ago" / "2d ago" style timestamp - notifications are the
// one place in the app that benefits from this over a plain date/time,
// since "how long has this been waiting" is the actual question.
function relativeTime(iso) {
  const ms = Date.now() - new Date(iso).getTime();
  const mins = Math.round(ms / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  return `${days}d ago`;
}

// Wired into renderNav() so every page gets the bell for free. Not
// awaited by renderNav itself - the nav renders synchronously, this
// fills in the badge/panel once the query comes back.
async function initNotifications(profile) {
  const bell = document.getElementById("notif-bell");
  const panel = document.getElementById("notif-panel");
  const badge = document.getElementById("notif-badge");
  if (!bell || !panel || !badge) return;

  // Best-effort - if this fails (e.g. offline), the panel just shows
  // whatever notifications already exist rather than blocking on it.
  try {
    await supabase.rpc("sync_expiry_notifications");
  } catch {
    /* ignore - see comment above */
  }

  let query = supabase
    .from("notifications")
    .select("id, type, title, body, link, is_read, created_at")
    .order("created_at", { ascending: false })
    .limit(NOTIF_LIMIT);
  query =
    profile.role === "staff"
      ? query.eq("recipient_role", "staff").or(`recipient_id.is.null,recipient_id.eq.${profile.id}`)
      : query.eq("recipient_role", "operator").eq("recipient_id", profile.id);

  const { data } = await query;
  const notifications = data ?? [];
  renderNotifPanel(notifications);

  bell.addEventListener("click", (e) => {
    e.stopPropagation();
    panel.classList.toggle("hidden");
  });
  document.addEventListener("click", (e) => {
    if (!panel.contains(e.target) && e.target !== bell) panel.classList.add("hidden");
  });

  function renderNotifPanel(items) {
    const unreadCount = items.filter((n) => !n.is_read).length;
    badge.textContent = String(unreadCount);
    badge.classList.toggle("hidden", unreadCount === 0);

    panel.innerHTML =
      items.length === 0
        ? `<p class="notif-empty">No notifications yet.</p>`
        : `
          <div class="notif-panel-head">
            <span>Notifications</span>
            ${unreadCount > 0 ? `<button type="button" class="btn-link" id="notif-mark-all">Mark all read</button>` : ""}
          </div>
          <div class="notif-list">
            ${items
              .map(
                (n) => `
                  <button type="button" class="notif-item${n.is_read ? "" : " is-unread"}" data-notif="${escapeHtml(n.id)}" data-link="${escapeHtml(n.link ?? "")}">
                    <span class="notif-title">${escapeHtml(n.title)}</span>
                    ${n.body ? `<span class="notif-body">${escapeHtml(n.body)}</span>` : ""}
                    <span class="notif-time">${relativeTime(n.created_at)}</span>
                  </button>
                `
              )
              .join("")}
          </div>
        `;

    document.getElementById("notif-mark-all")?.addEventListener("click", async (e) => {
      e.stopPropagation();
      const unreadIds = items.filter((n) => !n.is_read).map((n) => n.id);
      await supabase.from("notifications").update({ is_read: true }).in("id", unreadIds);
      items.forEach((n) => (n.is_read = true));
      renderNotifPanel(items);
    });

    panel.querySelectorAll("[data-notif]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.dataset.notif;
        const link = btn.dataset.link;
        await supabase.from("notifications").update({ is_read: true }).eq("id", id);
        if (link) location.href = link;
      });
    });
  }
}

/* ----------------------------------------------------------------- render */

/** Escapes text before it goes anywhere near innerHTML. */
export function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[ch]
  );
}

export function statusBadge(status) {
  return `<span class="badge badge-${escapeHtml(status)}">${escapeHtml(
    status
  )}</span>`;
}

const LTFRB_STATUS_LABELS = {
  active: "Active",
  inactive: "Inactive",
  no_record: "No Record",
  ltfrb_verified: "LTFRB Verified",
};

// Only set on vehicles that came from the masterlist import (migration
// 0021) - null for anything an operator registered directly, which this
// returns as "—" rather than a badge, since it's simply not applicable.
export function ltfrbBadge(ltfrbStatus) {
  if (!ltfrbStatus) return "—";
  const label = LTFRB_STATUS_LABELS[ltfrbStatus] ?? ltfrbStatus;
  return `<span class="badge badge-${escapeHtml(ltfrbStatus)}">${escapeHtml(
    label
  )}</span>`;
}

// Shared by vehicles.html (operator) and vehicles-database.html (staff)
// for the "click a row to see the full card" detail dialog - one builder
// so the field list/order can't drift between the two. `operatorLabel`
// is only passed by the staff page (its own list is already scoped to
// one operator, so there's nothing to show there). Documents are filled
// in afterward by the caller - resolving their signed URLs is async and
// each page already has its own storage-bucket helper for that.
export function vehicleDetailsHtml(v, operatorLabel) {
  const rows = [
    operatorLabel != null ? ["Operator", escapeHtml(operatorLabel)] : null,
    ["Status", statusBadge(v.status)],
    ["LTFRB", ltfrbBadge(v.ltfrb_status)],
    ["Case No.", escapeHtml(v.case_number ?? "—")],
    ["MV File #", escapeHtml(v.mv_file_number ?? "—")],
    ["OR No.", escapeHtml(v.or_number ?? "—")],
    ["CR No.", escapeHtml(v.cr_number ?? "—")],
    ["Chassis No.", escapeHtml(v.chassis_no ?? "—")],
    ["Franchise", escapeHtml(v.franchise ?? "—")],
    ["Sticker No.", escapeHtml(v.sticker_no ?? "—")],
    ["CPC validity", expiryCell(v.cpc_validity, escapeHtml)],
    ["OR/CR validity", expiryCell(v.orcr_validity, escapeHtml)],
    ["Route", escapeHtml(v.route ?? "—")],
    ["Bus No.", escapeHtml(v.bus_number ?? "—")],
    ["Seating capacity", escapeHtml(v.seating_capacity ?? "—")],
    ["Seat", escapeHtml(v.seat_type ?? "—")],
    [
      "Aircon",
      v.aircon === true ? "Aircon" : v.aircon === false ? "Non-aircon" : "—",
    ],
    ["Date granted", escapeHtml(v.date_granted ?? "—")],
    ["Date expiry", escapeHtml(v.date_expiry ?? "—")],
    v.rejection_reason ? ["Note", escapeHtml(v.rejection_reason)] : null,
  ].filter(Boolean);

  return `
    <div class="details-grid">
      ${rows
        .map(
          ([label, value]) =>
            `<div class="detail-item"><span class="detail-label">${escapeHtml(
              label
            )}</span><span class="detail-value">${value}</span></div>`
        )
        .join("")}
      <div class="detail-item detail-documents">
        <span class="detail-label">Documents</span>
        <span class="detail-value" id="details-documents">&hellip;</span>
      </div>
    </div>
  `;
}

export function showMessage(id, text, kind = "error") {
  const el = document.getElementById(id);
  if (!el) return;
  if (!text) {
    el.className = "hidden";
    el.textContent = "";
    return;
  }
  el.className = `msg msg-${kind === "ok" ? "ok" : "error"}`;
  el.textContent = text;
}
