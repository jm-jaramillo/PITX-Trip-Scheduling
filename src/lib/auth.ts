import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile, Role } from "@/lib/types";

/**
 * Loads the current authenticated user's profile row. Returns `null` when
 * there is no session. This is the source of truth for role checks inside
 * pages/Server Actions - the Proxy only uses the cheap auth metadata copy
 * for routing.
 */
export async function getCurrentProfile(): Promise<Profile | null> {
  const supabase = await createClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, username, role, operator_name, created_at")
    .eq("id", userData.user.id)
    .single();

  return (profile as Profile) ?? null;
}

/**
 * Server-side guard for pages. Redirects to /login if unauthenticated, or
 * to the other role's home page if the role doesn't match.
 */
export async function requireRole(role: Role): Promise<Profile> {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login");
  if (profile.role !== role) {
    redirect(profile.role === "staff" ? "/staff" : "/dashboard");
  }
  return profile;
}
