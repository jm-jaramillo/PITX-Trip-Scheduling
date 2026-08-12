import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import NavBar from "@/components/NavBar";
import { approveBooking, rejectBooking } from "@/app/staff/actions";
import { formatHourSlot } from "@/lib/types";
import type { Bay, Booking } from "@/lib/types";

export default async function StaffPendingPage(props: {
  searchParams: Promise<{ error?: string }>;
}) {
  const profile = await requireRole("staff");
  const { error } = await props.searchParams;
  const supabase = await createClient();

  const [{ data: pending }, { data: activeBays }, { data: approvedNow }] =
    await Promise.all([
      supabase
        .from("bookings")
        .select(
          "id, operator_id, operator_name, route, plate_no, booking_date, hour, status, assigned_bay_id, rejection_reason, decided_by, decided_at, created_at"
        )
        .eq("status", "pending")
        .order("booking_date", { ascending: true })
        .order("hour", { ascending: true }),
      supabase.from("bays").select("id, name, is_active, created_at").eq("is_active", true).order("name"),
      supabase
        .from("bookings")
        .select("booking_date, hour, assigned_bay_id")
        .eq("status", "approved"),
    ]);

  const bays = (activeBays as Bay[] | null) ?? [];
  const occupied = new Map<string, Set<number>>();
  for (const row of approvedNow ?? []) {
    const key = `${row.booking_date}|${row.hour}`;
    if (!occupied.has(key)) occupied.set(key, new Set());
    if (row.assigned_bay_id) occupied.get(key)!.add(row.assigned_bay_id);
  }

  const requests = (pending as Booking[] | null) ?? [];

  return (
    <div className="min-h-screen bg-slate-50">
      <NavBar profile={profile} />
      <main className="mx-auto max-w-5xl px-4 py-8">
        <h1 className="text-xl font-semibold text-slate-900">
          Pending requests
        </h1>
        <p className="mt-1 text-sm text-slate-500">
          Approve a request by assigning it a bay, or reject it with an
          optional note back to the operator.
        </p>

        {error && (
          <p className="mt-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </p>
        )}

        {requests.length === 0 ? (
          <p className="mt-6 rounded-md border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500">
            No pending requests right now.
          </p>
        ) : (
          <div className="mt-6 flex flex-col gap-4">
            {requests.map((booking) => {
              const key = `${booking.booking_date}|${booking.hour}`;
              const takenBayIds = occupied.get(key) ?? new Set<number>();
              const availableBays = bays.filter(
                (bay) => !takenBayIds.has(bay.id)
              );

              return (
                <div
                  key={booking.id}
                  className="rounded-xl border border-slate-200 bg-white p-5"
                >
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <div>
                      <p className="text-sm font-semibold text-slate-900">
                        {booking.operator_name} &middot; {booking.plate_no}
                      </p>
                      <p className="text-sm text-slate-600">
                        {booking.route}
                      </p>
                    </div>
                    <p className="text-sm font-medium text-slate-700">
                      {booking.booking_date} &middot;{" "}
                      {formatHourSlot(booking.hour)}
                    </p>
                  </div>

                  <div className="mt-4 flex flex-wrap items-center gap-3 border-t border-slate-100 pt-4">
                    <form action={approveBooking} className="flex items-center gap-2">
                      <input type="hidden" name="booking_id" value={booking.id} />
                      <select
                        name="bay_id"
                        required
                        disabled={availableBays.length === 0}
                        defaultValue=""
                        className="rounded-md border border-slate-300 px-2 py-1.5 text-sm text-black outline-none focus:border-slate-500 disabled:bg-slate-100"
                      >
                        <option value="" disabled>
                          {availableBays.length === 0
                            ? "No bays available"
                            : "Assign bay…"}
                        </option>
                        {availableBays.map((bay) => (
                          <option key={bay.id} value={bay.id}>
                            {bay.name}
                          </option>
                        ))}
                      </select>
                      <button
                        type="submit"
                        disabled={availableBays.length === 0}
                        className="rounded-md bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-50"
                      >
                        Approve
                      </button>
                    </form>

                    <form action={rejectBooking} className="flex items-center gap-2">
                      <input type="hidden" name="booking_id" value={booking.id} />
                      <input
                        name="reason"
                        placeholder="Reason (optional)"
                        className="rounded-md border border-slate-300 px-2 py-1.5 text-sm text-black outline-none focus:border-slate-500"
                      />
                      <button
                        type="submit"
                        className="rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50"
                      >
                        Reject
                      </button>
                    </form>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}
