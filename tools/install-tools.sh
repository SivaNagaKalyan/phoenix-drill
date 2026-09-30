#!/usr/bin/env bash
# Install pinned CLI tools with checksum verification. Safe to re-run.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=versions.env
source "${ROOT}/tools/versions.env"

BIN="${TOOLS_BIN:-${HOME}/.local/bin}"
mkdir -p "${BIN}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

log() { printf '[install-tools] %s\n' "$*" >&2; }

have_version() { # binary, expected substring of its version output, version command...
  local bin="$1" want="$2"; shift 2
  [[ -x "${BIN}/${bin}" ]] && "${BIN}/${bin}" "$@" 2>/dev/null | grep -q -- "${want}"
}

verify() { # file, expected sha256
  local actual
  actual="$(sha256sum "$1" | awk '{print $1}')"
  [[ "${actual}" == "$2" ]] || { log "checksum mismatch for $1: got ${actual}, want $2"; exit 1; }
}

install_kind() {
  if have_version kind "${KIND_VERSION}" version; then log "kind ${KIND_VERSION} present"; return; fi
  local base="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${OS}-${ARCH}"
  curl -fsSL -o "${WORK}/kind" "${base}"
  verify "${WORK}/kind" "$(curl -fsSL "${base}.sha256sum" | awk '{print $1}')"
  install -m 0755 "${WORK}/kind" "${BIN}/kind"
  log "installed kind ${KIND_VERSION}"
}

install_kubectl() {
  if have_version kubectl "${KUBECTL_VERSION}" version --client; then log "kubectl ${KUBECTL_VERSION} present"; return; fi
  local base="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
  curl -fsSL -o "${WORK}/kubectl" "${base}"
  verify "${WORK}/kubectl" "$(curl -fsSL "${base}.sha256")"
  install -m 0755 "${WORK}/kubectl" "${BIN}/kubectl"
  log "installed kubectl ${KUBECTL_VERSION}"
}

install_kubeconform() {
  if have_version kubeconform "${KUBECONFORM_VERSION#v}" -v; then log "kubeconform ${KUBECONFORM_VERSION} present"; return; fi
  local base="https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}"
  local asset="kubeconform-${OS}-${ARCH}.tar.gz"
  curl -fsSL -o "${WORK}/${asset}" "${base}/${asset}"
  verify "${WORK}/${asset}" "$(curl -fsSL "${base}/CHECKSUMS" | awk -v a="${asset}" '$2 == a {print $1}')"
  tar -xzf "${WORK}/${asset}" -C "${WORK}" kubeconform
  install -m 0755 "${WORK}/kubeconform" "${BIN}/kubeconform"
  log "installed kubeconform ${KUBECONFORM_VERSION}"
}

install_kind
install_kubectl
install_kubeconform

for tool in docker jq curl; do
  command -v "${tool}" >/dev/null || log "WARNING: ${tool} not found; install it with your OS package manager"
done
case ":${PATH}:" in *":${BIN}:"*) ;; *) log "add ${BIN} to PATH" ;; esac
