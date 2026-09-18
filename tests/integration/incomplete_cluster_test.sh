#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export K3S_VM_LAB_HOME="${TMP_DIR}/home"
export HOME="${TMP_DIR}/user"
export PATH="${ROOT_DIR}/tests/mocks:${PATH}"

cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/stale-lab"
mkdir -p "${cluster_dir}"
touch "${cluster_dir}/build.log"

"${ROOT_DIR}/scripts/local-k3s" status >"${TMP_DIR}/status-list.out"
grep -q "stale-lab.*incomplete.*missing cluster.env" "${TMP_DIR}/status-list.out"

set +e
"${ROOT_DIR}/scripts/local-k3s" status stale-lab >"${TMP_DIR}/status.out" 2>&1
status=$?
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "expected incomplete status to fail" >&2
  exit 1
fi
grep -q "Cluster 'stale-lab' is incomplete" "${TMP_DIR}/status.out"

set +e
{
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create stale-lab >"${TMP_DIR}/build.out" 2>&1
status=$?
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "expected build to refuse incomplete directory" >&2
  exit 1
fi
grep -q "Cluster directory already exists" "${TMP_DIR}/build.out"

printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete stale-lab >"${TMP_DIR}/delete.out"
test ! -e "${cluster_dir}"

echo "incomplete cluster test passed"
