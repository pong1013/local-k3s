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
export K3S_VM_LAB_CLUSTER_ID="abcd1234"
export MOCK_KUBECTL_LOG="${TMP_DIR}/kubectl.log"
export MOCK_MULTIPASS_LOG="${TMP_DIR}/multipass.log"
export NO_COLOR=1

mkdir -p "${HOME}/.kube"
printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"

{
  printf '2\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create indexed-lab >"${TMP_DIR}/build.out"

index_file="${K3S_VM_LAB_HOME}/generated/clusters.tsv"
cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/indexed-lab"
context="k3s-vm-lab-indexed-lab-abcd1234"

grep -q $'abcd1234\tindexed-lab\tk3s-vm-lab-indexed-lab-abcd1234\tready' "${index_file}"
grep -q "CLUSTER_ID=abcd1234" "${cluster_dir}/cluster.env"
grep -q "KUBE_CONTEXT=${context}" "${cluster_dir}/cluster.env"

set +e
"${ROOT_DIR}/scripts/local-k3s" create indexed-lab >"${TMP_DIR}/build-again.out" 2>&1
status=$?
set -e
if [[ "${status}" -eq 0 ]]; then
  echo "expected build to refuse existing cluster dir" >&2
  exit 1
fi
grep -q "Cluster directory already exists" "${TMP_DIR}/build-again.out"

{
  printf 'y\n'
  printf 'y\n'
} | "${ROOT_DIR}/scripts/local-k3s" delete indexed-lab >"${TMP_DIR}/delete.out"

test ! -e "${cluster_dir}"
test ! -e "${index_file}"
grep -q "delete-context ${context}" "${MOCK_KUBECTL_LOG}"
grep -q "delete-cluster ${context}" "${MOCK_KUBECTL_LOG}"
grep -q "delete-user ${context}" "${MOCK_KUBECTL_LOG}"
ls "${HOME}/.kube"/config.k3s-vm-lab.*.bak >/dev/null

mkdir -p "$(dirname "${index_file}")"
printf 'staleid\tstale-lab\tk3s-vm-lab-stale-lab-staleid\tstale\t%s\t2026-01-01T00:00:00Z\n' "${K3S_VM_LAB_HOME}/generated/clusters/stale-lab" > "${index_file}"
export K3S_VM_LAB_CLUSTER_ID="feed9876"
{
  printf 'y\n'
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create stale-lab >"${TMP_DIR}/stale-build.out"
grep -q $'feed9876\tstale-lab\tk3s-vm-lab-stale-lab-feed9876\tready' "${index_file}"

export K3S_VM_LAB_CLUSTER_ID="9999aaaa"
export MOCK_KUBECTL_CONTEXTS="k3s-vm-lab-blocked-lab-9999aaaa"
set +e
{
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${ROOT_DIR}/scripts/local-k3s" create blocked-lab >"${TMP_DIR}/blocked.out" 2>&1
status=$?
set -e
if [[ "${status}" -eq 0 ]]; then
  echo "expected build to refuse unmanaged kube context" >&2
  exit 1
fi
grep -q "is not managed by k3s-vm-lab" "${TMP_DIR}/blocked.out"

echo "cluster index test passed"
