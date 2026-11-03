#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export K3S_VM_LAB_HOME="${TMP_DIR}/lab"
export HOME="${TMP_DIR}/user"
export PATH="${ROOT_DIR}/tests/mocks:${PATH}"
export MOCK_CHIEN_DEV_LOG="${TMP_DIR}/chien-dev.log"
export MOCK_MULTIPASS_LOG="${TMP_DIR}/multipass.log"
export MOCK_VM_STATE_DIR="${TMP_DIR}/vms"
export MOCK_LIFECYCLE_LOG="${TMP_DIR}/lifecycle.log"
mkdir -p "${HOME}/.kube" "${MOCK_VM_STATE_DIR}"
printf 'kubeconfig sentinel\n' > "${HOME}/.kube/config"

cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/cleanup-lab"
mkdir -p "${cluster_dir}"
printf 'cleanup-lab-server-1\tserver\t10.0.0.1\t2\t2G\t20G\n' > "${cluster_dir}/nodes.tsv"
printf 'Running\n' > "${MOCK_VM_STATE_DIR}/cleanup-lab-server-1"
printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete cleanup-lab > "${TMP_DIR}/delete.out" 2>&1

test ! -e "${cluster_dir}"
grep -qx 'clean cleanup-lab-server-1' "${MOCK_CHIEN_DEV_LOG}"
test ! -e "${MOCK_VM_STATE_DIR}/cleanup-lab-server-1"
! grep -Eq '^(delete|purge)( |$)' "${MOCK_MULTIPASS_LOG}"
printf '%s\n' 'multipass stop cleanup-lab-server-1' 'chien-dev clean cleanup-lab-server-1' > "${TMP_DIR}/expected.log"
cmp "${TMP_DIR}/expected.log" "${MOCK_LIFECYCLE_LOG}"

# The remaining cases use real CLI creation to exercise complete cluster metadata.
export K3S_VM_LAB_HOST_CPUS=16
export K3S_VM_LAB_HOST_MEM_GB=64
export K3S_VM_LAB_HOST_DISK_GB=500
export MOCK_KUBECTL_LOG="${TMP_DIR}/kubectl.log"

prepare_case() {
  local name="$1"
  export K3S_VM_LAB_HOME="${TMP_DIR}/${name}/lab"
  export HOME="${TMP_DIR}/${name}/user"
  export MOCK_VM_STATE_DIR="${TMP_DIR}/${name}/vms"
  mkdir -p "${HOME}/.kube" "${MOCK_VM_STATE_DIR}"
  printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"
  : > "${MOCK_CHIEN_DEV_LOG}"
  : > "${MOCK_MULTIPASS_LOG}"
  : > "${MOCK_LIFECYCLE_LOG}"
  : > "${MOCK_KUBECTL_LOG}"
  unset MOCK_FAIL_STOP_NODE MOCK_FAIL_CLEAN_NODE MOCK_FAIL_WORKER_INSTALL MOCK_FAIL_IP_NODE
  cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/${name}"
}

create_cluster() {
  local name="$1"
  printf '%s\n' "${name}" 2 1 1 1 '' | "${ROOT_DIR}/scripts/local-k3s" create > "${TMP_DIR}/${name}-create.out" 2>&1
}

# Missing VM records still go through clean, without trying to stop them.
prepare_case missing
create_cluster missing
rm "${MOCK_VM_STATE_DIR}/missing-worker-1"
: > "${MOCK_CHIEN_DEV_LOG}"
printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete missing > "${TMP_DIR}/missing-delete.out" 2>&1
grep -qx 'clean missing-worker-1' "${MOCK_CHIEN_DEV_LOG}"
! grep -q 'stop missing-worker-1' "${MOCK_MULTIPASS_LOG}"
test ! -d "${cluster_dir}"

