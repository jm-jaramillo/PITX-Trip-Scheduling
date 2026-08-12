import LoginForm from "@/components/LoginForm";

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-50 px-4">
      <div className="w-full max-w-sm rounded-xl border border-slate-200 bg-white p-8 shadow-sm">
        <div className="mb-6 text-center">
          <h1 className="text-lg font-semibold text-slate-900">
            PITX Bus Bay Booking
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Sign in to request or manage bus bay schedules.
          </p>
        </div>
        <LoginForm />
      </div>
    </main>
  );
}
