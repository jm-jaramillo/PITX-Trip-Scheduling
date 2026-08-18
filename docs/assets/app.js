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
        <span class="whoami">${escapeHtml(
          profile.operator_name || profile.username
        )} <span class="role">${escapeHtml(profile.role)}</span></span>
        <button type="button" class="btn-outline" id="sign-out">Sign out</button>
      </div>
    </div>
  `;

  document.getElementById("sign-out").addEventListener("click", signOut);
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
