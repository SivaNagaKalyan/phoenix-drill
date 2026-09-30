# Findings from building the drill

Real failure modes discovered while making disaster recovery testable. Each one is a bug that a recovery plan on paper would not have caught.

## 1. A rebuilt cluster can overwrite your newest backup with an empty one

**What happens:** after a rebuild, the backup CronJob starts on its normal schedule. If it fires before the restore finishes, it uploads a dump of an empty database. That dump is now the newest backup, and the next restore silently restores nothing.

**Fix, in two layers:**

1. The CronJob ships with `suspend: true`. It is only enabled after the database is healthy and, during a recovery, after the restored data is verified.
2. The backup job itself refuses to back up a database with zero records unless `ALLOW_EMPTY_BACKUP=true`.

## 2. Credentials change on every rebuild

**What happens:** database passwords are generated inside each new cluster. A dump that preserves object ownership fails to restore, or restores objects owned by a role that no longer exists.

**Fix:** dump and restore with `--no-owner --no-privileges`. Verified: restoring into a database owned by a different role produces an identical checksum.

## 3. Sequences must come back with the data

**What happens:** if the id sequence is not restored, the first insert after recovery collides with an existing primary key.

**Fix:** custom-format dumps include sequence state. Verified: after restoring 20000 records, the next insert receives id 20001.

## 4. "Pods are running" is not recovery

**What happens:** the app becomes ready against an empty or partial database, and dashboards turn green.

**Fix:** the recovery clock only stops when count and checksum match the backup. Readiness depends on the database, liveness does not, so a database outage does not cause a restart storm.

## 5. Recovery must not depend on the internet being kind

**What happens:** a rebuild pulls every image again. Registry rate limits or outages turn a 5 minute recovery into a failed one.

**Fix:** images are pinned in one file and loaded into the new cluster from a local cache. In production this is a replicated private registry.
