#!/usr/bin/env bash
# Deploy the stack from code.
#
# Usage: deploy.sh data          namespace, secrets, database (backups stay suspended)
#        deploy.sh app IMAGE     the ledger service
#        deploy.sh backups-on    enable the backup schedule
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl openssl

ensure_secrets() {
  kubectl --context "${KUBE_CONTEXT}" apply -f "${ROOT}/deploy/data/namespace.yaml" >/dev/null

  # Database credentials are generated inside each new cluster and never leave it.
  # Restores use --no-owner, so a rebuilt cluster does not need the old password.
  if ! kc get secret postgres-credentials >/dev/null 2>&1; then
    kc create secret generic postgres-credentials \
      --from-literal=username=ledger \
      --from-literal=password="$(openssl rand -hex 24)" \
      --from-literal=database=ledger >/dev/null
    log "created postgres-credentials"
  fi

  # shellcheck source=/dev/null
  source "${STATE_DIR}/vault.env"
  local endpoint
  endpoint="$(bash "${ROOT}/scripts/vault.sh" attach)"
  kc create secret generic backup-vault \
    --from-literal=endpoint="${endpoint}" \
    --from-literal=bucket="${VAULT_BUCKET}" \
    --from-literal=access-key="${VAULT_ACCESS_KEY}" \
    --from-literal=secret-key="${VAULT_SECRET_KEY}" \
    --dry-run=client -o yaml | kc apply -f - >/dev/null
  log "backup-vault secret points at ${endpoint}"
}

data() {
  ensure_secrets
  kubectl --context "${KUBE_CONTEXT}" apply -k "${ROOT}/deploy/data" >/dev/null
  kc rollout status statefulset/postgres --timeout=300s >&2
  log "database ready"
}

app() {
  local image="${1:?image required}"
  local overlay="${STATE_DIR}/overlay"
  mkdir -p "${overlay}"
  cat >"${overlay}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../deploy/app
images:
  - name: ledger
    newName: ${image%%:*}
    newTag: ${image##*:}
YAML
  kubectl --context "${KUBE_CONTEXT}" apply -k "${overlay}" >/dev/null
  kc rollout status deployment/ledger --timeout=300s >&2
  log "ledger ${image} ready"
}

backups_on() {
  kc patch cronjob postgres-backup --type merge -p '{"spec":{"suspend":false}}' >/dev/null
  log "backup schedule enabled"
}

case "${1:-}" in
  data) data ;;
  app) shift; app "$@" ;;
  backups-on) backups_on ;;
  *) die "usage: deploy.sh data | app IMAGE | backups-on" ;;
esac
