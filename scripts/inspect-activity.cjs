const path = require('node:path');
const Database = require('better-sqlite3');

const dbPath = path.join(process.env.APPDATA, 'stryv', 'stryv.sqlite');
const db = new Database(dbPath, { readonly: true });

for (const table of ['activity_samples', 'activity_sessions', 'apps']) {
  const row = db.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get();
  console.log(`${table}: ${row.count}`);
}

const sessions = db
  .prepare(
    `
      SELECT id, app_name, window_title, is_idle, started_at, ended_at, duration_seconds
      FROM activity_sessions
      ORDER BY id DESC
      LIMIT 5
    `,
  )
  .all();

console.log(JSON.stringify(sessions, null, 2));

db.close();
process.exit(0);