# Both kinds of node failure preserve complete metadata and permit retry.
for failure in stop clean; do
  name="${failure}-failure"
  prepare_case "${name}"
  create_cluster "${name}"
  cp "${HOME}/.kube/config" "${TMP_DIR}/before-kubeconfig"
  cp "${cluster_dir}/nodes.tsv" "${TMP_DIR}/before-nodes"
  : > "${MOCK_CHIEN_DEV_LOG}"
  : > "${MOCK_KUBECTL_LOG}"
  if [[ "${failure}" == stop ]]; then
    export MOCK_FAIL_STOP_NODE="${name}-server-1"
  else
    export MOCK_FAIL_CLEAN_NODE="${name}-server-1"
  fi
  if printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete "${name}" > "${TMP_DIR}/${name}-delete.out" 2>&1; then
    echo "expected ${failure} failure to fail cluster deletion" >&2
    exit 1
  fi
  test -f "${cluster_dir}/cluster.env"
  cmp "${TMP_DIR}/before-nodes" "${cluster_dir}/nodes.tsv"
  cmp "${TMP_DIR}/before-kubeconfig" "${HOME}/.kube/config"
  grep -q "${name}" "${K3S_VM_LAB_HOME}/generated/clusters.tsv"
  ! grep -q 'delete-context' "${MOCK_KUBECTL_LOG}"
  grep -qx "clean ${name}-worker-1" "${MOCK_CHIEN_DEV_LOG}"
  test ! -e "${MOCK_VM_STATE_DIR}/${name}-worker-1"
  test -f "${MOCK_VM_STATE_DIR}/${name}-server-1"
  if [[ "${failure}" == stop ]]; then
    ! grep -qx "clean ${name}-server-1" "${MOCK_CHIEN_DEV_LOG}"
  fi
  ! grep -Eq '^(delete|purge)( |$)' "${MOCK_MULTIPASS_LOG}"
  unset MOCK_FAIL_STOP_NODE MOCK_FAIL_CLEAN_NODE
  printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete "${name}" > "${TMP_DIR}/${name}-retry.out" 2>&1
  test ! -d "${cluster_dir}"
  test ! -e "${MOCK_VM_STATE_DIR}/${name}-server-1"
  grep -q 'delete-context' "${MOCK_KUBECTL_LOG}"
done

# Incomplete cluster deletion has the same continue-and-retry behavior.
prepare_case incomplete
mkdir -p "${cluster_dir}"
printf 'incomplete-server-1\tserver\t10.0.0.1\t2\t2G\t20G\nincomplete-worker-1\tworker\t10.0.0.2\t2\t2G\t20G\n' > "${cluster_dir}/nodes.tsv"
printf 'Running\n' > "${MOCK_VM_STATE_DIR}/incomplete-server-1"
printf 'Running\n' > "${MOCK_VM_STATE_DIR}/incomplete-worker-1"
export MOCK_FAIL_CLEAN_NODE=incomplete-server-1
if printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete incomplete > "${TMP_DIR}/incomplete-delete.out" 2>&1; then
  echo 'expected incomplete deletion to fail' >&2
  exit 1
fi
test -f "${cluster_dir}/nodes.tsv"
grep -qx 'clean incomplete-worker-1' "${MOCK_CHIEN_DEV_LOG}"
unset MOCK_FAIL_CLEAN_NODE
printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete incomplete > "${TMP_DIR}/incomplete-retry.out" 2>&1
test ! -d "${cluster_dir}"

# A failed build retains recovery records if its cleanup also fails.
prepare_case rollback
export MOCK_FAIL_WORKER_INSTALL=true
export MOCK_FAIL_CLEAN_NODE=rollback-server-1
if create_cluster rollback; then
  echo 'expected worker installation failure' >&2
  exit 1
fi
grep -qx 'clean rollback-worker-1' "${MOCK_CHIEN_DEV_LOG}"
test -f "${cluster_dir}/cluster.env"
test -f "${cluster_dir}/nodes.tsv"
test -f "${cluster_dir}/build.log"
unset MOCK_FAIL_WORKER_INSTALL MOCK_FAIL_CLEAN_NODE
printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete rollback > "${TMP_DIR}/rollback-retry.out" 2>&1
test ! -d "${cluster_dir}"

# An IP lookup failure must not leave a created VM outside retry records.
prepare_case no-ip
export MOCK_FAIL_IP_NODE=no-ip-server-1
export MOCK_FAIL_CLEAN_NODE=no-ip-server-1
if create_cluster no-ip; then
  echo 'expected IP lookup failure' >&2
  exit 1
fi
grep -q $'^no-ip-server-1\tserver\tN/A\t' "${cluster_dir}/nodes.tsv"
test -f "${MOCK_VM_STATE_DIR}/no-ip-server-1"
unset MOCK_FAIL_IP_NODE MOCK_FAIL_CLEAN_NODE
printf 'y\n' | "${ROOT_DIR}/scripts/local-k3s" delete no-ip > "${TMP_DIR}/no-ip-retry.out" 2>&1
test ! -d "${cluster_dir}"
test ! -e "${MOCK_VM_STATE_DIR}/no-ip-server-1"

echo 'chien-dev cleanup test passed'
