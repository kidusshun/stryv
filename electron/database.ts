import path from 'node:path';
import Database from 'better-sqlite3';
import { app } from 'electron';

const CURRENT_SCHEMA_VERSION = 2;

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

export type Category = {
  id: number;
  name: string;
  color: string;
  is_builtin: number;
  is_focus: number;
  is_work: number;
  is_break: number;
  is_idle: number;
  is_distracting: number;
  idle_detection_exempt: number;
  distraction_blocker_enabled: number;
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
  categoryName: string | null;
};

export type IntentSession = {
  id: number;
  name: string;
  category_id: number;
  category_name: string;
  started_at: string;
  ends_at: string;
  status: 'active' | 'completed' | 'cancelled';
};

export type IntentSessionInput = {
  name: string;
  durationMinutes: number;
  categoryId: number;
  rules: Array<{
    matchType: 'app_name' | 'executable_path' | 'window_title' | 'url';
    pattern: string;
  }>;
};

export type TodayDashboard = {
  day: string;
  totalTrackedSeconds: number;
  activeSeconds: number;
  idleSeconds: number;
  breakSeconds: number;
  topApps: Array<{
    appName: string;
    durationSeconds: number;
  }>;
  timeline: Array<{
    id: number;
    appName: string;
    windowTitle: string | null;
    startedAt: string;
    endedAt: string | null;
    durationSeconds: number;
    isIdle: boolean;
  }>;
  current: CurrentActivity;
  activeIntent: IntentSession | null;
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

export function getCategories(): Category[] {
  return requireDatabase().prepare('SELECT * FROM categories ORDER BY is_builtin DESC, name ASC').all() as Category[];
}

export function getActiveIntentSession(now = new Date()): IntentSession | null {
  completeExpiredIntentSessions(now);

  return (
    (requireDatabase()
      .prepare(
        `
          SELECT intent_sessions.*, categories.name AS category_name
          FROM intent_sessions
          JOIN categories ON categories.id = intent_sessions.category_id
          WHERE intent_sessions.status = 'active'
          ORDER BY intent_sessions.started_at DESC
          LIMIT 1
        `,
      )
      .get() as IntentSession | undefined) ?? null
  );
}

export function startIntentSession(input: IntentSessionInput, now = new Date()): IntentSession {
  const database = requireDatabase();
  const durationMinutes = Math.max(1, Math.floor(input.durationMinutes));
  const startedAt = now.toISOString();
  const endsAt = new Date(now.getTime() + durationMinutes * 60_000).toISOString();
  const rules = input.rules
    .map((rule) => ({ ...rule, pattern: rule.pattern.trim() }))
    .filter((rule) => rule.pattern.length > 0);

  if (rules.length === 0) {
    throw new Error('Intent session requires at least one app or window rule.');
  }

  return database.transaction(() => {
    database.prepare("UPDATE intent_sessions SET status = 'cancelled' WHERE status = 'active'").run();

    const result = database
      .prepare(
        `
          INSERT INTO intent_sessions (name, category_id, started_at, ends_at, status)
          VALUES (@name, @categoryId, @startedAt, @endsAt, 'active')
        `,
      )
      .run({
        name: input.name.trim() || 'Intent Session',
        categoryId: input.categoryId,
        startedAt,
        endsAt,
      });

    const intentSessionId = Number(result.lastInsertRowid);
    const insertRule = database.prepare(`
      INSERT INTO intent_session_rules (intent_session_id, match_type, pattern)
      VALUES (@intentSessionId, @matchType, @pattern)
    `);

    for (const rule of rules) {
      insertRule.run({
        intentSessionId,
        matchType: rule.matchType,
        pattern: rule.pattern,
      });
    }

    return getIntentSessionById(database, intentSessionId);
  })();
}

export function stopActiveIntentSession(): void {
  requireDatabase()
    .prepare("UPDATE intent_sessions SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP WHERE status = 'active'")
    .run();
}

export function getActivityFingerprint(sample: ActivitySampleInput): string {
  const resolved = resolveCategoryForSample(requireDatabase(), sample, new Date(sample.sampledAt));

  return JSON.stringify({
    appName: sample.appName,
    executablePath: sample.executablePath,
    windowTitle: sample.windowTitle,
    isIdle: sample.isIdle,
    categoryId: resolved.categoryId,
    intentSessionId: resolved.intentSessionId,
  });
}

export function recordActivityChange(sample: ActivitySampleInput, forceNewSession = false): ActivitySession {
  const database = requireDatabase();
  const appId = sample.isIdle ? null : upsertApp(database, sample);
  const { categoryId } = resolveCategoryForSample(database, sample, new Date(sample.sampledAt));

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
      categoryName: null,
    };
  }

  const category = currentSession.category_id
    ? (database.prepare('SELECT name FROM categories WHERE id = ?').get(currentSession.category_id) as
        | { name: string }
        | undefined)
    : undefined;

  return {
    sessionId: currentSession.id,
    appName: currentSession.app_name,
    windowTitle: currentSession.window_title,
    executablePath: currentSession.executable_path,
    isIdle: Boolean(currentSession.is_idle),
    startedAt: currentSession.started_at,
    durationSeconds: currentSession.duration_seconds,
    categoryName: category?.name ?? null,
  };
}

