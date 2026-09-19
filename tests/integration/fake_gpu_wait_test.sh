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
export MOCK_FAKE_GPU_PODS_DELAY=true
export MOCK_FAKE_GPU_COUNTER_FILE="${TMP_DIR}/fake-gpu-counter"
mkdir -p "${HOME}/.kube"

printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"

{
  printf 'gpu-wait-lab\n'
  printf '2\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'y\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >"${TMP_DIR}/build.out" 2>&1

cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/gpu-wait-lab"

grep -q "BUILD_STATUS=ready" "${cluster_dir}/cluster.env"
grep -q "FAKE_GPU_STATUS=installed" "${cluster_dir}/cluster.env"
grep -q "fake-gpu-operator: installed" "${cluster_dir}/report.md"
grep -q "Waiting for fake-gpu-operator pods to be created" "${cluster_dir}/build.log"
grep -q "Waiting for fake-gpu-operator deployments" "${cluster_dir}/build.log"
grep -q "Waiting for fake-gpu-operator daemonsets" "${cluster_dir}/build.log"
grep -q "Waiting for fake-gpu-operator pods to become Ready" "${cluster_dir}/build.log"

echo "fake gpu wait test passed"
