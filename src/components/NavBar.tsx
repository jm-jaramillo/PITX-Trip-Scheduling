import Link from "next/link";
import { signOut } from "@/app/actions";
import type { Profile } from "@/lib/types";

const OPERATOR_LINKS = [{ href: "/dashboard", label: "My requests" }];

const STAFF_LINKS = [
  { href: "/staff", label: "Pending requests" },
  { href: "/staff/schedule", label: "Schedule" },
  { href: "/staff/bays", label: "Bays" },
  { href: "/staff/accounts", label: "Accounts" },
];

export default function NavBar({ profile }: { profile: Profile }) {
  const links = profile.role === "staff" ? STAFF_LINKS : OPERATOR_LINKS;

  return (
    <header className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3">
        <div className="flex flex-wrap items-center gap-6">
          <span className="text-sm font-semibold text-slate-900">
            PITX Bus Bay Booking
          </span>
          <nav className="flex gap-4">
            {links.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className="text-sm text-slate-600 hover:text-slate-900"
              >
                {link.label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-3">
          <span className="text-sm text-slate-500">
            {profile.operator_name ?? profile.username}{" "}
            <span className="text-xs uppercase text-slate-400">
              ({profile.role})
            </span>
          </span>
          <form action={signOut}>
            <button
              type="submit"
              className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-700 hover:bg-slate-50"
            >
              Sign out
            </button>
          </form>
        </div>
      </div>
    </header>
  );
}
