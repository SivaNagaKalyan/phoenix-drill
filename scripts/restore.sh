#!/usr/bin/env bash
# Restore the newest backup from the vault into the database in the current cluster.
# Prints the object key that was restored on stdout.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

job="$(kubectl --context "${KUBE_CONTEXT}" create -f "${ROOT}/deploy/jobs/restore-job.yaml" -o name)"
job="${job#job.batch/}"
log "started ${job}"
wait_job "${job}" 900 || die "restore failed"
object="$(kc logs "job/${job}" -c fetch | sed -n 's/^RESTORE_OBJECT=//p' | tail -n 1)"
log "$(kc logs "job/${job}" -c restore | tail -n 1)"
echo "${object}"
