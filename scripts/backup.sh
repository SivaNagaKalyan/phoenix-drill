#!/usr/bin/env bash
# Take an on-demand backup using the exact same CronJob template as scheduled backups.
# Prints the object key of the new backup on stdout.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

job="backup-manual-$(date -u +%Y%m%d%H%M%S)"
kc create job "${job}" --from=cronjob/postgres-backup >/dev/null
log "started ${job}"
wait_job "${job}" 600 || die "backup failed"
object="$(kc logs "job/${job}" -c upload | sed -n 's/^BACKUP_OBJECT=//p' | tail -n 1)"
[[ -n "${object}" ]] || die "backup job did not report an object key"
log "backup stored as ${object}"
echo "${object}"
