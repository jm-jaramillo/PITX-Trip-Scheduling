#!/usr/bin/env node
/**
 * Create an operator account directly, bypassing the in-app Accounts page.
 * Needed until the create-account Edge Function is deployed (see README) -
 * staff can still create operator logins from the Accounts page once that
 * ships; this is the same operation run from the command line in the
 * meantime, using the same service-role privileges.
 *
 * Usage:
 *   node scripts/create-operator.mjs <username> <password> ["Operator name"]
 */
import { config } from "dotenv";
import { createClient } from "@supabase/supabase-js";

config({ path: ".env.local" });

const [username, password, operatorName] = process.argv.slice(2);

if (!username || !password) {
  console.error(
    'Usage: node scripts/create-operator.mjs <username> <password> ["Operator name"]'
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
  app_metadata: { role: "operator" },
  user_metadata: { username, operator_name: operatorName ?? null },
});

if (createError || !created.user) {
  console.error("Failed to create auth user:", createError?.message);
  process.exit(1);
}

const { error: profileError } = await admin.from("profiles").insert({
  id: created.user.id,
  username,
  role: "operator",
  operator_name: operatorName ?? null,
});

if (profileError) {
  console.error("Failed to create profile row:", profileError.message);
  console.error(
    "You may need to delete the orphaned auth user from the Supabase dashboard: " +
      created.user.id
  );
  process.exit(1);
}

console.log(`Operator account "${username}" created. You can now log in.`);
