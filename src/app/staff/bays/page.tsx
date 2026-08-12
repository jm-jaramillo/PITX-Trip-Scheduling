import { requireRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import NavBar from "@/components/NavBar";
import { addBay, setBayActive } from "@/app/staff/bays/actions";
import type { Bay } from "@/lib/types";

export default async function BaysPage(props: {
  searchParams: Promise<{ error?: string }>;
}) {
  const profile = await requireRole("staff");
  const { error } = await props.searchParams;
  const supabase = await createClient();

  const { data: bays } = await supabase
    .from("bays")
    .select("id, name, is_active, created_at")
    .order("name");

  const bayList = (bays as Bay[] | null) ?? [];
  const activeCount = bayList.filter((b) => b.is_active).length;

  return (
    <div className="min-h-screen bg-slate-50">
      <NavBar profile={profile} />
      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="text-xl font-semibold text-slate-900">Bays</h1>
        <p className="mt-1 text-sm text-slate-500">
          {activeCount} active bay{activeCount === 1 ? "" : "s"} &mdash; this
          is the maximum number of approved bookings allowed per hour.
        </p>

        {error && (
          <p className="mt-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </p>
        )}

        <form
          action={addBay}
          className="mt-6 flex items-end gap-3 rounded-xl border border-slate-200 bg-white p-6"
        >
          <div className="flex flex-1 flex-col gap-1.5">
            <label htmlFor="name" className="text-sm font-medium text-slate-700">
              New bay name
            </label>
            <input
              id="name"
              name="name"
              required
              placeholder="e.g. Bay 21"
              className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
            />
          </div>
          <button
            type="submit"
            className="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
          >
            Add bay
          </button>
        </form>

        <div className="mt-6 overflow-x-auto rounded-md border border-slate-200 bg-white">
          <table className="min-w-full divide-y divide-slate-200 text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Bay
                </th>
                <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Status
                </th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {bayList.map((bay) => (
                <tr key={bay.id}>
                  <td className="whitespace-nowrap px-3 py-2 text-slate-700">
                    {bay.name}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2">
                    <span
                      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        bay.is_active
                          ? "bg-emerald-100 text-emerald-800"
                          : "bg-slate-100 text-slate-600"
                      }`}
                    >
                      {bay.is_active ? "Active" : "Inactive"}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-3 py-2 text-right">
                    <form action={setBayActive}>
                      <input type="hidden" name="bay_id" value={bay.id} />
                      <input
                        type="hidden"
                        name="is_active"
                        value={(!bay.is_active).toString()}
                      />
                      <button
                        type="submit"
                        className="text-xs font-medium text-blue-600 hover:underline"
                      >
                        {bay.is_active ? "Deactivate" : "Activate"}
                      </button>
                    </form>
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
