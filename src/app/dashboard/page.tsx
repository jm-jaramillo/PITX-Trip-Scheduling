import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import NavBar from "@/components/NavBar";
import NewBookingForm from "@/components/NewBookingForm";
import BookingsTable from "@/components/BookingsTable";
import type { Booking } from "@/lib/types";

export default async function DashboardPage() {
  const profile = await requireRole("operator");
  const supabase = await createClient();

  const { data: bookings } = await supabase
    .from("bookings")
    .select(
      "id, operator_id, operator_name, route, plate_no, booking_date, hour, status, assigned_bay_id, rejection_reason, decided_by, decided_at, created_at, bays ( id, name )"
    )
    .eq("operator_id", profile.id)
    .order("booking_date", { ascending: false })
    .order("hour", { ascending: false });

  return (
    <div className="min-h-screen bg-slate-50">
      <NavBar profile={profile} />
      <main className="mx-auto max-w-5xl px-4 py-8">
        <h1 className="text-xl font-semibold text-slate-900">
          Request a bus bay slot
        </h1>
        <p className="mt-1 text-sm text-slate-500">
          Pick an hourly slot. PITX staff will review your request and
          assign a bay once approved.
        </p>

        <div className="mt-6 rounded-xl border border-slate-200 bg-white p-6">
          <NewBookingForm defaultOperatorName={profile.operator_name ?? ""} />
        </div>

        <h2 className="mt-10 text-lg font-semibold text-slate-900">
          My requests
        </h2>
        <div className="mt-4">
          <BookingsTable bookings={(bookings as Booking[] | null) ?? []} />
        </div>
      </main>
    </div>
  );
}
