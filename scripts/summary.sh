#!/usr/bin/env bash
# Print {"count": N, "checksum": "..."} for the live dataset.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl curl
app_connect
api GET /records/summary
