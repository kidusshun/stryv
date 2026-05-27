import path from 'node:path';
import Database from 'better-sqlite3';
import { app } from 'electron';

const CURRENT_SCHEMA_VERSION = 1;

export type DatabaseStatus = {
  path: string;
  schemaVersion: number;
};

export type ActivitySampleInput = {
  sampledAt: string;
  appName: string;
  executablePath: string | null;
  windowTitle: string | null;
  isIdle: boolean;
};

export type ActivitySession = {
  id: number;
  app_id: number | null;
  category_id: number | null;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number;
  app_name: string;
  executable_path: string | null;
  window_title: string | null;
  is_idle: number;
};

export type TrackingSettings = {
  pollIntervalSeconds: number;
  idleThresholdSeconds: number;
  sessionMergeGraceSeconds: number;
};

export type CurrentActivity = {
  sessionId: number | null;
  appName: string;
  windowTitle: string | null;
  executablePath: string | null;
  isIdle: boolean;
  startedAt: string | null;
  durationSeconds: number;
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

export function getTrackingSettings(): TrackingSettings {
  const database = requireDatabase();
  const rows = database.prepare('SELECT key, value FROM settings').all() as Array<{
    key: string;
    value: string;
  }>;
  const settings = new Map(rows.map((row) => [row.key, row.value]));

  return {
    pollIntervalSeconds: readPositiveInteger(settings.get('tracking.pollIntervalSeconds'), 5),
    idleThresholdSeconds: readPositiveInteger(settings.get('tracking.idleThresholdSeconds'), 300),
    sessionMergeGraceSeconds: readPositiveInteger(settings.get('tracking.sessionMergeGraceSeconds'), 15),
  };
}

export function recordActivityChange(sample: ActivitySampleInput, forceNewSession = false): ActivitySession {
  const database = requireDatabase();
  const appId = sample.isIdle ? null : upsertApp(database, sample);
  const categoryId = sample.isIdle ? getCategoryIdByName(database, 'Idle') : null;

  return database.transaction(() => {
    database
      .prepare(
        `
          INSERT INTO activity_samples
            (app_id, sampled_at, app_name, executable_path, window_title, is_idle)
          VALUES
            (@appId, @sampledAt, @appName, @executablePath, @windowTitle, @isIdle)
        `,
      )
      .run({
        appId,
        sampledAt: sample.sampledAt,
        appName: sample.appName,
        executablePath: sample.executablePath,
        windowTitle: sample.windowTitle,
        isIdle: Number(sample.isIdle),
      });

    const currentSession = getLatestSession(database);
    if (!forceNewSession && currentSession && isSameActivity(currentSession, sample)) {
      return updateSessionEnd(database, currentSession.id, sample.sampledAt);
    }

    if (!forceNewSession && currentSession) {
      updateSessionEnd(database, currentSession.id, sample.sampledAt);

      const mergeGraceSeconds = getTrackingSettings().sessionMergeGraceSeconds;
      const previousSession = getPreviousSessionBefore(database, currentSession.id);
      const interruptionDuration = secondsBetween(currentSession.started_at, sample.sampledAt);

      if (
        previousSession &&
        interruptionDuration <= mergeGraceSeconds &&
        isSameActivity(previousSession, sample)
      ) {
        database.prepare('DELETE FROM activity_sessions WHERE id = ?').run(currentSession.id);
        database
          .prepare(
            `
              UPDATE activity_sessions
                  SET ended_at = @sampledAt,
                  duration_seconds = MAX(0, CAST((julianday(@sampledAt) - julianday(started_at)) * 86400 AS INTEGER)),
                  updated_at = CURRENT_TIMESTAMP
              WHERE id = @id
            `,
          )
          .run({ id: previousSession.id, sampledAt: sample.sampledAt });

        return getSessionById(database, previousSession.id);
      }
    }

    const result = database
      .prepare(
        `
          INSERT INTO activity_sessions
            (app_id, category_id, started_at, ended_at, duration_seconds, app_name, executable_path, window_title, is_idle)
          VALUES
            (@appId, @categoryId, @startedAt, NULL, 0, @appName, @executablePath, @windowTitle, @isIdle)
        `,
      )
      .run({
        appId,
        categoryId,
        startedAt: sample.sampledAt,
        appName: sample.appName,
        executablePath: sample.executablePath,
        windowTitle: sample.windowTitle,
        isIdle: Number(sample.isIdle),
      });

    return getSessionById(database, Number(result.lastInsertRowid));
  })();
}

export function touchCurrentSession(sampledAt: string): ActivitySession | null {
  const database = requireDatabase();
  const currentSession = getLatestSession(database);
  if (!currentSession) {
    return null;
  }

  return updateSessionEnd(database, currentSession.id, sampledAt);
}

export function stopCurrentSession(endedAt: string): void {
  const database = requireDatabase();
  const currentSession = getLatestSession(database);
  if (currentSession) {
    updateSessionEnd(database, currentSession.id, endedAt);
  }
}

export function getCurrentActivity(): CurrentActivity {
  const database = requireDatabase();
  const currentSession = getLatestSession(database);

  if (!currentSession) {
    return {
      sessionId: null,
      appName: 'Not tracking yet',
      windowTitle: null,
      executablePath: null,
      isIdle: false,
      startedAt: null,
      durationSeconds: 0,
    };
  }

  return {
    sessionId: currentSession.id,
    appName: currentSession.app_name,
    windowTitle: currentSession.window_title,
    executablePath: currentSession.executable_path,
    isIdle: Boolean(currentSession.is_idle),
    startedAt: currentSession.started_at,
    durationSeconds: currentSession.duration_seconds,
  };
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
    insertSetting.run({ key: 'tracking.sessionMergeGraceSeconds', value: '15' });
    insertSetting.run({ key: 'window.closeToTray', value: 'true' });
  })();
}

