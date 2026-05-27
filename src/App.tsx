import { Activity, Clock, Database, ShieldCheck } from 'lucide-react';
import { useEffect, useState } from 'react';

type DatabaseStatus = {
  path: string;
  schemaVersion: number;
};

export function App() {
  const [databaseStatus, setDatabaseStatus] = useState<DatabaseStatus | null>(null);

  useEffect(() => {
    if (!window.stryv) {
      setDatabaseStatus({ path: 'Electron preload unavailable in browser preview', schemaVersion: 1 });
      return;
    }

    void window.stryv.getDatabaseStatus().then(setDatabaseStatus);
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
            <p className="eyebrow">Phase 1 foundation</p>
            <h2>Dashboard</h2>
          </div>
          <div className="status-pill">
            <ShieldCheck size={17} />
            Local-first
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
            <strong>Not tracking yet</strong>
          </article>
          <article className="metric-card">
            <Database size={20} />
            <p>Storage</p>
            <strong>{databaseStatus ? `Schema v${databaseStatus.schemaVersion}` : 'Creating...'}</strong>
          </article>
        </section>

        <section className="panel" id="data">
          <div>
            <h3>Local Data Store</h3>
            <p>
              SQLite is initialized on launch with the Phase 1 core tables for samples,
              sessions, apps, categories, rules, summaries, and settings.
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
