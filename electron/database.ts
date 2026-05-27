import path from 'node:path';
import Database from 'better-sqlite3';
import { app } from 'electron';

const CURRENT_SCHEMA_VERSION = 1;

export type DatabaseStatus = {
  path: string;
  schemaVersion: number;
};

let db: Database.Database | null = null;

export function initializeDatabase(): DatabaseStatus {
  const databasePath = path.join(app.getPath('userData'), 'stryv.sqlite');
  db = new Database(databasePath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  migrate(db);
  seedDefaults(db);

  return {
    path: databasePath,
    schemaVersion: Number(db.pragma('user_version', { simple: true })),
  };
}

export function getDatabaseStatus(): DatabaseStatus {
  if (!db) {
    return initializeDatabase();
  }

  return {
    path: db.name,
    schemaVersion: Number(db.pragma('user_version', { simple: true })),
  };
}

export function closeDatabase(): void {
  db?.close();
  db = null;
}

function migrate(database: Database.Database): void {
  const currentVersion = Number(database.pragma('user_version', { simple: true }));

  if (currentVersion < 1) {
    database.transaction(() => {
      database.exec(`
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color TEXT NOT NULL,
          is_builtin INTEGER NOT NULL DEFAULT 0,
          is_focus_eligible INTEGER NOT NULL DEFAULT 0,
          is_distracting INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS apps (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          executable_path TEXT,
          category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
          track_titles INTEGER NOT NULL DEFAULT 1,
          is_excluded INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(name, executable_path)
        );

        CREATE TABLE IF NOT EXISTS activity_samples (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          app_id INTEGER REFERENCES apps(id) ON DELETE SET NULL,
          sampled_at TEXT NOT NULL,
          app_name TEXT NOT NULL,
          executable_path TEXT,
          window_title TEXT,
          is_idle INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_activity_samples_sampled_at
          ON activity_samples(sampled_at);

        CREATE TABLE IF NOT EXISTS activity_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          app_id INTEGER REFERENCES apps(id) ON DELETE SET NULL,
          category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          app_name TEXT NOT NULL,
          executable_path TEXT,
          window_title TEXT,
          is_idle INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_activity_sessions_started_at
          ON activity_sessions(started_at);

        CREATE TABLE IF NOT EXISTS rules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          match_type TEXT NOT NULL CHECK (match_type IN ('app_name', 'executable_path', 'window_title')),
          pattern TEXT NOT NULL,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS daily_summaries (
          day TEXT PRIMARY KEY,
          active_seconds INTEGER NOT NULL DEFAULT 0,
          idle_seconds INTEGER NOT NULL DEFAULT 0,
          break_seconds INTEGER NOT NULL DEFAULT 0,
          focus_seconds INTEGER NOT NULL DEFAULT 0,
          distraction_seconds INTEGER NOT NULL DEFAULT 0,
          context_switch_count INTEGER NOT NULL DEFAULT 0,
          first_active_at TEXT,
          last_active_at TEXT,
          longest_focus_seconds INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
      `);

      database.pragma(`user_version = ${CURRENT_SCHEMA_VERSION}`);
    })();
  }
}

function seedDefaults(database: Database.Database): void {
  const insertCategory = database.prepare(`
    INSERT OR IGNORE INTO categories
      (name, color, is_builtin, is_focus_eligible, is_distracting)
    VALUES
      (@name, @color, 1, @isFocusEligible, @isDistracting)
  `);

  const categories = [
    ['Deep Work', '#2563eb', 1, 0],
    ['Work', '#0891b2', 1, 0],
    ['Learning', '#16a34a', 1, 0],
    ['Communication', '#7c3aed', 0, 0],
    ['Planning', '#0f766e', 1, 0],
    ['Admin', '#64748b', 0, 0],
    ['Entertainment', '#f97316', 0, 1],
    ['Social', '#db2777', 0, 1],
    ['Distraction', '#dc2626', 0, 1],
    ['Neutral', '#737373', 0, 0],
    ['Idle', '#a3a3a3', 0, 0],
  ];

  const insertSetting = database.prepare(`
    INSERT OR IGNORE INTO settings (key, value)
    VALUES (@key, @value)
  `);

  database.transaction(() => {
    for (const [name, color, isFocusEligible, isDistracting] of categories) {
      insertCategory.run({ name, color, isFocusEligible, isDistracting });
    }

    insertSetting.run({ key: 'tracking.pollIntervalSeconds', value: '5' });
    insertSetting.run({ key: 'tracking.idleThresholdSeconds', value: '300' });
    insertSetting.run({ key: 'window.closeToTray', value: 'true' });
  })();
}
