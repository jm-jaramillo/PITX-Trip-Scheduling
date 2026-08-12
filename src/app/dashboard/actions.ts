"use server";

import { revalidatePath } from "next/cache";
import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { todayISO } from "@/lib/types";

export type BookingFormState = {
  error: string | null;
  success: boolean;
};

export async function createBooking(
  _prevState: BookingFormState,
  formData: FormData
): Promise<BookingFormState> {
  const profile = await requireRole("operator");

  const operatorName = String(formData.get("operator_name") ?? "").trim();
  const route = String(formData.get("route") ?? "").trim();
  const plateNo = String(formData.get("plate_no") ?? "").trim();
  const bookingDate = String(formData.get("booking_date") ?? "").trim();
  const hourRaw = String(formData.get("hour") ?? "").trim();
  const hour = Number(hourRaw);

  if (!operatorName || !route || !plateNo || !bookingDate || !hourRaw) {
    return { error: "Please fill in every field.", success: false };
  }
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
    return { error: "Please pick a valid hour slot.", success: false };
  }
  if (bookingDate < todayISO()) {
    return { error: "Booking date can't be in the past.", success: false };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("bookings").insert({
    operator_id: profile.id,
    operator_name: operatorName,
    route,
    plate_no: plateNo,
    booking_date: bookingDate,
    hour,
    status: "pending",
  });

  if (error) {
    return { error: error.message, success: false };
  }

  revalidatePath("/dashboard");
  return { error: null, success: true };
}

export async function cancelBooking(bookingId: string) {
  const profile = await requireRole("operator");
  const supabase = await createClient();

  await supabase
    .from("bookings")
    .update({ status: "cancelled" })
    .eq("id", bookingId)
    .eq("operator_id", profile.id)
    .eq("status", "pending");

  revalidatePath("/dashboard");
}
