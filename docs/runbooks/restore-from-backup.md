# Runbook: Restore the database from backup

**Owner:** Platform on-call | **Frequency:** As needed, and exercised weekly by the Phoenix drill

## Purpose

Recover the ledger database after data loss or loss of the cluster, using the newest backup in the vault.

## Prerequisites

- [ ] Access to the repository and a shell with docker, kind, kubectl, jq (`make tools`)
- [ ] The vault is running and holds at least one backup: `make backups`
- [ ] Vault credentials exist in `.phoenix/vault.env`

## Procedure

### Step 1: Confirm a usable backup exists

```bash
make backups
```

**Expected result:** at least one `<timestamp>.dump` with a matching `.sha256`.
**If it fails:** start the vault with `bash scripts/vault.sh up`. If there are no backups, stop and escalate. Do not continue into an empty restore.

### Step 2: Make sure a cluster and database exist

```bash
bash scripts/cluster.sh up
bash scripts/deploy.sh data
```

**Expected result:** `database ready`. The backup schedule stays suspended at this point on purpose.
**If it fails:** run `bash scripts/diagnostics.sh` and read `.phoenix/diagnostics/events.txt`.

### Step 3: Restore

```bash
bash scripts/restore.sh
```

**Expected result:** prints the restored object key and `restore complete: N records`.
**If it fails:** a checksum failure means the newest dump is corrupt. Remove it from the vault after saving a copy, then run the step again to use the previous one.

### Step 4: Deploy the application

```bash
bash scripts/deploy.sh app "$(bash scripts/build.sh)"
```

**Expected result:** `ledger ... ready`.

### Step 5: Verify, then re-enable backups

```bash
make summary
bash scripts/deploy.sh backups-on
make backup
```

## Verification

- [ ] Record count matches the count expected at the time of the restored backup
- [ ] A new backup completes after recovery

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Restore job `no backups found` | Wrong bucket or empty vault | `make backups`; check the `backup-vault` Secret |
| `sha256sum: WARNING: 1 computed checksum did NOT match` | Corrupt or partial upload | Use the previous backup (Step 3) |
| Pods `CreateContainerConfigError` | Secrets missing | Re-run `bash scripts/deploy.sh data` |
| Backup job `refusing to back up an empty database` | Backups enabled before restore | Expected guard; restore first |

## Rollback

The restore runs in a single transaction. If it fails, the database is unchanged. If a completed restore used the wrong backup, run it again against the intended one.

## Escalation

| Situation | Contact | Method |
|---|---|---|
| No valid backup exists | Platform lead | Incident channel, page |
| Restore succeeds but checksum differs from expected | Service owner | Incident channel |
