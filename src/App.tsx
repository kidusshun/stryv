import { Activity, Clock, Database, Monitor, ShieldCheck } from 'lucide-react';
import { useEffect, useState } from 'react';

type DatabaseStatus = {
  path: string;
  schemaVersion: number;
};

type TrackerStatus = Awaited<ReturnType<NonNullable<Window['stryv']>['getTrackerStatus']>>;

export function App() {
  const [databaseStatus, setDatabaseStatus] = useState<DatabaseStatus | null>(null);
  const [trackerStatus, setTrackerStatus] = useState<TrackerStatus | null>(null);

  useEffect(() => {
    if (!window.stryv) {
      setDatabaseStatus({ path: 'Electron preload unavailable in browser preview', schemaVersion: 1 });
      setTrackerStatus(null);
      return;
    }

    void window.stryv.getDatabaseStatus().then(setDatabaseStatus);
    void window.stryv.getTrackerStatus().then(setTrackerStatus);
    return window.stryv.onTrackerStatusChanged(setTrackerStatus);
  }, []);

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">S</div>
          <div>
            <h1>Stryv</h1>
          </div>
        </div>

        <nav className="nav-list" aria-label="Primary">
          <a className="nav-item active" href="#today">
            <Activity size={18} />
            Today
          </a>
          <a className="nav-item" href="#data">
            <Database size={18} />
            Local Data
          </a>
        </nav>
      </aside>

      <section className="content" id="today">
        <header className="topbar">
          <div>
            <p className="eyebrow">Phase 2 tracking</p>
            <h2>Dashboard</h2>
          </div>
          <div className="status-pill">
            <ShieldCheck size={17} />
            {trackerStatus?.isRunning ? 'Tracking' : 'Local-first'}
          </div>
        </header>

        <section className="metric-grid" aria-label="Daily metrics">
          <article className="metric-card">
            <Clock size={20} />
            <p>Tracked Today</p>
            <strong>0h 00m</strong>
          </article>
          <article className="metric-card">
            <Activity size={20} />
            <p>Current Session</p>
            <strong>{trackerStatus?.current.appName ?? 'Not tracking yet'}</strong>
          </article>
          <article className="metric-card">
            <Database size={20} />
            <p>Storage</p>
            <strong>{databaseStatus ? `Schema v${databaseStatus.schemaVersion}` : 'Creating...'}</strong>
          </article>
        </section>

        <section className="panel">
          <div>
            <h3>Active Window Tracking</h3>
            <p>
              Stryv is polling the focused Windows app, storing changes as raw samples, and
              maintaining readable sessions in SQLite.
            </p>
          </div>

          <dl className="data-list">
            <div>
              <dt>Window title</dt>
              <dd>{trackerStatus?.current.windowTitle ?? 'Waiting for first sample...'}</dd>
            </div>
            <div>
              <dt>Idle state</dt>
              <dd>{trackerStatus?.current.isIdle ? 'Idle' : 'Active'}</dd>
            </div>
            <div>
              <dt>Poll interval</dt>
              <dd>{trackerStatus ? `${trackerStatus.pollIntervalSeconds}s` : '5s'}</dd>
            </div>
            <div>
              <dt>Executable</dt>
              <dd>{trackerStatus?.current.executablePath ?? 'Unavailable'}</dd>
            </div>
          </dl>
        </section>

        <section className="panel" id="data">
          <div>
            <h3>Local Data Store</h3>
            <p>
              SQLite is initialized on launch with the core tables for samples, sessions,
              apps, categories, rules, summaries, and settings.
            </p>
          </div>

          <dl className="data-list">
            <div>
              <dt>Database file</dt>
              <dd>{databaseStatus?.path ?? 'Preparing local database...'}</dd>
            </div>
            <div>
              <dt>Background behavior</dt>
              <dd>Closing or minimizing hides Stryv to the tray so the app can keep running.</dd>
            </div>
          </dl>
        </section>
      </section>
    </main>
  );
}
