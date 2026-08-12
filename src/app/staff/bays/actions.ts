"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export async function addBay(formData: FormData) {
  await requireRole("staff");
  const name = String(formData.get("name") ?? "").trim();

  if (!name) {
    redirect("/staff/bays?error=Bay+name+is+required.");
  }

  const supabase = await createClient();
  const { error } = await supabase.from("bays").insert({ name });

  if (error) {
    redirect(`/staff/bays?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/staff/bays");
  revalidatePath("/staff");
  revalidatePath("/staff/schedule");
}

export async function setBayActive(formData: FormData) {
  await requireRole("staff");
  const bayId = Number(formData.get("bay_id"));
  const isActive = String(formData.get("is_active")) === "true";

  const supabase = await createClient();
  await supabase.from("bays").update({ is_active: isActive }).eq("id", bayId);

  revalidatePath("/staff/bays");
  revalidatePath("/staff");
  revalidatePath("/staff/schedule");
}
