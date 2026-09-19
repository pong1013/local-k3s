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
export MOCK_FAIL_WORKER_INSTALL=true
mkdir -p "${HOME}/.kube"

set +e
{
  printf 'fail-lab\n'
  printf '2\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create >/tmp/k3s-vm-lab-failure-test.out 2>&1
status=$?
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "expected build to fail" >&2
  exit 1
fi

grep -q "delete fail-lab-server-1" "${MOCK_MULTIPASS_LOG}"
grep -q "delete fail-lab-worker-1" "${MOCK_MULTIPASS_LOG}"
grep -q "purge" "${MOCK_MULTIPASS_LOG}"
test -f "${K3S_VM_LAB_HOME}/generated/clusters/fail-lab/build.log"
grep -q "Build status: failed" "${K3S_VM_LAB_HOME}/generated/clusters/fail-lab/report.md"

echo "mock failure cleanup test passed"