export function getTodayDashboard(now = new Date()): TodayDashboard {
  const database = requireDatabase();
  const dayStart = new Date(now);
  dayStart.setHours(0, 0, 0, 0);

  const dayEnd = new Date(dayStart);
  dayEnd.setDate(dayEnd.getDate() + 1);

  const rows = database
    .prepare(
      `
        SELECT *
        FROM activity_sessions
        WHERE started_at < @dayEnd
          AND COALESCE(ended_at, @now) >= @dayStart
        ORDER BY started_at ASC, id ASC
      `,
    )
    .all({
      dayStart: dayStart.toISOString(),
      dayEnd: dayEnd.toISOString(),
      now: now.toISOString(),
    }) as ActivitySession[];

  let activeSeconds = 0;
  let idleSeconds = 0;
  const topAppDurations = new Map<string, number>();

  const timeline = rows.map((session) => {
    const durationSeconds = getSessionOverlapSeconds(session, dayStart, dayEnd, now);

    if (session.is_idle) {
      idleSeconds += durationSeconds;
    } else {
      activeSeconds += durationSeconds;
      topAppDurations.set(session.app_name, (topAppDurations.get(session.app_name) ?? 0) + durationSeconds);
    }

    return {
      id: session.id,
      appName: session.app_name,
      windowTitle: session.window_title,
      startedAt: session.started_at,
      endedAt: session.ended_at,
      durationSeconds,
      isIdle: Boolean(session.is_idle),
    };
  });

  const topApps = [...topAppDurations.entries()]
    .map(([appName, durationSeconds]) => ({ appName, durationSeconds }))
    .sort((a, b) => b.durationSeconds - a.durationSeconds)
    .slice(0, 5);

  return {
    day: formatLocalDay(dayStart),
    totalTrackedSeconds: activeSeconds + idleSeconds,
    activeSeconds,
    idleSeconds,
    breakSeconds: 0,
    topApps,
    timeline,
    current: getCurrentActivity(),
    activeIntent: getActiveIntentSession(now),
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

  if (currentVersion < 2) {
    database.transaction(() => {
      addColumnIfMissing(database, 'categories', 'is_focus', 'INTEGER NOT NULL DEFAULT 0');
      addColumnIfMissing(database, 'categories', 'is_work', 'INTEGER NOT NULL DEFAULT 0');
      addColumnIfMissing(database, 'categories', 'is_break', 'INTEGER NOT NULL DEFAULT 0');
      addColumnIfMissing(database, 'categories', 'is_idle', 'INTEGER NOT NULL DEFAULT 0');
      addColumnIfMissing(database, 'categories', 'idle_detection_exempt', 'INTEGER NOT NULL DEFAULT 0');
      addColumnIfMissing(database, 'categories', 'distraction_blocker_enabled', 'INTEGER NOT NULL DEFAULT 0');
      addColumnIfMissing(database, 'rules', 'priority', 'INTEGER NOT NULL DEFAULT 100');

      database.exec(`
        CREATE TABLE IF NOT EXISTS intent_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
          started_at TEXT NOT NULL,
          ends_at TEXT NOT NULL,
          status TEXT NOT NULL CHECK (status IN ('active', 'completed', 'cancelled')),
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_intent_sessions_status_ends_at
          ON intent_sessions(status, ends_at);

        CREATE TABLE IF NOT EXISTS intent_session_rules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          intent_session_id INTEGER NOT NULL REFERENCES intent_sessions(id) ON DELETE CASCADE,
          match_type TEXT NOT NULL CHECK (match_type IN ('app_name', 'executable_path', 'window_title', 'url')),
          pattern TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
      `);

      database.pragma(`user_version = ${CURRENT_SCHEMA_VERSION}`);
    })();
  }
}

function seedDefaults(database: Database.Database): void {
  const insertCategory = database.prepare(`
    INSERT OR IGNORE INTO categories
      (
        name,
        color,
        is_builtin,
        is_focus_eligible,
        is_focus,
        is_work,
        is_break,
        is_idle,
        is_distracting,
        idle_detection_exempt,
        distraction_blocker_enabled
      )
    VALUES
      (
        @name,
        @color,
        1,
        @isFocus,
        @isFocus,
        @isWork,
        @isBreak,
        @isIdle,
        @isDistracting,
        @idleDetectionExempt,
        @distractionBlockerEnabled
      )
    ON CONFLICT(name) DO UPDATE SET
      color = excluded.color,
      is_builtin = 1,
      is_focus_eligible = excluded.is_focus_eligible,
      is_focus = excluded.is_focus,
      is_work = excluded.is_work,
      is_break = excluded.is_break,
      is_idle = excluded.is_idle,
      is_distracting = excluded.is_distracting,
      idle_detection_exempt = excluded.idle_detection_exempt,
      distraction_blocker_enabled = excluded.distraction_blocker_enabled,
      updated_at = CURRENT_TIMESTAMP
  `);

  const categories = [
    ['Focus Work', '#f97316', 1, 1, 0, 0, 0, 0],
    ['Shallow Work', '#fb923c', 0, 1, 0, 0, 0, 0],
    ['Communication', '#38bdf8', 0, 1, 0, 0, 0, 0],
    ['Meetings', '#a78bfa', 0, 1, 0, 0, 1, 0],
    ['Planning', '#2dd4bf', 1, 1, 0, 0, 0, 0],
    ['Admin', '#94a3b8', 0, 1, 0, 0, 0, 0],
    ['Learning', '#22c55e', 1, 1, 0, 0, 0, 0],
    ['Creative', '#f59e0b', 1, 1, 0, 0, 0, 0],
    ['Break', '#84cc16', 0, 0, 1, 0, 1, 0],
    ['Idle', '#737373', 0, 0, 0, 1, 0, 0],
    ['Personal', '#e879f9', 0, 0, 0, 0, 0, 0],
    ['Entertainment', '#ef4444', 0, 0, 0, 0, 1, 1],
    ['Social', '#ec4899', 0, 0, 0, 0, 1, 1],
    ['Distraction', '#dc2626', 0, 0, 0, 0, 1, 1],
    ['Uncategorized', '#a3a3a3', 0, 0, 0, 0, 0, 0],
  ];

  const insertSetting = database.prepare(`
    INSERT OR IGNORE INTO settings (key, value)
    VALUES (@key, @value)
  `);

  database.transaction(() => {
    for (const [
      name,
      color,
      isFocus,
      isWork,
      isBreak,
      isIdle,
      isDistracting,
      distractionBlockerEnabled,
    ] of categories) {
      insertCategory.run({
        name,
        color,
        isFocus,
        isWork,
        isBreak,
        isIdle,
        isDistracting,
        idleDetectionExempt: isBreak || isIdle,
        distractionBlockerEnabled,
      });
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

function addColumnIfMissing(
  database: Database.Database,
  tableName: string,
  columnName: string,
  columnDefinition: string,
): void {
  const columns = database.prepare(`PRAGMA table_info(${tableName})`).all() as Array<{ name: string }>;
  if (columns.some((column) => column.name === columnName)) {
    return;
  }

  database.exec(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDefinition}`);
}

function resolveCategoryForSample(
  database: Database.Database,
  sample: ActivitySampleInput,
  now: Date,
): { categoryId: number | null; intentSessionId: number | null } {
  if (sample.isIdle) {
    return { categoryId: getCategoryIdByName(database, 'Idle'), intentSessionId: null };
  }

  completeExpiredIntentSessions(now);

  const intentMatch = getIntentCategoryMatch(database, sample);
  if (intentMatch) {
    return intentMatch;
  }

  const ruleMatch = getRuleCategoryMatch(database, sample);
  if (ruleMatch) {
    return { categoryId: ruleMatch.categoryId, intentSessionId: null };
  }

  const appCategory = getAppCategoryId(database, sample);
  if (appCategory) {
    return { categoryId: appCategory, intentSessionId: null };
  }

  return { categoryId: getCategoryIdByName(database, 'Uncategorized'), intentSessionId: null };
}

function completeExpiredIntentSessions(now: Date): void {
  requireDatabase()
    .prepare(
      `
        UPDATE intent_sessions
        SET status = 'completed',
            updated_at = CURRENT_TIMESTAMP
        WHERE status = 'active'
          AND ends_at <= @now
      `,
    )
    .run({ now: now.toISOString() });
}

function getIntentCategoryMatch(
  database: Database.Database,
  sample: ActivitySampleInput,
): { categoryId: number; intentSessionId: number } | null {
  const rows = database
    .prepare(
      `
        SELECT intent_sessions.id AS intent_session_id,
               intent_sessions.category_id,
               intent_session_rules.match_type,
               intent_session_rules.pattern
        FROM intent_sessions
        JOIN intent_session_rules ON intent_session_rules.intent_session_id = intent_sessions.id
        WHERE intent_sessions.status = 'active'
        ORDER BY intent_sessions.started_at DESC, intent_session_rules.id ASC
      `,
    )
    .all() as Array<{
    intent_session_id: number;
    category_id: number;
    match_type: string;
    pattern: string;
  }>;

  for (const row of rows) {
    if (ruleMatchesSample(row.match_type, row.pattern, sample)) {
      return { categoryId: row.category_id, intentSessionId: row.intent_session_id };
    }
  }

  return null;
}

function getRuleCategoryMatch(
  database: Database.Database,
  sample: ActivitySampleInput,
): { categoryId: number } | null {
  const rows = database
    .prepare(
      `
        SELECT category_id, match_type, pattern
        FROM rules
        WHERE is_enabled = 1
        ORDER BY priority ASC, id ASC
      `,
    )
    .all() as Array<{ category_id: number; match_type: string; pattern: string }>;

  for (const row of rows) {
    if (ruleMatchesSample(row.match_type, row.pattern, sample)) {
      return { categoryId: row.category_id };
    }
  }

  return null;
}

function getAppCategoryId(database: Database.Database, sample: ActivitySampleInput): number | null {
  const row = database
    .prepare('SELECT category_id FROM apps WHERE name = @appName AND executable_path IS @executablePath')
    .get({ appName: sample.appName, executablePath: sample.executablePath }) as
    | { category_id: number | null }
    | undefined;

  return row?.category_id ?? null;
}

function ruleMatchesSample(matchType: string, pattern: string, sample: ActivitySampleInput): boolean {
  const normalizedPattern = pattern.trim().toLowerCase();
  if (!normalizedPattern) {
    return false;
  }

  const target = getRuleTarget(matchType, sample)?.toLowerCase();
  return Boolean(target?.includes(normalizedPattern));
}

function getRuleTarget(matchType: string, sample: ActivitySampleInput): string | null {
  switch (matchType) {
    case 'app_name':
      return sample.appName;
    case 'executable_path':
      return sample.executablePath;
    case 'window_title':
    case 'url':
      return sample.windowTitle;
    default:
      return null;
  }
}

function getIntentSessionById(database: Database.Database, id: number): IntentSession {
  const row = database
    .prepare(
      `
        SELECT intent_sessions.*, categories.name AS category_name
        FROM intent_sessions
        JOIN categories ON categories.id = intent_sessions.category_id
        WHERE intent_sessions.id = ?
      `,
    )
    .get(id) as IntentSession | undefined;

  if (!row) {
    throw new Error(`Intent session ${id} was not found.`);
  }

  return row;
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

function getSessionOverlapSeconds(
  session: ActivitySession,
  dayStart: Date,
  dayEnd: Date,
  now: Date,
): number {
  const startedAt = Math.max(Date.parse(session.started_at), dayStart.getTime());
  const endedAt = Math.min(Date.parse(session.ended_at ?? now.toISOString()), dayEnd.getTime(), now.getTime());

  return Math.max(0, Math.floor((endedAt - startedAt) / 1000));
}

function formatLocalDay(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
}

function readPositiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return Math.floor(parsed);
}
