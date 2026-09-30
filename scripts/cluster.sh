#!/usr/bin/env bash
# Disposable Kubernetes cluster lifecycle.
# Usage: cluster.sh up | down
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require kind kubectl docker

up() {
  if cluster_exists; then
    log "cluster ${CLUSTER_NAME} already exists"
  else
    log "creating cluster ${CLUSTER_NAME} (${KIND_NODE_IMAGE%@*})"
    kind create cluster --name "${CLUSTER_NAME}" --image "${KIND_NODE_IMAGE}" \
      --config "${ROOT}/kind/cluster.yaml" --wait 180s
  fi
  kubectl --context "${KUBE_CONTEXT}" wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
  # Seed node image caches from the host so a rebuild does not depend on registry
  # availability or rate limits. In a real platform this is a registry mirror.
  local image
  for image in "${POSTGRES_IMAGE}" "${AWSCLI_IMAGE}"; do
    docker image inspect "${image}" >/dev/null 2>&1 || docker pull -q "${image}" >/dev/null
    kind load docker-image --name "${CLUSTER_NAME}" "${image}" >/dev/null
  done
  log "cluster ready"
}

down() {
  if cluster_exists; then
    kind delete cluster --name "${CLUSTER_NAME}"
  else
    log "cluster ${CLUSTER_NAME} does not exist"
  fi
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) die "usage: cluster.sh up|down" ;;
esac
