#!/usr/bin/env bash
# Shared helpers. Sourced by every script, never executed directly.
# shellcheck shell=bash
# Variables defined here are consumed by the scripts that source this file.
# shellcheck disable=SC2034
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tools/versions.env
source "${ROOT}/tools/versions.env"

export PATH="${TOOLS_BIN:-${HOME}/.local/bin}:${PATH}"

STATE_DIR="${ROOT}/.phoenix"
CLUSTER_NAME="${CLUSTER_NAME:-phoenix}"
KUBE_CONTEXT="kind-${CLUSTER_NAME}"
NAMESPACE="phoenix"
VAULT_CONTAINER="${VAULT_CONTAINER:-phoenix-vault}"
VAULT_BUCKET="${VAULT_BUCKET:-phoenix-backups}"
VAULT_HOST_PORT="${VAULT_HOST_PORT:-19000}"
APP_LOCAL_PORT="${APP_LOCAL_PORT:-18080}"
SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-lib}" .sh)"

mkdir -p "${STATE_DIR}"

log() { printf '%s [%s] %s\n' "$(date -u +%H:%M:%S)" "${SCRIPT_NAME}" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
now() { date +%s; }

require() {
  local missing=0 tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || { log "missing required tool: ${tool}"; missing=1; }
  done
  ((missing == 0)) || die "install missing tools (make tools) and retry"
}

kc() { kubectl --context "${KUBE_CONTEXT}" --namespace "${NAMESPACE}" "$@"; }

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; }

retry() { # attempts, delay_seconds, command...
  local attempts="$1" delay="$2" n=1; shift 2
  until "$@"; do
    ((n >= attempts)) && return 1
    n=$((n + 1)); sleep "${delay}"
  done
}

# Wait for a Job to finish. Returns non-zero and prints logs if it failed or timed out.
wait_job() { # job_name, timeout_seconds
  local job="$1" timeout="$2" deadline succeeded failed
  deadline=$(($(now) + timeout))
  while (($(now) < deadline)); do
    succeeded="$(kc get job "${job}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kc get job "${job}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    [[ "${succeeded:-0}" -ge 1 ]] && return 0
    if [[ "${failed:-0}" -ge 1 ]] && [[ -n "$(kc get job "${job}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')" ]]; then
      log "job ${job} failed"; kc logs "job/${job}" --all-containers --prefix >&2 || true; return 1
    fi
    sleep 3
  done
  log "job ${job} timed out after ${timeout}s"
  kc logs "job/${job}" --all-containers --prefix >&2 || true
  return 1
}

# Port-forward the ledger service for the lifetime of the calling script.
PF_PID=""
app_connect() {
  kc port-forward svc/ledger "${APP_LOCAL_PORT}:80" >"${STATE_DIR}/port-forward.log" 2>&1 &
  PF_PID=$!
  trap app_disconnect EXIT
  retry 30 1 curl -fsS "http://127.0.0.1:${APP_LOCAL_PORT}/readyz" -o /dev/null \
    || die "ledger not reachable through port-forward (see ${STATE_DIR}/port-forward.log)"
}
app_disconnect() {
  if [[ -n "${PF_PID}" ]]; then kill "${PF_PID}" 2>/dev/null || true; fi
}

api() { # method, path, [json body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "${body}" ]]; then
    curl -fsS -X "${method}" -H 'Content-Type: application/json' -d "${body}" "http://127.0.0.1:${APP_LOCAL_PORT}${path}"
  else
    curl -fsS -X "${method}" "http://127.0.0.1:${APP_LOCAL_PORT}${path}"
  fi
}

# Run the pinned AWS CLI image against the vault from the host.
vault_s3() {
  # shellcheck source=/dev/null
  source "${STATE_DIR}/vault.env"
  docker run --rm --network host \
    -e AWS_ACCESS_KEY_ID="${VAULT_ACCESS_KEY}" -e AWS_SECRET_ACCESS_KEY="${VAULT_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    "${AWSCLI_IMAGE}" --endpoint-url "http://127.0.0.1:${VAULT_HOST_PORT}" "$@"
}
