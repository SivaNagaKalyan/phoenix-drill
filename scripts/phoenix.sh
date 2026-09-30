#!/usr/bin/env bash
# The Phoenix drill: build everything, destroy everything, rebuild from code, prove the data survived.
#
# Environment:
#   RECORDS              records written before the backup           (default 20000)
#   LATE_WRITES          records written after the backup             (default 100)
#   RTO_BUDGET_SECONDS   fail the drill if recovery takes longer      (default 600)
#
# Outputs .phoenix/results/latest.json and a Markdown report (also appended to
# $GITHUB_STEP_SUMMARY when running in GitHub Actions). Exits non-zero on any failed check.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require docker kind kubectl curl jq openssl git

RECORDS="${RECORDS:-20000}"
LATE_WRITES="${LATE_WRITES:-100}"
RTO_BUDGET_SECONDS="${RTO_BUDGET_SECONDS:-600}"
S="${ROOT}/scripts"
RESULTS="${STATE_DIR}/results"
mkdir -p "${RESULTS}"

on_error() {
  local code=$?
  # The trap is inherited by command substitutions; only the main shell reports.
  [[ "${BASHPID}" == "$$" ]] || exit "${code}"
  log "drill FAILED at phase: ${PHASE:-unknown} (exit ${code})"
  bash "${S}/diagnostics.sh"
  exit "${code}"
}
trap on_error ERR

declare -A T
PHASE=""
phase() { PHASE="$1"; T["$1"]=$(now); log "==== ${1} ===="; }

drill_started=$(now)

# 1. Clean slate. A drill that reuses leftovers proves nothing.
phase preflight
bash "${S}/cluster.sh" down
bash "${S}/vault.sh" down --purge

# 2. Build the world from code.
phase provision
bash "${S}/vault.sh" up
bash "${S}/cluster.sh" up
image="$(bash "${S}/build.sh")"
bash "${S}/deploy.sh" data
bash "${S}/deploy.sh" app "${image}"
bash "${S}/deploy.sh" backups-on
provisioned=$(now)

# 3. Real data, known in advance.
phase seed
before="$(bash "${S}/seed.sh" "${RECORDS}" phoenix 0)"
expected_count="$(jq -r .count <<<"${before}")"
expected_checksum="$(jq -r .checksum <<<"${before}")"
[[ "${expected_count}" -eq "${RECORDS}" ]] || { log "seed wrote ${expected_count}, wanted ${RECORDS}"; false; }

# 4. Back up.
phase backup
backup_object="$(bash "${S}/backup.sh")"
backup_done=$(now)

# 5. Writes that land after the last backup. These SHOULD be lost; measuring them is the RPO.
phase late-writes
at_disaster="$(bash "${S}/seed.sh" "${LATE_WRITES}" late 0)"
count_at_disaster="$(jq -r .count <<<"${at_disaster}")"

# 6. Disaster: the entire cluster is gone. Nodes, volumes, secrets, everything.
phase disaster
bash "${S}/cluster.sh" down
disaster_at=$(now)

# 7. Recovery, from nothing but the repository and the off-cluster vault.
phase recovery
bash "${S}/cluster.sh" up
image="$(bash "${S}/build.sh")"
bash "${S}/deploy.sh" data
restored_object="$(bash "${S}/restore.sh")"
bash "${S}/deploy.sh" app "${image}"

# 8. Recovery is not done until the data is proven correct.
phase verify
after="$(bash "${S}/summary.sh")"
recovered_at=$(now)
actual_count="$(jq -r .count <<<"${after}")"
actual_checksum="$(jq -r .checksum <<<"${after}")"
records_lost=$((count_at_disaster - actual_count))
rto=$((recovered_at - disaster_at))
data_loss_window=$((disaster_at - backup_done))

checks_ok=true
check() { # name, condition...
  local name="$1"; shift
  if "$@"; then log "PASS ${name}"; else log "FAIL ${name}"; checks_ok=false; fi
}
check "restored the backup that was taken" test "${restored_object}" = "${backup_object}"
check "record count matches backup"        test "${actual_count}" = "${expected_count}"
check "checksum matches backup"            test "${actual_checksum}" = "${expected_checksum}"
check "only post-backup writes were lost"  test "${records_lost}" = "${LATE_WRITES}"
check "RTO within ${RTO_BUDGET_SECONDS}s budget" test "${rto}" -le "${RTO_BUDGET_SECONDS}"

# 9. A recovered system that cannot back itself up is not recovered.
phase re-protect
bash "${S}/deploy.sh" backups-on
post_backup="$(bash "${S}/backup.sh")"
check "first backup after recovery succeeded" test -n "${post_backup}"
drill_finished=$(now)

phase report
status=$([[ "${checks_ok}" == true ]] && echo passed || echo failed)
jq -n \
  --arg status "${status}" \
  --arg started "$(date -u -d "@${drill_started}" +%Y-%m-%dT%H:%M:%SZ)" \
  --arg commit "$(git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" \
  --arg backup "${backup_object}" --arg restored "${restored_object}" \
  --arg expected_checksum "${expected_checksum}" --arg actual_checksum "${actual_checksum}" \
  --argjson rto "${rto}" --argjson rto_budget "${RTO_BUDGET_SECONDS}" \
  --argjson window "${data_loss_window}" --argjson lost "${records_lost}" \
  --argjson records "${expected_count}" --argjson restored_count "${actual_count}" \
  --argjson provision "$((provisioned - T[provision]))" \
  --argjson recovery "$((T[verify] - T[recovery]))" \
  --argjson verify "$((recovered_at - T[verify]))" \
  --argjson total "$((drill_finished - drill_started))" \
  '{status: $status, started_at: $started, commit: $commit,
    rto_seconds: $rto, rto_budget_seconds: $rto_budget,
    data_loss_window_seconds: $window, records_lost: $lost,
    records_expected: $records, records_restored: $restored_count,
    checksum_expected: $expected_checksum, checksum_restored: $actual_checksum,
    backup_object: $backup, restored_object: $restored,
    phase_seconds: {initial_provision: $provision, rebuild_and_restore: $recovery, verification: $verify},
    drill_total_seconds: $total}' >"${RESULTS}/latest.json"

report="${RESULTS}/latest.md"
{
  echo "## Phoenix drill: ${status^^}"
  echo
  echo "| Metric | Result |"
  echo "|---|---|"
  echo "| Recovery time (RTO), destroy to verified data | **${rto}s** (budget ${RTO_BUDGET_SECONDS}s) |"
  echo "| Data loss window (time since last backup) | ${data_loss_window}s |"
  echo "| Records lost (written after last backup) | ${records_lost} of ${count_at_disaster} |"
  echo "| Records restored and verified | ${actual_count} |"
  echo "| Checksum match | $([[ "${actual_checksum}" == "${expected_checksum}" ]] && echo yes || echo NO) |"
  echo "| Backup restored | \`${restored_object}\` |"
  echo "| Rebuild and restore phase | $((T[verify] - T[recovery]))s |"
  echo "| Whole drill | $((drill_finished - drill_started))s |"
} >"${report}"
cat "${report}"
[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "${report}" >>"${GITHUB_STEP_SUMMARY}"

[[ "${checks_ok}" == true ]] || { log "one or more checks failed"; exit 1; }
log "drill passed"
