#!/usr/bin/env bash
# Capture everything needed to debug a failed drill. Never fails.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
set +e
out="${STATE_DIR}/diagnostics"
mkdir -p "${out}"
cluster_exists || { log "no cluster to inspect"; exit 0; }
kc get all,pvc,cronjob,job,networkpolicy -o wide >"${out}/resources.txt" 2>&1
kc get events --sort-by=.lastTimestamp >"${out}/events.txt" 2>&1
kc describe pods >"${out}/pods-describe.txt" 2>&1
for pod in $(kc get pods -o name 2>/dev/null); do
  kc logs "${pod}" --all-containers --prefix >"${out}/logs-${pod#pod/}.txt" 2>&1
done
kubectl --context "${KUBE_CONTEXT}" get nodes -o wide >"${out}/nodes.txt" 2>&1
log "diagnostics written to ${out}"
exit 0
