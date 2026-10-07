# Hands-On Lab: Backups, Point-in-Time Recovery, and Replication

## Objective

This lab demonstrates PostgreSQL backup and disaster-recovery fundamentals:

- Create and verify a logical backup
- Enable WAL archiving and create a physical base backup
- Recover a database to a precise point in time (PITR)
- Configure and monitor a streaming standby replica

> **Lab note:** Run these commands in a disposable PostgreSQL lab environment. Recovery operations can destroy or replace a PostgreSQL data directory.

## Step 1: Logical Backup

```bash
mkdir -p ~/backups
pg_dump -Fc -f ~/backups/bootcamp.dump bootcamp
pg_restore --list ~/backups/bootcamp.dump | head
createdb bootcamp_check
pg_restore -d bootcamp_check ~/backups/bootcamp.dump
```

Verify the restored database:

```bash
psql -d bootcamp_check -c "\\dt"
psql -d bootcamp_check -c "SELECT count(*) FROM students;"
```

## Step 2: WAL Archiving and Base Backup

Create the archive directory:

```bash
mkdir -p ~/backups/wal
```

Add to `postgresql.conf` (replace `YOUR_USER` with the OS account that owns the backup directory):

```conf
wal_level = replica
archive_mode = on
archive_command = 'cp %p /home/YOUR_USER/backups/wal/%f'
```

Restart and verify:

```bash
sudo systemctl restart postgresql
psql -d postgres -c "SHOW wal_level;"
psql -d postgres -c "SHOW archive_mode;"
psql -d postgres -c "SHOW archive_command;"
```

Take a physical base backup:

```bash
pg_basebackup -D ~/backups/base -Ft -z -Xs -P
```

Check the WAL archive:

```bash
psql -d bootcamp -c "SELECT now();"
ls -lh ~/backups/wal/
```

## Step 3: Simulate Disaster and Perform PITR

Record a timestamp immediately before the destructive operation:

```sql
SELECT now();
DELETE FROM students;
SELECT count(*) FROM students;
```

Stop PostgreSQL:

```bash
sudo systemctl stop postgresql
```

Determine the actual data directory before replacing it:

```bash
sudo -u postgres psql -d postgres -c "SHOW data_directory;"
ls -lh ~/backups/base/
```

Restore the appropriate `base.tar.gz` (and any tablespace archives) into the PostgreSQL data directory using the PostgreSQL service account. Do not blindly overwrite a production data directory.

During recovery, configure an absolute WAL restore path:

```conf
restore_command = 'cp /home/YOUR_USER/backups/wal/%f %p'
recovery_target_time = '2026-10-07 08:30:00+01'
recovery_target_action = 'pause'
```

Modern PostgreSQL uses a recovery signal file. Create `standby.signal` in the restored data directory, then start PostgreSQL:

```bash
sudo -u postgres touch /path/to/data_directory/standby.signal
sudo systemctl start postgresql
```

Verify:

```sql
SELECT pg_is_in_recovery();
SELECT count(*) FROM students;
```

The row count should match the state at the chosen recovery target, before the accidental delete. Once verified, complete recovery according to the PostgreSQL version and lab requirements.

## Step 4: Streaming Standby

On the primary:

```sql
CREATE ROLE replicator
WITH REPLICATION LOGIN PASSWORD 'reppass';
```

In `pg_hba.conf`, prefer SCRAM where supported:

```conf
host replication replicator 127.0.0.1/32 scram-sha-256
```

If the lab specifically uses MD5:

```conf
host replication replicator 127.0.0.1/32 md5
```

Reload PostgreSQL:

```bash
sudo systemctl reload postgresql
```

Build the standby in a separate empty directory:

```bash
rm -rf ~/standby
pg_basebackup -h 127.0.0.1 -U replicator -D ~/standby -R -P
```

For a real two-server setup, use the primary server's reachable address instead of `127.0.0.1` and configure network access appropriately.

## Step 5: Monitor Replication

From the primary:

```sql
SELECT application_name,
       client_addr,
       state,
       sync_state,
       sent_lsn,
       write_lsn,
       flush_lsn,
       replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

On the standby:

```sql
SELECT pg_is_in_recovery();
SELECT * FROM pg_stat_wal_receiver;
```

`state = streaming` indicates active streaming. `lag_bytes` estimates WAL sent but not yet replayed.

## Troubleshooting

### WAL archive is empty

```sql
SHOW archive_mode;
SHOW archive_command;
SELECT * FROM pg_stat_archiver;
```

Confirm the PostgreSQL service account can write to the archive destination.

### `pg_basebackup` cannot connect

Check `listen_addresses`, `port`, and the relevant `pg_hba.conf` rule, then reload PostgreSQL.

### Standby does not appear

Check `pg_stat_wal_receiver` on the standby and PostgreSQL logs on both systems.

### PITR target is not reached

Confirm that the base backup predates the target, required WAL files exist, `restore_command` uses the correct absolute path, the timestamp/time zone is correct, and WAL archiving was working before the failure.

## Wrap-Up

This lab demonstrates layered PostgreSQL protection: logical backups, base backups plus WAL archives, point-in-time recovery, and streaming replication. The operational lesson is to verify backups by restoring them, monitor WAL archiving, and test recovery procedures before an actual incident.
