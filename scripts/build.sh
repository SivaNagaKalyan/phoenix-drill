#!/usr/bin/env bash
# Build the ledger image and make it available to the cluster.
# Prints the image reference on stdout.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require docker kind git

tag="$(git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || echo dev)"
if [[ -n "$(git -C "${ROOT}" status --porcelain -- app 2>/dev/null)" ]]; then
  tag="${tag}-dirty"
fi
image="ledger:${tag}"

if ! docker image inspect "${image}" >/dev/null 2>&1 || [[ "${tag}" == *-dirty ]]; then
  log "building ${image}"
  docker build --quiet -t "${image}" "${ROOT}/app" >/dev/null
fi
kind load docker-image --name "${CLUSTER_NAME}" "${image}" >/dev/null
echo "${image}"
