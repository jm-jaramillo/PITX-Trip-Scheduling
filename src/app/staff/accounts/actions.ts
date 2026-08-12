"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isValidUsername, usernameToEmail } from "@/lib/username";
import type { Role } from "@/lib/types";

function fail(message: string): never {
  redirect(`/staff/accounts?error=${encodeURIComponent(message)}`);
}

export async function createAccount(formData: FormData) {
  await requireRole("staff");

  const username = String(formData.get("username") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const roleRaw = String(formData.get("role") ?? "");
  const operatorName = String(formData.get("operator_name") ?? "").trim();

  if (!isValidUsername(username)) {
    fail("Username must be 3-32 characters: letters, numbers, dot, dash, underscore.");
  }
  if (password.length < 8) {
    fail("Password must be at least 8 characters.");
  }
  if (roleRaw !== "operator" && roleRaw !== "staff") {
    fail("Please choose a role.");
  }
  const role = roleRaw as Role;

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("profiles")
    .select("id")
    .ilike("username", username)
    .maybeSingle();
  if (existing) {
    fail("That username is already taken.");
  }

  const admin = createAdminClient();
  const { data: created, error: createError } =
    await admin.auth.admin.createUser({
      email: usernameToEmail(username),
      password,
      email_confirm: true,
      app_metadata: { role },
      user_metadata: { username, operator_name: operatorName || null },
    });

  if (createError || !created.user) {
    fail(createError?.message ?? "Could not create account.");
  }

  const { error: profileError } = await admin.from("profiles").insert({
    id: created.user.id,
    username,
    role,
    operator_name: operatorName || null,
  });

  if (profileError) {
    // Roll back the auth user so we don't end up with an orphaned login.
    await admin.auth.admin.deleteUser(created.user.id);
    fail(profileError.message);
  }

  revalidatePath("/staff/accounts");
  redirect(
    `/staff/accounts?ok=${encodeURIComponent(`Account "${username}" created.`)}`
  );
}
