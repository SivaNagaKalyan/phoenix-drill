#!/usr/bin/env bash
# Backup vault: S3-compatible object storage that lives OUTSIDE the cluster.
# Destroying the cluster must never destroy the backups. That is the whole point.
#
# Usage: vault.sh up | attach | list | down [--purge]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require docker curl

ensure_credentials() {
  if [[ ! -f "${STATE_DIR}/vault.env" ]]; then
    umask 077
    {
      echo "VAULT_ACCESS_KEY=phoenix$(openssl rand -hex 6)"
      echo "VAULT_SECRET_KEY=$(openssl rand -hex 24)"
    } >"${STATE_DIR}/vault.env"
    log "generated vault credentials in .phoenix/vault.env (git-ignored)"
  fi
  # shellcheck source=/dev/null
  source "${STATE_DIR}/vault.env"
}

up() {
  ensure_credentials
  if [[ "$(docker inspect -f '{{.State.Running}}' "${VAULT_CONTAINER}" 2>/dev/null)" != "true" ]]; then
    docker rm -f "${VAULT_CONTAINER}" >/dev/null 2>&1 || true
    log "starting vault ${MINIO_IMAGE}"
    docker run -d --name "${VAULT_CONTAINER}" --restart unless-stopped \
      -p "127.0.0.1:${VAULT_HOST_PORT}:9000" \
      -v "${VAULT_VOLUME}:/data" \
      -e MINIO_ROOT_USER="${VAULT_ACCESS_KEY}" -e MINIO_ROOT_PASSWORD="${VAULT_SECRET_KEY}" \
      "${MINIO_IMAGE}" server /data >/dev/null
  fi
  retry 30 1 curl -fsS "http://127.0.0.1:${VAULT_HOST_PORT}/minio/health/live" -o /dev/null \
    || die "vault did not become healthy"
  if ! vault_s3 s3api head-bucket --bucket "${VAULT_BUCKET}" >/dev/null 2>&1; then
    vault_s3 s3api create-bucket --bucket "${VAULT_BUCKET}" >/dev/null
    log "created bucket ${VAULT_BUCKET}"
  fi
  log "vault ready at 127.0.0.1:${VAULT_HOST_PORT}"
}

# Join the vault to the kind docker network and print the in-cluster endpoint.
attach() {
  docker network inspect kind >/dev/null 2>&1 || die "docker network 'kind' missing; create the cluster first"
  if [[ -z "$(docker inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "${VAULT_CONTAINER}")" ]]; then
    docker network connect kind "${VAULT_CONTAINER}"
  fi
  local ip
  ip="$(docker inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "${VAULT_CONTAINER}")"
  [[ -n "${ip}" ]] || die "could not resolve vault address on the kind network"
  echo "http://${ip}:9000"
}

list() { vault_s3 s3 ls "s3://${VAULT_BUCKET}/backups/"; }

down() {
  docker rm -f "${VAULT_CONTAINER}" >/dev/null 2>&1 || true
  if [[ "${1:-}" == "--purge" ]]; then
    docker volume rm "${VAULT_VOLUME}" >/dev/null 2>&1 || true
    rm -f "${STATE_DIR}/vault.env"
    log "vault and all backups deleted"
  else
    log "vault stopped (backups kept in volume ${VAULT_VOLUME})"
  fi
}

case "${1:-}" in
  up) up ;;
  attach) attach ;;
  list) list ;;
  down) shift; down "$@" ;;
  *) die "usage: vault.sh up|attach|list|down [--purge]" ;;
esac
