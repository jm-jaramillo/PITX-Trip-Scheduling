"use client";

import { useActionState, useEffect, useRef } from "react";
import { createBooking, type BookingFormState } from "@/app/dashboard/actions";
import { HOURS, formatHourSlot, todayISO } from "@/lib/types";

const initialState: BookingFormState = { error: null, success: false };

export default function NewBookingForm({
  defaultOperatorName,
}: {
  defaultOperatorName: string;
}) {
  const [state, formAction, pending] = useActionState(
    createBooking,
    initialState
  );
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.success) formRef.current?.reset();
  }, [state]);

  return (
    <form
      ref={formRef}
      action={formAction}
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5"
    >
      <div className="flex flex-col gap-1.5">
        <label htmlFor="operator_name" className="text-sm font-medium text-slate-700">
          Operator
        </label>
        <input
          id="operator_name"
          name="operator_name"
          required
          defaultValue={defaultOperatorName}
          className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="route" className="text-sm font-medium text-slate-700">
          Route
        </label>
        <input
          id="route"
          name="route"
          required
          placeholder="e.g. PITX - Batangas"
          className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="plate_no" className="text-sm font-medium text-slate-700">
          Plate No.
        </label>
        <input
          id="plate_no"
          name="plate_no"
          required
          placeholder="e.g. ABC 1234"
          className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="booking_date" className="text-sm font-medium text-slate-700">
          Date
        </label>
        <input
          id="booking_date"
          name="booking_date"
          type="date"
          required
          min={todayISO()}
          defaultValue={todayISO()}
          className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="hour" className="text-sm font-medium text-slate-700">
          Hour slot
        </label>
        <select
          id="hour"
          name="hour"
          required
          defaultValue=""
          className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
        >
          <option value="" disabled>
            Select an hour
          </option>
          {HOURS.map((hour) => (
            <option key={hour} value={hour}>
              {formatHourSlot(hour)}
            </option>
          ))}
        </select>
      </div>

      <div className="sm:col-span-2 lg:col-span-5">
        {state.error && (
          <p className="mb-2 text-sm text-red-600">{state.error}</p>
        )}
        {state.success && (
          <p className="mb-2 text-sm text-emerald-600">
            Request submitted. PITX staff will review it shortly.
          </p>
        )}
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-60"
        >
          {pending ? "Submitting…" : "Request slot"}
        </button>
      </div>
    </form>
  );
}
