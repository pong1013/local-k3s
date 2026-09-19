#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/helm" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_HELM_LOG}"
if [[ "${MOCK_MONITORING_FAIL:-false}" == true && "$*" == *kube-prometheus-stack* ]]; then
  echo 'mock monitoring Helm failure' >&2
  exit 1
fi
MOCK
chmod +x "${TMP_DIR}/bin/helm"
cat > "${TMP_DIR}/bin/multipass" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_MULTIPASS_COMMANDS}"
exec "${MOCK_MULTIPASS_DELEGATE}" "$@"
MOCK
chmod +x "${TMP_DIR}/bin/multipass"
cat > "${TMP_DIR}/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
if [[ "${MOCK_MONITORING_COMPLETED_JOB:-false}" == true && "$*" == *'-n monitoring get pods --no-headers'* ]]; then
  printf '%s\n' 'prometheus-0 2/2 Running'
  if [[ "$*" != *'--field-selector=status.phase!=Succeeded'* ]]; then
    printf '%s\n' 'monitoring-admission-create 0/1 Completed'
  fi
  exit 0
fi
if [[ "${MOCK_MONITORING_COMPLETED_JOB:-false}" == true && "$*" == *'-n monitoring wait'* && "$*" == *'pods --all'* && "$*" != *'--field-selector=status.phase!=Succeeded'* ]]; then
  echo 'timed out waiting for condition on pods/monitoring-admission-create' >&2
  exit 1
fi
exec "${MOCK_KUBECTL_DELEGATE}" "$@"
MOCK
chmod +x "${TMP_DIR}/bin/kubectl"

export PATH="${TMP_DIR}/bin:${ROOT_DIR}/tests/mocks:${PATH}"
export K3S_VM_LAB_HOST_CPUS=16
export K3S_VM_LAB_HOST_MEM_GB=64
export K3S_VM_LAB_HOST_DISK_GB=500
export MOCK_HELM_LOG="${TMP_DIR}/helm.log"
export MOCK_MULTIPASS_LOG="${TMP_DIR}/multipass.log"
export MOCK_MULTIPASS_COMMANDS="${TMP_DIR}/multipass-commands.log"
export MOCK_MULTIPASS_DELEGATE="${ROOT_DIR}/tests/mocks/multipass"
export MOCK_KUBECTL_DELEGATE="${ROOT_DIR}/tests/mocks/kubectl"

prepare_case() {
  local name="$1"
  export HOME="${TMP_DIR}/${name}/user"
  export K3S_VM_LAB_HOME="${TMP_DIR}/${name}/lab"
  mkdir -p "${HOME}/.kube" "${K3S_VM_LAB_HOME}/generated/clusters"
  printf 'apiVersion: v1\nkind: Config\n' > "${HOME}/.kube/config"
  : > "${MOCK_HELM_LOG}"
  : > "${MOCK_MULTIPASS_LOG}"
  : > "${MOCK_MULTIPASS_COMMANDS}"
  unset MOCK_MONITORING_FAIL
  unset MOCK_MONITORING_COMPLETED_JOB
}

create_case() {
  local name="$1"
  local gpu_answer="$2"
  local monitoring_answer="$3"
  local failure_answer="${4:-}"
  if {
    printf '%s\n' "$name" 1 1 1 "$gpu_answer" "$monitoring_answer"
    if [[ -n "$failure_answer" ]]; then
      printf '%s\n' "$failure_answer"
    fi
  } | "${ROOT_DIR}/scripts/local-k3s" create > "${TMP_DIR}/${name}.out" 2>&1; then
    [[ "$failure_answer" != n ]]
  else
    [[ "$failure_answer" == n ]]
  fi
}

prepare_case skipped
create_case skipped n n
cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/skipped"
grep -q '^MONITORING_STATUS=disabled$' "${cluster_dir}/cluster.env"
grep -qi 'monitoring: disabled' "${cluster_dir}/report.md"
test ! -s "${MOCK_HELM_LOG}"
"${ROOT_DIR}/scripts/local-k3s" report skipped > "${TMP_DIR}/skipped-report.out"
grep -qi 'monitoring:.*disabled' "${TMP_DIR}/skipped-report.out"

prepare_case installed
create_case installed n y
cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/installed"
grep -q '^MONITORING_STATUS=installed$' "${cluster_dir}/cluster.env"
grep -qi 'monitoring: installed' "${cluster_dir}/report.md"
grep -q 'kube-prometheus-stack' "${MOCK_HELM_LOG}"
grep -q -- '--namespace monitoring' "${MOCK_HELM_LOG}"
"${ROOT_DIR}/scripts/local-k3s" report installed > "${TMP_DIR}/installed-report.out"
grep -qi 'monitoring:.*installed' "${TMP_DIR}/installed-report.out"

# Installing monitoring must not switch on fake GPU.
! grep -q 'fake-gpu-operator' "${MOCK_HELM_LOG}"
grep -q '^FAKE_GPU_STATUS=disabled$' "${cluster_dir}/cluster.env"

prepare_case completed-job
export MOCK_MONITORING_COMPLETED_JOB=true
create_case completed-job n y
cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/completed-job"
grep -q '^MONITORING_STATUS=installed$' "${cluster_dir}/cluster.env"
grep -qi 'monitoring: installed' "${cluster_dir}/report.md"

prepare_case keep
export MOCK_MONITORING_FAIL=true
create_case keep n y ''
cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/keep"
grep -q '^BUILD_STATUS=ready$' "${cluster_dir}/cluster.env"
grep -q '^MONITORING_STATUS=failed$' "${cluster_dir}/cluster.env"
grep -qi 'monitoring: failed' "${cluster_dir}/report.md"
grep -q 'mock monitoring Helm failure' "${cluster_dir}/build.log"
grep -Eqi 'keep.*cluster|delete.*cluster' "${TMP_DIR}/keep.out"
test -f "${cluster_dir}/kubeconfig"

prepare_case removed
export MOCK_MONITORING_FAIL=true
mkdir -p "${K3S_VM_LAB_HOME}/generated/clusters/unrelated"
printf 'sentinel\n' > "${K3S_VM_LAB_HOME}/generated/clusters/unrelated/sentinel"
create_case removed n y n
test ! -d "${K3S_VM_LAB_HOME}/generated/clusters/removed"
test -f "${K3S_VM_LAB_HOME}/generated/clusters/unrelated/sentinel"
! grep -q $'\tremoved\t' "${K3S_VM_LAB_HOME}/generated/clusters.tsv" 2>/dev/null
grep -Eq '^delete (.* )?removed-server-1$' "${MOCK_MULTIPASS_COMMANDS}"
! grep -Eq '^delete .*unrelated|^purge$' "${MOCK_MULTIPASS_COMMANDS}"

echo 'monitoring test passed'
