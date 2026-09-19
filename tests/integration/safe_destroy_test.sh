#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export K3S_VM_LAB_HOME="${TMP_DIR}/home"
export HOME="${TMP_DIR}/user"
export PATH="${ROOT_DIR}/tests/mocks:${PATH}"
export K3S_VM_LAB_HOST_CPUS=16
export K3S_VM_LAB_HOST_MEM_GB=64
export K3S_VM_LAB_HOST_DISK_GB=500
export MOCK_MULTIPASS_LOG="${TMP_DIR}/multipass.log"
export MOCK_KUBECTL_LOG="${TMP_DIR}/kubectl.log"
export MOCK_SSH_LOG="${TMP_DIR}/ssh.log"
export NO_COLOR=1
mkdir -p "${HOME}/.kube"

printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"

{
  printf 'destroy-lab\n'
  printf '2\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >"${TMP_DIR}/build.out"

cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/destroy-lab"
index_file="${K3S_VM_LAB_HOME}/generated/clusters.tsv"
context="$(grep '^KUBE_CONTEXT=' "${cluster_dir}/cluster.env" | cut -d= -f2-)"

{
  printf 'y\n'
} | "${ROOT_DIR}/scripts/local-k3s" stop destroy-lab >"${TMP_DIR}/stop.out"

test -d "${cluster_dir}"
test -f "${index_file}"
grep -q "BUILD_STATUS=stopped" "${cluster_dir}/cluster.env"
grep -q "stop destroy-lab-server-1" "${MOCK_MULTIPASS_LOG}"
grep -q "stop destroy-lab-worker-1" "${MOCK_MULTIPASS_LOG}"
! grep -q "delete-context ${context}" "${MOCK_KUBECTL_LOG}"

before_status_get_nodes="$(grep -c 'get nodes -o wide' "${MOCK_KUBECTL_LOG}" || true)"
"${ROOT_DIR}/scripts/local-k3s" status >"${TMP_DIR}/status-list.out"
grep -q "destroy-lab.*stopped" "${TMP_DIR}/status-list.out"
after_status_get_nodes="$(grep -c 'get nodes -o wide' "${MOCK_KUBECTL_LOG}" || true)"
test "${before_status_get_nodes}" = "${after_status_get_nodes}"

printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" start destroy-lab >"${TMP_DIR}/start.out"

grep -q "BUILD_STATUS=ready" "${cluster_dir}/cluster.env"
grep -q "start destroy-lab-server-1" "${MOCK_MULTIPASS_LOG}"
grep -q "start destroy-lab-worker-1" "${MOCK_MULTIPASS_LOG}"
grep -q "Cluster 'destroy-lab' VM nodes are started" "${TMP_DIR}/start.out"

printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete destroy-lab >"${TMP_DIR}/delete-stopped.out"

test ! -e "${cluster_dir}"
grep -q "delete destroy-lab-server-1" "${MOCK_MULTIPASS_LOG}"
grep -q "delete destroy-lab-worker-1" "${MOCK_MULTIPASS_LOG}"
grep -q "purge" "${MOCK_MULTIPASS_LOG}"
grep -q "delete-context ${context}" "${MOCK_KUBECTL_LOG}"

{
  printf 'delete-lab\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >"${TMP_DIR}/delete-build.out"
delete_dir="${K3S_VM_LAB_HOME}/generated/clusters/delete-lab"
delete_context="$(grep '^KUBE_CONTEXT=' "${delete_dir}/cluster.env" | cut -d= -f2-)"

printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete delete-lab >"${TMP_DIR}/delete-ready.out"

test ! -e "${delete_dir}"
grep -q "delete delete-lab-server-1" "${MOCK_MULTIPASS_LOG}"
grep -q "delete-context ${delete_context}" "${MOCK_KUBECTL_LOG}"

{
  printf 'alias-lab\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >"${TMP_DIR}/alias-build.out"
alias_dir="${K3S_VM_LAB_HOME}/generated/clusters/alias-lab"

if "${ROOT_DIR}/scripts/local-k3s" destroy alias-lab >"${TMP_DIR}/destroy-alias.out" 2>&1; then
  echo "destroy alias unexpectedly succeeded" >&2
  exit 1
fi
test -e "${alias_dir}"
grep -q "Unknown command: destroy" "${TMP_DIR}/destroy-alias.out"
printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete alias-lab >"${TMP_DIR}/alias-delete.out"

test ! -e "${alias_dir}"
grep -q "Cluster 'alias-lab' deleted" "${TMP_DIR}/alias-delete.out"

legacy_dir="${K3S_VM_LAB_HOME}/generated/clusters/legacy-lab"
mkdir -p "${legacy_dir}"
cat > "${legacy_dir}/cluster.env" <<'EOF'
CLUSTER_NAME=legacy-lab
OS_VERSION=24.04
TOTAL_NODE_COUNT=1
WORKER_COUNT=0
RESOURCE_PROFILE=small
SERVER_NAME=legacy-lab-server-1
SERVER_IP=10.0.0.50
KUBE_CONTEXT=k3s-vm-lab-legacy-lab
KUBECONFIG_PATH=/tmp/legacy-kubeconfig
KUBECONFIG_BACKUP=none
FAKE_GPU_ENABLED=false
FAKE_GPU_STATUS=disabled
K3S_VERSION=unknown
BUILD_STATUS=ready
CREATED_AT=2026-01-01T00:00:00Z
EOF
printf 'legacy-lab-server-1\tserver\t10.0.0.50\t2\t2G\t20G\n' > "${legacy_dir}/nodes.tsv"

{
  printf 'y\n'
} | "${ROOT_DIR}/scripts/local-k3s" delete legacy-lab >"${TMP_DIR}/legacy-delete.out" 2>&1

test ! -e "${legacy_dir}"
grep -q "adopting legacy metadata" "${TMP_DIR}/legacy-delete.out"
grep -q "delete legacy-lab-server-1" "${MOCK_MULTIPASS_LOG}"

echo "safe destroy test passed"
