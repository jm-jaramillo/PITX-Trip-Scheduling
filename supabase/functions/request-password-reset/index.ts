// Supabase Edge Function: an operator (or staff member) who forgot their
// password submits their username here - unauthenticated, since by
// definition they can't sign in to ask any other way. There's no
// self-signup and no real email inboxes behind these accounts (see
// usernameToEmail() in app.js - accounts log in with a username, not a
// real address), so Supabase's built-in email-based password reset
// can't work here either. Instead this raises a staff-broadcast
// notification (same table/mechanism every other "something needs
// staff's attention" notification already uses) so a PITX staff member
// sees it in their existing notification bell and resets the password
// from the Accounts page - already-built functionality (reset-password
// Edge Function), just triggered by the operator instead of staff
// noticing on their own.
//
// Deliberately returns the same generic success message whether or not
// the username exists, to avoid letting this endpoint be used to probe
// which usernames are registered.
//
// Deploy:  supabase functions deploy request-password-reset
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (injected automatically)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.3";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GENERIC_MESSAGE =
  "If that username exists, PITX staff have been notified and will reset your password.";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  let payload: { username?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const username = (payload.username ?? "").trim();
  if (!username) {
    return json({ error: "Username is required." }, 400);
  }

  // No caller auth to check here - this is the one endpoint in the app
  // meant to be reachable while signed out. The service_role client is
  // only used to look up the account and insert a notification, both
  // read/write operations RLS would otherwise block for an anonymous
  // caller (notifications has no client INSERT policy at all - see
  // migration 0024 - by design, every row comes from a SECURITY DEFINER
  // path, and this is one more).
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: targetProfile } = await admin
    .from("profiles")
    .select("id, username, operator_name, role")
    .ilike("username", username)
    .maybeSingle();

  if (targetProfile) {
    const label = targetProfile.operator_name || targetProfile.username;
    await admin.from("notifications").insert({
      recipient_role: "staff",
      recipient_id: null,
      type: "password_reset_requested",
      title: `Password reset requested: ${label}`,
      body: `@${targetProfile.username} (${targetProfile.role}) asked for a password reset from the sign-in page.`,
      // The generic notification click handler (app.js) only appends a
      // query param automatically for relatedTable === "vehicles" - for
      // any other table it navigates to `link` verbatim, so the
      // ?user=<id> accounts.html reads to scroll/highlight the row has
      // to be baked into the link itself here rather than relying on
      // that handler to add it.
      link: `accounts.html?user=${targetProfile.id}`,
      related_table: "profiles",
      related_id: targetProfile.id,
    });
  }

  return json({ ok: true, message: GENERIC_MESSAGE });
});
