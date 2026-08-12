import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PUBLIC_PATHS = ["/login"];

/**
 * Runs on every request (except static assets, see `config.matcher` below).
 * Keeps the Supabase auth session cookie fresh, and redirects based on
 * whether the visitor is signed in and what role they hold.
 *
 * Role here comes from the Supabase Auth user's `app_metadata.role`, which
 * is only ever set server-side via the service-role Admin API (see
 * `src/lib/supabase/admin.ts`) - a signed-in user cannot alter it
 * themselves. This keeps routing cheap (no DB round trip). Pages and
 * Server Actions still re-check the authoritative `profiles` row via
 * `requireRole()` / RLS before doing anything sensitive.
 *
 * Cookie handling follows Supabase's reference SSR pattern: `response`
 * must be rebuilt from the (possibly cookie-mutated) `request` object
 * inside `setAll`, and any redirect response must copy `response`'s
 * cookies onto itself - otherwise a refreshed session token never makes
 * it to the browser and the visitor gets silently signed out.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const { data: userData } = await supabase.auth.getUser();
  const user = userData.user;
  const role = (user?.app_metadata as { role?: string } | undefined)?.role;
  const pathname = request.nextUrl.pathname;
  const isPublicPath = PUBLIC_PATHS.includes(pathname);

  function redirectTo(pathnameTarget: string) {
    const url = request.nextUrl.clone();
    url.pathname = pathnameTarget;
    const redirectResponse = NextResponse.redirect(url);
    // Carry over the (possibly refreshed) session cookies.
    response.cookies.getAll().forEach((cookie) => {
      redirectResponse.cookies.set(cookie);
    });
    return redirectResponse;
  }

  if (!user && !isPublicPath) return redirectTo("/login");
  if (user && isPublicPath) {
    return redirectTo(role === "staff" ? "/staff" : "/dashboard");
  }
  if (user && role !== "staff" && pathname.startsWith("/staff")) {
    return redirectTo("/dashboard");
  }
  if (user && role === "staff" && pathname.startsWith("/dashboard")) {
    return redirectTo("/staff");
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
