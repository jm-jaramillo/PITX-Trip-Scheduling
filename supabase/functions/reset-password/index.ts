// Supabase Edge Function: reset an operator or PITX staff account's
// password to a new value staff provides.
//
// Same reasoning as create-account/delete-account: changing another
// user's password needs the service_role key, which can never live in
// the public static site. This function runs server-side, reads the key
// from the SUPABASE_SERVICE_ROLE_KEY secret, and only proceeds after
// verifying the *caller* is signed in AND has the 'staff' role.
//
// Deploy:  supabase functions deploy reset-password
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
    return json({ error: "Only PITX staff may reset passwords." }, 403);
  }

  // --- 2. Validate the request ---------------------------------------------
  let payload: { user_id?: string; new_password?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const targetId = (payload.user_id ?? "").trim();
  const newPassword = payload.new_password ?? "";
  if (!targetId) {
    return json({ error: "user_id is required." }, 400);
  }
  if (newPassword.length < 8) {
    return json({ error: "New password must be at least 8 characters." }, 400);
  }

  // --- 3. Reset with the privileged client ---------------------------------
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

  const { error: updateError } = await admin.auth.admin.updateUserById(targetId, {
    password: newPassword,
  });

  if (updateError) {
    return json({ error: updateError.message }, 400);
  }

  return json({ ok: true, username: targetProfile.username });
});
