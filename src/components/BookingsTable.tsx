import { cancelBooking } from "@/app/dashboard/actions";
import StatusBadge from "@/components/StatusBadge";
import { formatHourSlot } from "@/lib/types";
import type { Booking } from "@/lib/types";

export default function BookingsTable({ bookings }: { bookings: Booking[] }) {
  if (bookings.length === 0) {
    return (
      <p className="rounded-md border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500">
        No booking requests yet.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto rounded-md border border-slate-200">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <Th>Date</Th>
            <Th>Hour</Th>
            <Th>Operator</Th>
            <Th>Route</Th>
            <Th>Plate No.</Th>
            <Th>Status</Th>
            <Th>Assigned bay</Th>
            <Th>Note</Th>
            <Th />
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100 bg-white">
          {bookings.map((b) => (
            <tr key={b.id}>
              <Td>{b.booking_date}</Td>
              <Td>{formatHourSlot(b.hour)}</Td>
              <Td>{b.operator_name}</Td>
              <Td>{b.route}</Td>
              <Td>{b.plate_no}</Td>
              <Td>
                <StatusBadge status={b.status} />
              </Td>
              <Td>{b.bays?.name ?? "—"}</Td>
              <Td className="max-w-[16rem] truncate" title={b.rejection_reason ?? ""}>
                {b.rejection_reason ?? "—"}
              </Td>
              <Td>
                {b.status === "pending" && (
                  <form action={cancelBooking.bind(null, b.id)}>
                    <button
                      type="submit"
                      className="text-xs font-medium text-red-600 hover:underline"
                    >
                      Cancel
                    </button>
                  </form>
                )}
              </Td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Th({ children }: { children?: React.ReactNode }) {
  return (
    <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
      {children}
    </th>
  );
}

function Td({
  children,
  className = "",
  title,
}: {
  children?: React.ReactNode;
  className?: string;
  title?: string;
}) {
  return (
    <td className={`whitespace-nowrap px-3 py-2 text-slate-700 ${className}`} title={title}>
      {children}
    </td>
  );
}
