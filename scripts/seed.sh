#!/usr/bin/env bash
# Write deterministic records through the public API.
# Usage: seed.sh COUNT [SEED] [START]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl curl jq

count="${1:?count required}"
seed="${2:-phoenix}"
start="${3:-0}"
batch=5000

app_connect
written=0
while ((written < count)); do
  n=$((count - written < batch ? count - written : batch))
  api POST /records/generate "{\"seed\":\"${seed}\",\"start\":$((start + written)),\"count\":${n}}" >/dev/null
  written=$((written + n))
done
log "wrote ${count} records (seed=${seed}, start=${start})"
api GET /records/summary
