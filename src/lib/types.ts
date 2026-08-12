export type Role = "operator" | "staff";

export type BookingStatus = "pending" | "approved" | "rejected" | "cancelled";

export type Profile = {
  id: string;
  username: string;
  role: Role;
  operator_name: string | null;
  created_at: string;
};

export type Bay = {
  id: number;
  name: string;
  is_active: boolean;
  created_at: string;
};

export type Booking = {
  id: string;
  operator_id: string;
  operator_name: string;
  route: string;
  plate_no: string;
  booking_date: string; // YYYY-MM-DD
  hour: number; // 0-23
  status: BookingStatus;
  assigned_bay_id: number | null;
  rejection_reason: string | null;
  decided_by: string | null;
  decided_at: string | null;
  created_at: string;
  bays?: Pick<Bay, "id" | "name"> | null;
};

/** All 24 hourly slots, since PITX bay booking runs 24/7. */
export const HOURS = Array.from({ length: 24 }, (_, i) => i);

export function formatHourSlot(hour: number): string {
  const start = formatHour12(hour);
  const end = formatHour12((hour + 1) % 24);
  return `${start} – ${end}`;
}

function formatHour12(hour: number): string {
  const period = hour < 12 ? "AM" : "PM";
  const displayHour = hour % 12 === 0 ? 12 : hour % 12;
  return `${displayHour}:00 ${period}`;
}

export function todayISO(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}
