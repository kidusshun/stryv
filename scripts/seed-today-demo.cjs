const path = require('node:path');
const Database = require('better-sqlite3');

const dbPath = path.join(process.env.APPDATA, 'stryv', 'stryv.sqlite');
const db = new Database(dbPath);

const categories = new Map(
  db.prepare('SELECT id, name FROM categories').all().map((category) => [category.name, category.id]),
);

function localTodayAt(hour, minute) {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0, 0).toISOString();
}

function categoryId(name) {
  const id = categories.get(name);
  if (!id) {
    throw new Error(`Missing category: ${name}`);
  }

  return id;
}

const sessions = [
  ['Deep work planning', 'Stryv', 'Focus Work', '08:00', '08:55', false],
  ['Design reference review', 'Figma', 'Creative', '08:55', '09:25', false],
  ['Break', 'Break', 'Break', '09:25', '09:55', true],
  ['React implementation', 'Codex', 'Focus Work', '09:55', '10:40', false],
  ['Docs lookup', 'YouTube', 'Learning', '10:40', '11:10', false],
  ['Break', 'Break', 'Break', '11:10', '11:35', true],
  ['Team messages', 'Telegram Desktop', 'Communication', '11:35', '12:05', false],
  ['Lunch break', 'Break', 'Break', '12:05', '13:05', true],
  ['Rule cleanup', 'Stryv', 'Admin', '13:05', '13:35', false],
  ['Category tuning', 'Stryv', 'Planning', '13:35', '14:10', false],
  ['Content research', 'TikTok', 'Learning', '14:10', '14:45', false],
  ['Break', 'Break', 'Break', '14:45', '15:15', true],
  ['UI polish', 'Codex', 'Creative', '15:15', '16:30', false],
];

const insert = db.prepare(`
  INSERT INTO activity_sessions (
    app_id,
    category_id,
    started_at,
    ended_at,
    duration_seconds,
    app_name,
    executable_path,
    window_title,
    is_idle
  )
  VALUES (
    NULL,
    @categoryId,
    @startedAt,
    @endedAt,
    @durationSeconds,
    @appName,
    NULL,
    @windowTitle,
    @isIdle
  )
`);

db.transaction(() => {
  for (const [windowTitle, appName, categoryName, start, end, isIdle] of sessions) {
    const [startHour, startMinute] = start.split(':').map(Number);
    const [endHour, endMinute] = end.split(':').map(Number);
    const startedAt = localTodayAt(startHour, startMinute);
    const endedAt = localTodayAt(endHour, endMinute);

    insert.run({
      appName,
      categoryId: categoryId(categoryName),
      durationSeconds: Math.floor((Date.parse(endedAt) - Date.parse(startedAt)) / 1000),
      endedAt,
      isIdle: Number(isIdle),
      startedAt,
      windowTitle,
    });
  }
})();

console.log(`Seeded ${sessions.length} demo sessions into ${dbPath}`);

db.close();
process.exit(0);
