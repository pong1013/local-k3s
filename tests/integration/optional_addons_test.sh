#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'status=$?; if (( status != 0 )); then cat "${TMP_DIR}"/*.out >&2; fi; rm -rf "${TMP_DIR}"' EXIT
export PATH="${ROOT_DIR}/tests/mocks:${PATH}"
export K3S_VM_LAB_HOST_CPUS=16 K3S_VM_LAB_HOST_MEM_GB=64 K3S_VM_LAB_HOST_DISK_GB=500
export MOCK_CHIEN_DEV_LOG="${TMP_DIR}/chien-dev.log"
export MOCK_HELM_LOG="${TMP_DIR}/helm.log" MOCK_KUBECTL_LOG="${TMP_DIR}/kubectl.log" MOCK_MULTIPASS_LOG="${TMP_DIR}/multipass.log"
prepare() {
  export K3S_VM_LAB_HOME="${TMP_DIR}/$1/lab"
  # Isolate the user's kubeconfig without changing the shell's HOME.
  export KUBECONFIG_TARGET="${TMP_DIR}/$1/kubeconfig"
  mkdir -p "${K3S_VM_LAB_HOME}"
  : > "$MOCK_CHIEN_DEV_LOG"; : > "$MOCK_HELM_LOG"; : > "$MOCK_KUBECTL_LOG"; : > "$MOCK_MULTIPASS_LOG"
  unset MOCK_CERT_MANAGER_FAIL MOCK_CERT_MANAGER_READINESS_FAIL
}
create() {
  local name="$1" answers="$2"
  printf '%s\n' "$name" 1 1 1 "$answers" | "${ROOT_DIR}/scripts/local-k3s" create > "${TMP_DIR}/${name}.out" 2>&1
  cluster_dir="${K3S_VM_LAB_HOME}/generated/clusters/${name}"
}
assert_status() { grep -q "^$1_STATUS=$2$" "${cluster_dir}/cluster.env"; }
prepare blank
create blank ''
assert_status FAKE_GPU disabled; assert_status MONITORING disabled; assert_status CERT_MANAGER disabled
test ! -s "$MOCK_HELM_LOG"
prepare cert
create cert 3
assert_status CERT_MANAGER installed; assert_status FAKE_GPU disabled; assert_status MONITORING disabled
grep -q '^CERT_MANAGER_ENABLED=true$' "${cluster_dir}/cluster.env"
grep -qi 'cert-manager: installed' "${cluster_dir}/report.md"
grep -q 'cert-manager' "$MOCK_HELM_LOG"
grep -Eq 'oci://quay.io/jetstack/charts/cert-manager|jetstack/cert-manager' "$MOCK_HELM_LOG"
grep -q -- '--namespace cert-manager' "$MOCK_HELM_LOG"
grep -Eq -- 'crds.enabled=true|installCRDs=true' "$MOCK_HELM_LOG"
grep -q -- '--wait' "$MOCK_HELM_LOG"
"${ROOT_DIR}/scripts/local-k3s" report cert > "${TMP_DIR}/cert-report.out"
grep -qi 'cert-manager:.*installed' "${TMP_DIR}/cert-report.out"
# Legacy cluster.env files must still be readable and report the new add-on disabled.
sed '/^CERT_MANAGER_/d' "${cluster_dir}/cluster.env" > "${cluster_dir}/legacy.env"
mv "${cluster_dir}/legacy.env" "${cluster_dir}/cluster.env"
"${ROOT_DIR}/scripts/local-k3s" report cert > "${TMP_DIR}/legacy-report.out"
grep -qi 'cert-manager:.*disabled' "${TMP_DIR}/legacy-report.out"
prepare duplicates
create duplicates '3 1 3 2 1'
assert_status FAKE_GPU installed; assert_status MONITORING installed; assert_status CERT_MANAGER installed
[[ $(grep -Ec '^upgrade .*cert-manager' "$MOCK_HELM_LOG") -eq 1 ]]
# Every invalid token rejects the entire answer, including an otherwise valid 1.
retry_number=0
for invalid in '1 4' '0' '01' '1;touch /tmp/unwanted' 'x'; do
  retry_number=$((retry_number + 1))
  prepare "retry-${retry_number}"
  create "retry-${retry_number}" "${invalid}
3"
  assert_status CERT_MANAGER installed; assert_status FAKE_GPU disabled; assert_status MONITORING disabled
done
prepare failure
export MOCK_CERT_MANAGER_FAIL=true
create failure 3
assert_status CERT_MANAGER failed
grep -q '^BUILD_STATUS=ready$' "${cluster_dir}/cluster.env"
test -f "${cluster_dir}/kubeconfig"
grep -qi 'cert-manager: failed' "${cluster_dir}/report.md"
grep -q 'mock cert-manager Helm failure' "${cluster_dir}/build.log"
grep -q -- '-n cert-manager get' "$MOCK_KUBECTL_LOG"
grep -qi 'cert-manager.*fail' "${TMP_DIR}/failure.out"
prepare readiness
export MOCK_CERT_MANAGER_READINESS_FAIL=true
create readiness 3
assert_status CERT_MANAGER failed
grep -q '^BUILD_STATUS=ready$' "${cluster_dir}/cluster.env"
grep -q 'mock cert-manager readiness failure' "${cluster_dir}/build.log"
grep -q -- '-n cert-manager get' "$MOCK_KUBECTL_LOG"
prepare eof
if printf '%s\n' eof 1 1 1 | "${ROOT_DIR}/scripts/local-k3s" create > "${TMP_DIR}/eof.out" 2>&1; then
  echo 'expected EOF to cancel create' >&2; exit 1
fi
test ! -s "$MOCK_MULTIPASS_LOG"
test ! -s "$MOCK_CHIEN_DEV_LOG"
prepare missing-helm
mkdir -p "${TMP_DIR}/no-helm"
for tool in chien-dev multipass kubectl ssh; do
  ln -s "${ROOT_DIR}/tests/mocks/${tool}" "${TMP_DIR}/no-helm/${tool}"
done
if printf '%s\n' missing-helm 1 1 1 3 | PATH="${TMP_DIR}/no-helm:/usr/bin:/bin:/usr/sbin:/sbin" "${ROOT_DIR}/scripts/local-k3s" create > "${TMP_DIR}/missing-helm.out" 2>&1; then
  echo 'expected missing Helm to fail' >&2; exit 1
fi
grep -q "Missing required command 'helm'" "${TMP_DIR}/missing-helm.out"
test ! -s "$MOCK_MULTIPASS_LOG"
test ! -s "$MOCK_CHIEN_DEV_LOG"
test ! -d "${K3S_VM_LAB_HOME}/generated/clusters/missing-helm"
echo 'optional add-ons test passed'
