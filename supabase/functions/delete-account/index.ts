// Supabase Edge Function: delete an operator or PITX staff account.
//
// Same reasoning as create-account: deleting an auth user needs the
// service_role key, which can never live in the public static site. This
// function runs server-side, reads the key from the
// SUPABASE_SERVICE_ROLE_KEY secret, and only proceeds after verifying the
// *caller* is signed in AND has the 'staff' role.
//
// Deleting the auth user cascades to the profiles row (on delete cascade,
// migration 0001) and from there to that operator's vehicles (on delete
// cascade, migration 0003). It does NOT cascade to bookings.operator_id or
// any decided_by column (no cascade there, by design - so approval history
// isn't silently destroyed) - deleting an account with existing bookings,
// or a staff account that has ever approved/rejected something, fails with
// a generic delete error (Supabase wraps the underlying FK violation)
// rather than orphaning those rows.
//
// Deploy:  supabase functions deploy delete-account
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
//          (injected automatically by Supabase for deployed functions.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.3";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // --- 1. Authenticate the caller and confirm they are PITX staff ---------
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Not signed in." }, 401);
  }

  const asCaller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await asCaller.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Not signed in." }, 401);
  }

  const { data: callerProfile } = await asCaller
    .from("profiles")
    .select("role")
    .eq("id", userData.user.id)
    .single();

  if (callerProfile?.role !== "staff") {
    return json({ error: "Only PITX staff may delete accounts." }, 403);
  }

  // --- 2. Validate the request ---------------------------------------------
  let payload: { user_id?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const targetId = (payload.user_id ?? "").trim();
  if (!targetId) {
    return json({ error: "user_id is required." }, 400);
  }
  if (targetId === userData.user.id) {
    return json({ error: "You can't delete your own account." }, 400);
  }

  // --- 3. Delete with the privileged client --------------------------------
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: targetProfile } = await admin
    .from("profiles")
    .select("username")
    .eq("id", targetId)
    .maybeSingle();

  if (!targetProfile) {
    return json({ error: "Account not found." }, 404);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(targetId);

  if (deleteError) {
    // Supabase's admin API wraps whatever Postgres actually says (typically
    // a foreign-key violation from bookings.operator_id/decided_by, which
    // deliberately don't cascade) into a generic "Database error deleting
    // user" - so any failure here is treated as "still referenced
    // elsewhere," since that's the only way deleteUser fails once the
    // account itself was found.
    return json(
      {
        error: `Can't delete "${targetProfile.username}" - it still has bookings, vehicles, or approval decisions on record. Those need to be reassigned or the history preserved first. (${deleteError.message})`,
      },
      400
    );
  }

  return json({ ok: true, username: targetProfile.username });
});
