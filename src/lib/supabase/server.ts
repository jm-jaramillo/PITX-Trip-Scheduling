import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";

/**
 * Supabase client for use in Server Components, Server Actions, and Route
 * Handlers. Reads/writes the auth session via Next.js cookies.
 *
 * NOTE: calling `.set()` inside a Server Component will throw — cookies can
 * only be written from a Server Action or Route Handler. We swallow that
 * here so Server Components can still call this (e.g. to read the session)
 * without crashing; the Proxy (`src/proxy.ts`) is responsible for keeping
 * the session cookie fresh on every request.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Called from a Server Component - safe to ignore because the
            // Proxy already refreshes the session on the request.
          }
        },
      },
    }
  );
}
