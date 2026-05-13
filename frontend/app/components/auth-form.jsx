'use client';

import { useState } from 'react';

import { ROLE_LABELS } from '../lib/roles';

export function AuthForm({
  title,
  subtitle,
  authError,
  onLogin,
  helper,
  accent = 'cyan',
}) {
  const [email, setEmail] = useState('admin@alghurair.local');
  const [password, setPassword] = useState('Admin@12345');
  const [submitting, setSubmitting] = useState(false);
  const [localError, setLocalError] = useState('');

  const accentStyles = {
    cyan: 'border-cyan-400/20 bg-cyan-500/10 text-cyan-100',
    amber: 'border-amber-400/20 bg-amber-500/10 text-amber-100',
    rose: 'border-rose-400/20 bg-rose-500/10 text-rose-100',
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    setLocalError('');
    setSubmitting(true);

    try {
      await onLogin({ email, password });
    } catch (error) {
      setLocalError(error.message || 'Login failed');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(17,24,39,0.8),_rgba(2,6,23,1)_55%)] px-5 py-10 text-white">
      <div className="mx-auto flex min-h-[80vh] max-w-5xl items-center justify-center">
        <div className="grid w-full gap-6 lg:grid-cols-[1.15fr_0.85fr]">
          <div className="rounded-[32px] border border-white/10 bg-white/5 p-8 shadow-2xl shadow-black/30">
            <div className={`inline-flex rounded-full border px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.2em] ${accentStyles[accent] || accentStyles.cyan}`}>
              Industrial Control Platform
            </div>
            <h1 className="mt-5 text-4xl font-semibold tracking-tight">{title}</h1>
            <p className="mt-4 max-w-2xl text-sm leading-7 text-slate-300">{subtitle}</p>
            {helper ? <p className="mt-5 text-sm text-slate-400">{helper}</p> : null}
          </div>

          <form
            onSubmit={handleSubmit}
            className="rounded-[32px] border border-white/10 bg-slate-950/85 p-8 shadow-2xl shadow-black/40"
          >
            <h2 className="text-2xl font-semibold tracking-tight">Sign In</h2>
            <p className="mt-2 text-sm text-slate-400">
              Seeded admin login: <span className="text-slate-200">admin@alghurair.local</span>
            </p>

            <div className="mt-6 space-y-4">
              <label className="block">
                <span className="mb-2 block text-sm text-slate-300">Email</span>
                <input
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
                />
              </label>

              <label className="block">
                <span className="mb-2 block text-sm text-slate-300">Password</span>
                <input
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
                />
              </label>
            </div>

            {authError || localError ? (
              <div className="mt-5 rounded-2xl border border-rose-400/20 bg-rose-500/10 px-4 py-3 text-sm text-rose-100">
                {localError || authError}
              </div>
            ) : null}

            <button
              type="submit"
              disabled={submitting}
              className="mt-6 inline-flex w-full items-center justify-center rounded-2xl bg-cyan-400 px-4 py-3 font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:bg-cyan-400/60"
            >
              {submitting ? 'Signing In...' : 'Sign In'}
            </button>

            <div className="mt-6 rounded-2xl border border-white/10 bg-white/5 p-4 text-xs leading-6 text-slate-400">
              Role labels:
              <div className="mt-2 flex flex-wrap gap-2">
                {Object.entries(ROLE_LABELS).map(([key, value]) => (
                  <span
                    key={key}
                    className="rounded-full border border-white/10 px-2.5 py-1 text-[11px] uppercase tracking-[0.14em] text-slate-200"
                  >
                    {value}
                  </span>
                ))}
              </div>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
