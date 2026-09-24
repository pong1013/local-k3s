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
export MOCK_FAKE_GPU_ROLLOUT_FAIL=true
export MOCK_HELM_LOG="${TMP_DIR}/helm.log"
mkdir -p "${HOME}/.kube"

printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"

{
  printf 'gpu-fail-lab\n'
  printf '2\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'y\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >"${TMP_DIR}/build.out" 2>&1

cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/gpu-fail-lab"

test -f "${cluster_dir}/cluster.env"
test -f "${cluster_dir}/build.log"
grep -q "BUILD_STATUS=ready" "${cluster_dir}/cluster.env"
grep -q "FAKE_GPU_STATUS=failed" "${cluster_dir}/cluster.env"
grep -q "fake-gpu-operator: failed" "${cluster_dir}/report.md"
grep -q "fake-gpu-operator install failed; cluster will be kept" "${TMP_DIR}/build.out"
grep -q -- "--set runtimeClass.enabled=false" "${MOCK_HELM_LOG}"
grep -q "mock fake-gpu deployment rollout failure" "${cluster_dir}/build.log"
grep -q "Name: fake-gpu-mock" "${cluster_dir}/build.log"

echo "fake gpu failure test passed"
