import Link from "next/link";
import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import NavBar from "@/components/NavBar";
import StatusBadge from "@/components/StatusBadge";
import { HOURS, formatHourSlot, todayISO } from "@/lib/types";
import type { Bay, Booking } from "@/lib/types";

function addDays(iso: string, days: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + days));
  return date.toISOString().slice(0, 10);
}

export default async function SchedulePage(props: {
  searchParams: Promise<{ date?: string }>;
}) {
  const profile = await requireRole("staff");
  const { date: dateParam } = await props.searchParams;
  const date = dateParam && /^\d{4}-\d{2}-\d{2}$/.test(dateParam) ? dateParam : todayISO();

  const supabase = await createClient();
  const [{ data: activeBays }, { data: dayBookings }] = await Promise.all([
    supabase.from("bays").select("id, name, is_active, created_at").eq("is_active", true).order("name"),
    supabase
      .from("bookings")
      .select(
        "id, operator_id, operator_name, route, plate_no, booking_date, hour, status, assigned_bay_id, rejection_reason, decided_by, decided_at, created_at, bays ( id, name )"
      )
      .eq("booking_date", date)
      .in("status", ["pending", "approved"])
      .order("hour", { ascending: true }),
  ]);

  const bays = (activeBays as Bay[] | null) ?? [];
  const totalBays = bays.length;
  const bookings = (dayBookings as Booking[] | null) ?? [];

  const byHour = new Map<number, Booking[]>();
  for (const booking of bookings) {
    if (!byHour.has(booking.hour)) byHour.set(booking.hour, []);
    byHour.get(booking.hour)!.push(booking);
  }

  return (
    <div className="min-h-screen bg-slate-50">
      <NavBar profile={profile} />
      <main className="mx-auto max-w-5xl px-4 py-8">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-xl font-semibold text-slate-900">Schedule</h1>
          <div className="flex items-center gap-2 text-sm">
            <Link
              href={`/staff/schedule?date=${addDays(date, -1)}`}
              className="rounded-md border border-slate-300 px-3 py-1.5 text-slate-700 hover:bg-slate-50"
            >
              ← Prev day
            </Link>
            <form action="/staff/schedule" className="flex items-center gap-2">
              <input
                type="date"
                defaultValue={date}
                name="date"
                className="rounded-md border border-slate-300 px-3 py-1.5 text-slate-700"
              />
              <button
                type="submit"
                className="rounded-md border border-slate-300 px-3 py-1.5 text-slate-700 hover:bg-slate-50"
              >
                Go
              </button>
            </form>
            <Link
              href={`/staff/schedule?date=${addDays(date, 1)}`}
              className="rounded-md border border-slate-300 px-3 py-1.5 text-slate-700 hover:bg-slate-50"
            >
              Next day →
            </Link>
          </div>
        </div>
        <p className="mt-1 text-sm text-slate-500">
          {totalBays} active bay{totalBays === 1 ? "" : "s"} total. Each hour
          can hold at most that many approved buses.
        </p>

        <div className="mt-6 overflow-x-auto rounded-md border border-slate-200 bg-white">
          <table className="min-w-full divide-y divide-slate-200 text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Hour
                </th>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Approved / capacity
                </th>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Bookings
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {HOURS.map((hour) => {
                const hourBookings = byHour.get(hour) ?? [];
                const approvedCount = hourBookings.filter(
                  (b) => b.status === "approved"
                ).length;
                return (
                  <tr key={hour}>
                    <td className="whitespace-nowrap px-3 py-2 font-medium text-slate-700">
                      {formatHourSlot(hour)}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2 text-slate-600">
                      {approvedCount} / {totalBays}
                    </td>
                    <td className="px-3 py-2">
                      {hourBookings.length === 0 ? (
                        <span className="text-slate-400">—</span>
                      ) : (
                        <ul className="flex flex-col gap-1">
                          {hourBookings.map((b) => (
                            <li key={b.id} className="flex items-center gap-2">
                              <StatusBadge status={b.status} />
                              <span className="text-slate-700">
                                {b.operator_name} &middot; {b.plate_no} &middot;{" "}
                                {b.route}
                              </span>
                              {b.bays?.name && (
                                <span className="text-xs text-slate-500">
                                  ({b.bays.name})
                                </span>
                              )}
                            </li>
                          ))}
                        </ul>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
