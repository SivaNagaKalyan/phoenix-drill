# ADR 0002: Logical backups with integrity manifests

**Status:** Accepted

## Context

Options considered:

| Option | Pros | Cons |
|---|---|---|
| Volume snapshots | Fast, whole-disk | Tied to storage provider and often to the cluster; crash-consistent only |
| Physical backup plus WAL archiving | Point-in-time recovery, lowest RPO | More moving parts; same major version required for restore |
| Logical dump (`pg_dump -Fc`) | Portable across clusters, versions and credentials; easy to verify | RPO equals the backup interval; slower for very large databases |

## Decision

Use logical dumps in custom format, uploaded with a sha256 manifest. The restore job downloads the newest dump, verifies the checksum, and only then runs `pg_restore`.

Restore flags and why:

* `--no-owner --no-privileges`: the rebuilt cluster has new credentials; ownership from the old cluster is irrelevant.
* `--single-transaction --exit-on-error`: a restore either fully succeeds or changes nothing.
* `--clean --if-exists`: safe to run twice, and safe if the schema already exists.

## Consequences

* RPO is bounded by the schedule (hourly). The drill measures the actual loss on every run.
* Corrupted or truncated uploads are caught before they reach the database.
* For production with a tighter RPO, add WAL archiving and keep logical dumps as an independent second layer.
