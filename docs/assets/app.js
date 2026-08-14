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
  { href: "vehicles.html", label: "My vehicles" },
  { href: "operator-profile.html", label: "Operator profile" },
];

const STAFF_LINKS = [
  { href: "staff.html", label: "Pending requests" },
  { href: "vehicle-approvals.html", label: "Vehicle approvals" },
  { href: "schedule.html", label: "Schedule" },
  { href: "bays.html", label: "Bays" },
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
