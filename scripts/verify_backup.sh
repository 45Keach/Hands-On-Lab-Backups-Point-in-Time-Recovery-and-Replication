#!/usr/bin/env bash
set -euo pipefail

BACKUP="$HOME/backups/bootcamp.dump"
CHECK_DB="bootcamp_check"

test -s "$BACKUP"
echo "Backup archive:"
pg_restore --list "$BACKUP" | head

if psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$CHECK_DB'" | grep -q 1; then
  dropdb "$CHECK_DB"
fi

createdb "$CHECK_DB"
pg_restore -d "$CHECK_DB" "$BACKUP"
echo "Restore completed successfully."
psql -d "$CHECK_DB" -c '\\dt'
psql -d "$CHECK_DB" -c 'SELECT count(*) FROM students;'