function requireDatabase(): Database.Database {
  if (!db) {
    initializeDatabase();
  }

  if (!db) {
    throw new Error('Database was not initialized.');
  }

  return db;
}

function upsertApp(database: Database.Database, sample: ActivitySampleInput): number {
  database
    .prepare(
      `
        INSERT INTO apps (name, executable_path)
        VALUES (@appName, @executablePath)
        ON CONFLICT(name, executable_path) DO UPDATE SET
          updated_at = CURRENT_TIMESTAMP
      `,
    )
    .run({ appName: sample.appName, executablePath: sample.executablePath });

  const row = database
    .prepare('SELECT id FROM apps WHERE name = @appName AND executable_path IS @executablePath')
    .get({ appName: sample.appName, executablePath: sample.executablePath }) as { id: number };

  return row.id;
}

function getLatestSession(database: Database.Database): ActivitySession | null {
  return (
    (database
      .prepare('SELECT * FROM activity_sessions ORDER BY started_at DESC, id DESC LIMIT 1')
      .get() as ActivitySession | undefined) ?? null
  );
}

function getPreviousSessionBefore(database: Database.Database, sessionId: number): ActivitySession | null {
  return (
    (database
      .prepare(
        `
          SELECT *
          FROM activity_sessions
          WHERE id <> @sessionId
          ORDER BY ended_at DESC, started_at DESC, id DESC
          LIMIT 1
        `,
      )
      .get({ sessionId }) as ActivitySession | undefined) ?? null
  );
}

function getSessionById(database: Database.Database, id: number): ActivitySession {
  const session = database.prepare('SELECT * FROM activity_sessions WHERE id = ?').get(id) as
    | ActivitySession
    | undefined;

  if (!session) {
    throw new Error(`Activity session ${id} was not found.`);
  }

  return session;
}

function updateSessionEnd(
  database: Database.Database,
  sessionId: number,
  sampledAt: string,
): ActivitySession {
  database
    .prepare(
      `
        UPDATE activity_sessions
        SET ended_at = @sampledAt,
            duration_seconds = MAX(0, CAST((julianday(@sampledAt) - julianday(started_at)) * 86400 AS INTEGER)),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = @sessionId
      `,
    )
    .run({ sessionId, sampledAt });

  return getSessionById(database, sessionId);
}

function getCategoryIdByName(database: Database.Database, name: string): number | null {
  const row = database.prepare('SELECT id FROM categories WHERE name = ?').get(name) as
    | { id: number }
    | undefined;

  return row?.id ?? null;
}

function isSameActivity(session: ActivitySession, sample: ActivitySampleInput): boolean {
  return (
    Boolean(session.is_idle) === sample.isIdle &&
    session.app_name === sample.appName &&
    nullableString(session.executable_path) === nullableString(sample.executablePath) &&
    nullableString(session.window_title) === nullableString(sample.windowTitle)
  );
}

function nullableString(value: string | null | undefined): string | null {
  return value ?? null;
}

function secondsBetween(startIso: string, endIso: string): number {
  return Math.max(0, Math.floor((Date.parse(endIso) - Date.parse(startIso)) / 1000));
}

function readPositiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return Math.floor(parsed);
}
