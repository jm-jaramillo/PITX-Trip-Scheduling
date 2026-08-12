"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

const UNIQUE_VIOLATION = "23505";

export async function approveBooking(formData: FormData) {
  const profile = await requireRole("staff");

  const bookingId = String(formData.get("booking_id") ?? "");
  const bayIdRaw = String(formData.get("bay_id") ?? "");
  const bayId = Number(bayIdRaw);

  if (!bookingId || !bayIdRaw || !Number.isInteger(bayId)) {
    redirect("/staff?error=Please+choose+a+bay+before+approving.");
  }

  const supabase = await createClient();
  const { error, data } = await supabase
    .from("bookings")
    .update({
      status: "approved",
      assigned_bay_id: bayId,
      decided_by: profile.id,
      decided_at: new Date().toISOString(),
    })
    .eq("id", bookingId)
    .eq("status", "pending")
    .select("id");

  if (error) {
    const message =
      error.code === UNIQUE_VIOLATION
        ? "That bay was just taken for this hour by another request. Pick a different bay."
        : error.message;
    redirect(`/staff?error=${encodeURIComponent(message)}`);
  }

  if (!data || data.length === 0) {
    redirect(
      "/staff?error=" +
        encodeURIComponent("That request was already decided on.")
    );
  }

  revalidatePath("/staff");
  revalidatePath("/staff/schedule");
  revalidatePath("/dashboard");
}

export async function rejectBooking(formData: FormData) {
  const profile = await requireRole("staff");

  const bookingId = String(formData.get("booking_id") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();

  if (!bookingId) {
    redirect("/staff?error=Missing+booking.");
  }

  const supabase = await createClient();
  await supabase
    .from("bookings")
    .update({
      status: "rejected",
      rejection_reason: reason || null,
      decided_by: profile.id,
      decided_at: new Date().toISOString(),
    })
    .eq("id", bookingId)
    .eq("status", "pending");

  revalidatePath("/staff");
  revalidatePath("/staff/schedule");
  revalidatePath("/dashboard");
}
