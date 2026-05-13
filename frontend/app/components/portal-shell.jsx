'use client';

import { Loader2, LogOut, ShieldAlert } from 'lucide-react';

import { roleLabel } from '../lib/roles';

function NavLink({ href, label, active }) {
  return (
    <a
      href={href}
      className={
        active
          ? 'rounded-full border border-cyan-400/30 bg-cyan-500/10 px-3 py-2 text-sm text-cyan-100'
          : 'rounded-full border border-white/10 bg-white/5 px-3 py-2 text-sm text-slate-200 hover:bg-white/10'
      }
    >
      {label}
    </a>
  );
}

export function LoadingScreen({ label = 'Loading secure portal...' }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950 text-white">
      <div className="text-center">
        <Loader2 className="mx-auto h-10 w-10 animate-spin text-cyan-300" />
        <p className="mt-4 text-sm text-slate-400">{label}</p>
      </div>
    </div>
  );
}

export function AccessDeniedScreen({ role, onLogout }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950 px-5 text-white">
      <div className="max-w-xl rounded-[32px] border border-rose-400/20 bg-rose-500/10 p-8">
        <ShieldAlert className="h-10 w-10 text-rose-200" />
        <h1 className="mt-4 text-2xl font-semibold">Access restricted</h1>
        <p className="mt-3 text-sm leading-7 text-rose-100">
          This surface requires a higher role than <strong>{roleLabel(role)}</strong>.
        </p>
        <button
          onClick={onLogout}
          className="mt-6 inline-flex items-center rounded-2xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white hover:bg-white/15"
        >
          Sign out
        </button>
      </div>
    </div>
  );
}

export function PortalShell({
  title,
  subtitle,
  section,
  currentPath = '/',
  session,
  children,
}) {
  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(15,23,42,0.82),_rgba(2,6,23,1)_50%)] text-white">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/80 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-5 py-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-300">
              {section}
            </div>
            <h1 className="mt-2 text-2xl font-semibold tracking-tight">{title}</h1>
            <p className="mt-1 text-sm text-slate-400">{subtitle}</p>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <div className="rounded-full border border-white/10 bg-white/5 px-3 py-2 text-sm text-slate-200">
              {session.user?.full_name || session.user?.email}
              <span className="ml-2 text-slate-400">|</span>
              <span className="ml-2 text-cyan-100">{roleLabel(session.user?.role)}</span>
            </div>
            <button
              onClick={session.logout}
              className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm text-white hover:bg-white/10"
            >
              <LogOut className="h-4 w-4" />
              Logout
            </button>
          </div>
        </div>

        <div className="mx-auto flex max-w-7xl flex-wrap gap-2 px-5 pb-4">
          <NavLink href="/" label="Monitoring" active={currentPath === '/'} />
          <NavLink href="/admin" label="Admin" active={currentPath === '/admin'} />
          <NavLink href="/injection" label="Node Injection" active={currentPath === '/injection'} />
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-5 py-6">{children}</main>
    </div>
  );
}
