const path = require('node:path');
const Database = require('better-sqlite3');

const dbPath = path.join(process.env.APPDATA, 'stryv', 'stryv.sqlite');
const db = new Database(dbPath);

db.transaction(() => {
  db.prepare('DELETE FROM activity_samples').run();
  db.prepare('DELETE FROM activity_sessions').run();
  db.prepare('DELETE FROM daily_summaries').run();
  db.prepare('DELETE FROM intent_session_rules').run();
  db.prepare('DELETE FROM intent_sessions').run();
  db.prepare('DELETE FROM rules').run();
  db.prepare('DELETE FROM apps').run();

  db.prepare("DELETE FROM categories WHERE is_builtin = 0").run();

  for (const table of [
    'activity_samples',
    'activity_sessions',
    'daily_summaries',
    'intent_session_rules',
    'intent_sessions',
    'rules',
    'apps',
    'categories',
  ]) {
    db.prepare('DELETE FROM sqlite_sequence WHERE name = ?').run(table);
  }
})();

db.pragma('wal_checkpoint(TRUNCATE)');
db.close();

console.log(`Reset Stryv data in ${dbPath}`);
process.exit(0);
