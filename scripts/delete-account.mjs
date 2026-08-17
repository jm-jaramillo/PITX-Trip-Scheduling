#!/usr/bin/env node
/**
 * Delete an operator or staff account directly, bypassing the Accounts
 * page. Needed until the delete-account Edge Function is deployed - staff
 * can delete accounts from the Accounts page once that ships; this is the
 * same operation run from the command line in the meantime.
 *
 * Deleting the auth user cascades to the profiles row and from there to
 * that operator's vehicles. It does NOT cascade to bookings.operator_id or
 * any decided_by column (no cascade there, by design), so deleting an
 * account that still has bookings or approval decisions on record fails
 * fails (Supabase wraps the underlying FK violation in a generic error)
 * rather than orphaning those rows - that's
 * intentional, not a bug to work around.
 *
 * Usage:
 *   node scripts/delete-account.mjs <username>
 */
import { config } from "dotenv";
import { createClient } from "@supabase/supabase-js";

config({ path: ".env.local" });

const [username] = process.argv.slice(2);

if (!username) {
  console.error("Usage: node scripts/delete-account.mjs <username>");
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

const { data: profile, error: lookupError } = await admin
  .from("profiles")
  .select("id, username")
  .ilike("username", username)
  .maybeSingle();

if (lookupError) {
  console.error("Lookup failed:", lookupError.message);
  process.exit(1);
}
if (!profile) {
  console.error(`No account found with username "${username}".`);
  process.exit(1);
}

const { error: deleteError } = await admin.auth.admin.deleteUser(profile.id);

if (deleteError) {
  // Supabase's admin API wraps whatever Postgres actually says (typically
  // a foreign-key violation from bookings.operator_id/decided_by, which
  // deliberately don't cascade) into a generic "Database error deleting
  // user" - so rather than pattern-match a message we don't control, any
  // failure here is treated as "still referenced elsewhere," since that's
  // the only way deleteUser fails once the account itself was found.
  console.error(
    `Can't delete "${profile.username}" - it still has bookings, vehicles, ` +
      `or approval decisions on record. Those need to be reassigned or the ` +
      `history preserved first. (${deleteError.message})`
  );
  process.exit(1);
}

console.log(`Account "${profile.username}" deleted.`);
