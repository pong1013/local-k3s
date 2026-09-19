#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
export PATH="${ROOT_DIR}/tests/mocks:${PATH}"
export K3S_VM_LAB_REPO_URL="file://${TMP_DIR}/source"
export K3S_VM_LAB_HOST_CPUS=16
export K3S_VM_LAB_HOST_MEM_GB=64
export K3S_VM_LAB_HOST_DISK_GB=500
export NO_COLOR=1

mkdir -p "${HOME}/.local/bin" "${TMP_DIR}/source" "${TMP_DIR}/unrelated"
git -C "${TMP_DIR}/source" init -q -b main
tar -C "${ROOT_DIR}" -cf - install.sh scripts README.md | tar -C "${TMP_DIR}/source" -xf -
git -C "${TMP_DIR}/source" add install.sh scripts README.md
git -C "${TMP_DIR}/source" -c user.name='Test' -c user.email='test@example.invalid' commit -qm 'local installer fixture'

touch "${TMP_DIR}/unrelated/k3s-vm-lab"
ln -s "${TMP_DIR}/unrelated/k3s-vm-lab" "${HOME}/.local/bin/k3s-vm-lab"
cat "${ROOT_DIR}/install.sh" | bash >"${TMP_DIR}/install.out" 2>&1

install_dir="${HOME}/.k3s-vm-lab"
command_path="${HOME}/.local/bin/local-k3s"
test -d "${install_dir}/.git"
test -L "${command_path}"
test "$(readlink "${command_path}")" = "${install_dir}/scripts/local-k3s"
test -L "${HOME}/.local/bin/k3s-vm-lab"
test "$(readlink "${HOME}/.local/bin/k3s-vm-lab")" = "${TMP_DIR}/unrelated/k3s-vm-lab"

"${command_path}" help >"${TMP_DIR}/help.out"
grep -q 'local-k3s create' "${TMP_DIR}/help.out"
if "${command_path}" build old-name >"${TMP_DIR}/old-command.out" 2>&1; then
  echo 'old build command unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Unknown command: build' "${TMP_DIR}/old-command.out"
test ! -e "${install_dir}/scripts/k3s-vm-lab"
test ! -L "${install_dir}/scripts/k3s-vm-lab"

mkdir -p "${install_dir}/generated/clusters/old-lab" "${HOME}/.kube"
cat >"${install_dir}/generated/clusters/old-lab/cluster.env" <<'EOF'
CLUSTER_NAME=old-lab
BUILD_STATUS=stopped
TOTAL_NODE_COUNT=1
WORKER_COUNT=0
KUBE_CONTEXT=k3s-vm-lab-old-lab-existing
EOF
printf 'existing kubeconfig\n' >"${HOME}/.kube/config"
ln -s "${install_dir}/scripts/k3s-vm-lab" "${TMP_DIR}/managed-link"
mv "${TMP_DIR}/managed-link" "${HOME}/.local/bin/k3s-vm-lab"

cat "${ROOT_DIR}/install.sh" | bash >"${TMP_DIR}/reinstall.out" 2>&1
test ! -e "${HOME}/.local/bin/k3s-vm-lab"
test ! -L "${HOME}/.local/bin/k3s-vm-lab"
test -f "${install_dir}/generated/clusters/old-lab/cluster.env"
grep -q 'existing kubeconfig' "${HOME}/.kube/config"
"${command_path}" status >"${TMP_DIR}/status.out"
grep -q 'old-lab.*stopped' "${TMP_DIR}/status.out"

{
  printf '1\n'
  printf '1\n'
  printf '1\n'
  printf 'n\n'
} | "${command_path}" create new-lab >"${TMP_DIR}/create.out" 2>&1
test -f "${install_dir}/generated/clusters/new-lab/cluster.env"
grep -q '^BUILD_STATUS=ready$' "${install_dir}/generated/clusters/new-lab/cluster.env"
"${command_path}" status >"${TMP_DIR}/status-after-create.out"
grep -q 'old-lab.*stopped' "${TMP_DIR}/status-after-create.out"
grep -q 'new-lab.*ready' "${TMP_DIR}/status-after-create.out"

echo 'global CLI test passed'
