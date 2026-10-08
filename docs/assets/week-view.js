// Compact weekly view of confirmed trips, shared by the staff Schedule page
// and the operator My schedule page so the two can't drift apart.
//
// Deliberately sparse: each trip is one small chip showing the bus operator
// and its trip code and nothing else - the full detail (time, destination,
// plate, gate/bay, status) is in the chip's tooltip and on the day view,
// one click away from any day's header. Trips within a day are in
// departure order, grouped under a heading per departure time like the Day view.

import { addDays, escapeHtml, formatSlotStart } from "./app.js";

const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** The Monday on or before an ISO date (weeks run Mon-Sun). */
export function weekStartISO(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const dow = new Date(y, m - 1, d, 12).getDay(); // 0 = Sun
  return addDays(iso, -((dow + 6) % 7));
}

export function weekRangeLabel(startISO) {
  const fmt = (iso) => {
    const [y, m, d] = iso.split("-").map(Number);
    return new Date(y, m - 1, d, 12).toLocaleDateString("en-PH", {
      month: "short",
      day: "numeric",
    });
  };
  const end = addDays(startISO, 6);
  return `${fmt(startISO)} - ${fmt(end)}, ${end.slice(0, 4)}`;
}

/**
 * @param host        element to render into
 * @param weekStart   ISO date of the Monday
 * @param bookings    rows with booking_date, slot, operator_name, trip_number,
 *                    status, and optionally route/plate_no/bays/operator_id
 * @param today       ISO date, to mark today's column
 * @param mineId      operator id to highlight (operator "All trips" view)
 * @param onOpenDay   called with an ISO date when a day header is clicked
 */
// Same grouping as the Day view: one time heading, then every trip departing
// at that time beneath it (rows arrive sorted by slot).
function groupBySlot(rows) {
  const groups = new Map();
  for (const b of rows) {
    if (!groups.has(b.slot)) groups.set(b.slot, []);
    groups.get(b.slot).push(b);
  }
  return [...groups.entries()];
}

function chipHtml(b, mineId) {
  const cancelled = b.status === "cancelled";
  const tip = [
    formatSlotStart(b.slot),
    b.route,
    b.plate_no ? `Plate ${b.plate_no}` : "No plate yet",
    b.bays?.name,
    cancelled ? "Cancelled" : null,
  ]
    .filter(Boolean)
    .join(" · ");
  return `
              <div class="week-trip${cancelled ? " is-cancelled" : ""}${
    mineId && b.operator_id === mineId ? " is-mine" : ""
  }" title="${escapeHtml(tip)}">
                <span class="week-trip-op">${escapeHtml(b.operator_name ?? "Operator")}</span>
                <span class="week-trip-code">${escapeHtml(b.trip_number ?? "—")}</span>
              </div>`;
}

export function renderWeek(host, { weekStart, bookings, today, mineId, onOpenDay }) {
  const byDay = new Map();
  for (let i = 0; i < 7; i++) byDay.set(addDays(weekStart, i), []);
  for (const b of bookings) byDay.get(b.booking_date)?.push(b);

  host.innerHTML = `
    <div class="week-scroll">
      <div class="week-grid">
        ${[...byDay.entries()]
          .map(([date, rows], i) => {
            rows.sort((a, b) => a.slot - b.slot);
            const live = rows.filter((r) => r.status !== "cancelled").length;
            return `
          <section class="week-day${date === today ? " is-today" : ""}">
            <button type="button" class="week-day-head" data-open-day="${date}"
              title="Open ${date} in the day view">
              <span class="week-day-name">${DAY_NAMES[i]}</span>
              <span class="week-day-num">${Number(date.slice(8))}</span>
              <span class="week-day-count">${live} trip${live === 1 ? "" : "s"}</span>
            </button>
            <div class="week-day-body">
              ${
                rows.length === 0
                  ? `<p class="week-empty">No trips</p>`
                  : groupBySlot(rows)
                      .map(
                        ([slot, group]) => `
              <div class="week-time">${escapeHtml(formatSlotStart(slot))}</div>
              ${group.map((b) => chipHtml(b, mineId)).join("")}`
                      )
                      .join("")
              }
            </div>
          </section>`;
          })
          .join("")}
      </div>
    </div>`;

  host.querySelectorAll("[data-open-day]").forEach((btn) => {
    btn.addEventListener("click", () => onOpenDay?.(btn.dataset.openDay));
  });
}
