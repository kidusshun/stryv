const path = require('node:path');
const Database = require('better-sqlite3');

const dbPath = path.join(process.env.APPDATA, 'stryv', 'stryv.sqlite');
const db = new Database(dbPath, { readonly: true });

console.log(`DB: ${dbPath}`);
console.log(`user_version: ${db.pragma('user_version', { simple: true })}`);

const tables = db
  .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
  .all();

for (const { name } of tables) {
  const columns = db
    .prepare(`PRAGMA table_info(${name})`)
    .all()
    .map((column) => {
      const flags = [column.notnull ? 'NOT NULL' : '', column.pk ? 'PRIMARY KEY' : '']
        .filter(Boolean)
        .join(' ');

      return `  - ${column.name} ${column.type}${flags ? ` ${flags}` : ''}`;
    });

  console.log(`\n${name}`);
  for (const column of columns) {
    console.log(column);
  }
}

db.close();
process.exit(0);
