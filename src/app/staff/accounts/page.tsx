import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import NavBar from "@/components/NavBar";
import { createAccount } from "@/app/staff/accounts/actions";
import type { Profile } from "@/lib/types";

export default async function AccountsPage(props: {
  searchParams: Promise<{ error?: string; ok?: string }>;
}) {
  const profile = await requireRole("staff");
  const { error, ok } = await props.searchParams;
  const supabase = await createClient();

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, username, role, operator_name, created_at")
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-slate-50">
      <NavBar profile={profile} />
      <main className="mx-auto max-w-5xl px-4 py-8">
        <h1 className="text-xl font-semibold text-slate-900">Accounts</h1>
        <p className="mt-1 text-sm text-slate-500">
          Create login accounts for bus operators and other PITX staff.
          There is no self-signup.
        </p>

        {error && (
          <p className="mt-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </p>
        )}
        {ok && (
          <p className="mt-4 rounded-md bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
            {ok}
          </p>
        )}

        <form
          action={createAccount}
          className="mt-6 grid grid-cols-1 gap-4 rounded-xl border border-slate-200 bg-white p-6 sm:grid-cols-2"
        >
          <div className="flex flex-col gap-1.5">
            <label htmlFor="username" className="text-sm font-medium text-slate-700">
              Username
            </label>
            <input
              id="username"
              name="username"
              required
              className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
            />
          </div>

          <div className="flex flex-col gap-1.5">
            <label htmlFor="password" className="text-sm font-medium text-slate-700">
              Temporary password
            </label>
            <input
              id="password"
              name="password"
              type="text"
              minLength={8}
              required
              className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
            />
          </div>

          <div className="flex flex-col gap-1.5">
            <label htmlFor="role" className="text-sm font-medium text-slate-700">
              Role
            </label>
            <select
              id="role"
              name="role"
              required
              defaultValue="operator"
              className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
            >
              <option value="operator">Bus operator</option>
              <option value="staff">PITX staff</option>
            </select>
          </div>

          <div className="flex flex-col gap-1.5">
            <label htmlFor="operator_name" className="text-sm font-medium text-slate-700">
              Operator / display name (optional)
            </label>
            <input
              id="operator_name"
              name="operator_name"
              placeholder="e.g. Genesis Transport"
              className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
            />
          </div>

          <div className="sm:col-span-2">
            <button
              type="submit"
              className="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
            >
              Create account
            </button>
          </div>
        </form>

        <h2 className="mt-10 text-lg font-semibold text-slate-900">
          Existing accounts
        </h2>
        <div className="mt-4 overflow-x-auto rounded-md border border-slate-200 bg-white">
          <table className="min-w-full divide-y divide-slate-200 text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Username
                </th>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Role
                </th>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Operator name
                </th>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Created
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {((profiles as Profile[] | null) ?? []).map((p) => (
                <tr key={p.id}>
                  <td className="whitespace-nowrap px-3 py-2 text-slate-700">
                    {p.username}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 capitalize text-slate-700">
                    {p.role}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 text-slate-700">
                    {p.operator_name ?? "—"}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 text-slate-500">
                    {new Date(p.created_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
