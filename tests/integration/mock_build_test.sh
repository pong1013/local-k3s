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
mkdir -p "${HOME}/.kube"

printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"

{
  printf 'mock-lab\n'
  printf '3\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >/tmp/k3s-vm-lab-test.out

test -f "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/report.md"
test -f "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/kubeconfig"
test -f "${HOME}/.kube/config"
grep -q "Build status: ready" "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/report.md"
grep -q "Total nodes: 3" "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/report.md"
grep -q "mock-lab-server-1" "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/report.md"
grep -q "mock-lab-worker-1" "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/report.md"
grep -q "mock-lab-worker-2" "${K3S_VM_LAB_HOME}/generated/clusters/mock-lab/report.md"
grep -q "step: Creating control-plane VM mock-lab-server-1" /tmp/k3s-vm-lab-test.out

echo "mock build test passed"
