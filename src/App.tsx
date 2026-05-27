import {
  Activity,
  BarChart3,
  Clock,
  Database,
  Flame,
  ListTree,
  Monitor,
  Moon,
  ShieldCheck,
  Timer,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';

type DatabaseStatus = {
  path: string;
  schemaVersion: number;
};

type TrackerStatus = Awaited<ReturnType<NonNullable<Window['stryv']>['getTrackerStatus']>>;
type TodayDashboard = Awaited<ReturnType<NonNullable<Window['stryv']>['getTodayDashboard']>>;

const previewDashboard: TodayDashboard = {
  day: new Date().toISOString().slice(0, 10),
  totalTrackedSeconds: 0,
  activeSeconds: 0,
  idleSeconds: 0,
  breakSeconds: 0,
  topApps: [],
  timeline: [],
  current: {
    sessionId: null,
    appName: 'Electron preview unavailable',
    windowTitle: null,
    executablePath: null,
    isIdle: false,
    startedAt: null,
    durationSeconds: 0,
  },
};

export function App() {
  const [databaseStatus, setDatabaseStatus] = useState<DatabaseStatus | null>(null);
  const [trackerStatus, setTrackerStatus] = useState<TrackerStatus | null>(null);
  const [today, setToday] = useState<TodayDashboard>(previewDashboard);

  useEffect(() => {
    if (!window.stryv) {
      setDatabaseStatus({ path: 'Electron preload unavailable in browser preview', schemaVersion: 1 });
      return;
    }

    const refreshDashboard = () => {
      void window.stryv?.getTodayDashboard().then(setToday);
    };

    void window.stryv.getDatabaseStatus().then(setDatabaseStatus);
    void window.stryv.getTrackerStatus().then(setTrackerStatus);
    refreshDashboard();

    return window.stryv.onTrackerStatusChanged((status) => {
      setTrackerStatus(status);
      refreshDashboard();
    });
  }, []);

  const topDuration = useMemo(
    () => Math.max(...today.topApps.map((app) => app.durationSeconds), 1),
    [today.topApps],
  );

  return (
    <main className="min-h-screen bg-stryv-bg text-stryv-text">
      <div className="grid min-h-screen grid-cols-1 lg:grid-cols-[252px_minmax(0,1fr)]">
        <aside className="border-b border-stryv-line bg-black px-5 py-5 lg:border-b-0 lg:border-r">
          <div className="flex items-center gap-3">
            <div className="grid h-10 w-10 place-items-center rounded-lg border border-stryv-orange/50 bg-gradient-to-br from-stryv-amber via-stryv-orange to-stryv-ember text-lg font-black text-black shadow-neon">
              S
            </div>
            <div>
              <h1 className="text-lg font-bold leading-none tracking-normal">Stryv</h1>
              <p className="mt-1 text-xs font-medium text-stryv-muted">Personal time OS</p>
            </div>
          </div>

          <nav className="mt-8 grid gap-2" aria-label="Primary">
            <a
              className="flex h-11 items-center gap-3 rounded-lg border border-stryv-orange/35 bg-gradient-to-r from-stryv-ember/20 via-stryv-orange/10 to-transparent px-3 text-sm font-bold text-stryv-orange"
              href="#today"
            >
              <Activity size={18} />
              Today
            </a>
            <a
              className="flex h-11 items-center gap-3 rounded-lg px-3 text-sm font-semibold text-stryv-muted hover:bg-stryv-elevated hover:text-stryv-text"
              href="#timeline"
            >
              <ListTree size={18} />
              Timeline
            </a>
            <a
              className="flex h-11 items-center gap-3 rounded-lg px-3 text-sm font-semibold text-stryv-muted hover:bg-stryv-elevated hover:text-stryv-text"
              href="#data"
            >
              <Database size={18} />
              Local Data
            </a>
          </nav>
        </aside>

        <section className="min-w-0 px-5 py-6 sm:px-7 lg:px-9" id="today">
          <header className="flex flex-col gap-4 border-b border-stryv-line pb-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="bg-gradient-to-r from-stryv-amber via-stryv-orange to-stryv-ember bg-clip-text text-xs font-bold uppercase text-transparent">
                Phase 3 dashboard
              </p>
              <h2 className="mt-1 text-3xl font-bold tracking-normal text-white">Today</h2>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <StatusPill icon={<ShieldCheck size={16} />} label="Local-first" />
              <StatusPill
                icon={<Monitor size={16} />}
                label={trackerStatus?.isRunning ? 'Tracking live' : 'Tracker unavailable'}
                active={Boolean(trackerStatus?.isRunning)}
              />
            </div>
          </header>

          <section className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4" aria-label="Daily metrics">
            <MetricCard icon={<Timer size={20} />} label="Tracked Today" value={formatDuration(today.totalTrackedSeconds)} />
            <MetricCard icon={<Activity size={20} />} label="Active Time" value={formatDuration(today.activeSeconds)} />
            <MetricCard icon={<Moon size={20} />} label="Idle Time" value={formatDuration(today.idleSeconds)} />
            <MetricCard icon={<Clock size={20} />} label="Break Time" value={formatDuration(today.breakSeconds)} />
          </section>

          <section className="mt-6 grid min-w-0 gap-5 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
            <Panel title="Current Session" icon={<Flame size={18} />}>
              <div className="flex min-w-0 flex-col items-start justify-between gap-4 sm:flex-row">
                <div className="min-w-0">
                  <p className="truncate text-2xl font-bold text-white">{today.current.appName}</p>
                  <p className="mt-2 line-clamp-2 text-sm leading-6 text-stryv-muted">
                    {today.current.windowTitle ?? 'Waiting for the next active window sample.'}
                  </p>
                </div>
                <div className="shrink-0 rounded-lg border border-stryv-orange/35 bg-gradient-to-br from-stryv-orange/15 to-stryv-ember/10 px-3 py-2 text-left sm:text-right">
                  <p className="text-[11px] font-bold uppercase text-stryv-orange">Duration</p>
                  <p className="mt-1 whitespace-nowrap text-sm font-bold text-white">
                    {formatDuration(today.current.durationSeconds)}
                  </p>
                </div>
              </div>
              <div className="mt-5 grid gap-3 text-sm">
                <InfoRow label="State" value={today.current.isIdle ? 'Idle' : 'Active'} />
                <InfoRow label="Executable" value={today.current.executablePath ?? 'Unavailable'} />
                <InfoRow label="Database" value={databaseStatus ? `Schema v${databaseStatus.schemaVersion}` : 'Preparing'} />
              </div>
            </Panel>

            <Panel title="Top Apps" icon={<BarChart3 size={18} />}>
              <div className="grid gap-3">
                {today.topApps.length > 0 ? (
                  today.topApps.map((app) => (
                    <div key={app.appName} className="grid gap-2">
                      <div className="flex items-center justify-between gap-3 text-sm">
                        <span className="min-w-0 truncate font-semibold text-white">{app.appName}</span>
                        <span className="whitespace-nowrap text-stryv-muted">{formatDuration(app.durationSeconds)}</span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-stryv-elevated">
                        <div
                          className="h-full rounded-full bg-gradient-to-r from-stryv-ember via-stryv-orange to-stryv-amber shadow-neon"
                          style={{ width: `${Math.max(6, (app.durationSeconds / topDuration) * 100)}%` }}
                        />
                      </div>
                    </div>
                  ))
                ) : (
                  <EmptyState text="No app usage recorded today yet." />
                )}
              </div>
            </Panel>
          </section>

          <Panel title="Timeline" icon={<ListTree size={18} />} className="mt-5" id="timeline">
            <div className="grid gap-2">
              {today.timeline.length > 0 ? (
                today.timeline.map((session) => (
                  <article
                    key={session.id}
                    className="grid gap-3 rounded-lg border border-stryv-line bg-black/40 p-3 sm:grid-cols-[132px_minmax(0,1fr)_96px] sm:items-center"
                  >
                    <div className="text-xs font-bold uppercase text-stryv-orange">
                      {formatTime(session.startedAt)} - {session.endedAt ? formatTime(session.endedAt) : 'Now'}
                    </div>
                    <div className="min-w-0">
                      <div className="flex min-w-0 items-center gap-2">
                        <span
                          className={`h-2 w-2 shrink-0 rounded-full ${
                            session.isIdle
                              ? 'bg-stryv-muted'
                              : 'bg-gradient-to-br from-stryv-amber to-stryv-ember shadow-neon'
                          }`}
                        />
                        <h3 className="truncate text-sm font-bold text-white">{session.appName}</h3>
                      </div>
                      <p className="mt-1 truncate text-sm text-stryv-muted">
                        {session.windowTitle ?? (session.isIdle ? 'Idle block' : 'Untitled window')}
                      </p>
                    </div>
                    <div className="text-left text-sm font-bold text-white sm:text-right">
                      {formatDuration(session.durationSeconds)}
                    </div>
                  </article>
                ))
              ) : (
                <EmptyState text="The timeline will fill in as Stryv records activity changes." />
              )}
            </div>
          </Panel>

          <section className="mt-5 rounded-lg border border-stryv-line bg-stryv-panel p-5" id="data">
            <h3 className="text-base font-bold text-white">Local Data</h3>
            <dl className="mt-4 grid gap-3 text-sm">
              <InfoRow label="Database file" value={databaseStatus?.path ?? 'Preparing local database...'} />
              <InfoRow label="Poll interval" value={trackerStatus ? `${trackerStatus.pollIntervalSeconds}s` : '5s'} />
              <InfoRow label="Idle threshold" value={trackerStatus ? `${trackerStatus.idleThresholdSeconds}s` : '300s'} />
            </dl>
          </section>
        </section>
      </div>
    </main>
  );
}

function MetricCard({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <article className="rounded-lg border border-stryv-line bg-stryv-panel p-5 shadow-[0_18px_40px_rgba(0,0,0,0.28)]">
      <div className="flex items-center justify-between gap-3 text-stryv-orange">
        {icon}
        <span className="h-2 w-2 rounded-full bg-gradient-to-br from-stryv-amber to-stryv-ember shadow-neon" />
      </div>
      <p className="mt-5 text-xs font-bold uppercase text-stryv-muted">{label}</p>
      <strong className="mt-2 block text-2xl font-bold tracking-normal text-white">{value}</strong>
    </article>
  );
}

function Panel({
  children,
  className = '',
  icon,
  id,
  title,
}: {
  children: React.ReactNode;
  className?: string;
  icon: React.ReactNode;
  id?: string;
  title: string;
}) {
  return (
    <section className={`min-w-0 rounded-lg border border-stryv-line bg-stryv-panel p-5 ${className}`} id={id}>
      <div className="mb-5 flex items-center gap-2 text-white">
        <span className="text-stryv-orange">{icon}</span>
        <h3 className="text-base font-bold">{title}</h3>
      </div>
      {children}
    </section>
  );
}

function StatusPill({ active = false, icon, label }: { active?: boolean; icon: React.ReactNode; label: string }) {
  return (
    <div
      className={`inline-flex h-9 items-center gap-2 rounded-full border px-3 text-sm font-bold ${
        active
          ? 'border-stryv-orange/50 bg-stryv-orange/10 text-stryv-orange'
          : 'border-stryv-line bg-stryv-panel text-stryv-muted'
      }`}
    >
      {icon}
      {label}
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid gap-1 border-t border-stryv-line pt-3 sm:grid-cols-[132px_minmax(0,1fr)] sm:gap-4">
      <dt className="text-xs font-bold uppercase text-stryv-muted">{label}</dt>
      <dd className="min-w-0 overflow-wrap-anywhere text-stryv-text [overflow-wrap:anywhere]">{value}</dd>
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="rounded-lg border border-dashed border-stryv-line bg-black/30 p-5 text-sm text-stryv-muted">
      {text}
    </div>
  );
}

function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  if (hours > 0) {
    return `${hours}h ${String(minutes).padStart(2, '0')}m`;
  }

  return `${minutes}m`;
}

function formatTime(iso: string): string {
  return new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}
