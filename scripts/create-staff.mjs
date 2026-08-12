#!/usr/bin/env node
/**
 * Bootstrap the very first PITX staff account (chicken-and-egg fix: normal
 * accounts are created from the /staff/accounts page, but you need one
 * staff login to reach that page in the first place).
 *
 * Usage:
 *   npm run create-staff -- <username> <password> ["Display name"]
 */
import { config } from "dotenv";
import { createClient } from "@supabase/supabase-js";

config({ path: ".env.local" });

const [username, password, displayName] = process.argv.slice(2);

if (!username || !password) {
  console.error(
    'Usage: npm run create-staff -- <username> <password> ["Display name"]'
  );
  process.exit(1);
}
if (password.length < 8) {
  console.error("Password must be at least 8 characters.");
  process.exit(1);
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceRoleKey) {
  console.error(
    "Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local"
  );
  process.exit(1);
}

const admin = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const email = `${username.trim().toLowerCase()}@pitx.local`;

const { data: created, error: createError } = await admin.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
  app_metadata: { role: "staff" },
  user_metadata: { username, operator_name: displayName ?? null },
});

if (createError || !created.user) {
  console.error("Failed to create auth user:", createError?.message);
  process.exit(1);
}

const { error: profileError } = await admin.from("profiles").insert({
  id: created.user.id,
  username,
  role: "staff",
  operator_name: displayName ?? null,
});

if (profileError) {
  console.error("Failed to create profile row:", profileError.message);
  console.error(
    "You may need to delete the orphaned auth user from the Supabase dashboard: " +
      created.user.id
  );
  process.exit(1);
}

console.log(`Staff account "${username}" created. You can now log in.`);
