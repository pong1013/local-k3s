#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "update test: $*" >&2
  exit 1
}

make_fixture() {
  local name="$1"
  local fixture="${TMP_DIR}/${name}"
  export HOME="${fixture}/home"
  export K3S_VM_LAB_REPO_URL="file://${fixture}/remote"
  unset K3S_VM_LAB_INSTALL_DIR
  mkdir -p "${HOME}" "${fixture}/remote"
  git -C "${fixture}/remote" init -q -b main
  tar -C "${ROOT_DIR}" -cf - install.sh scripts README.md | tar -C "${fixture}/remote" -xf -
  git -C "${fixture}/remote" add install.sh scripts README.md
  git -C "${fixture}/remote" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline
  bash "${ROOT_DIR}/install.sh" >"${fixture}/install.out" 2>&1
  [[ -L "${HOME}/.local/bin/local-k3s" ]] || fail "${name}: installer did not create CLI symlink"
}

remote_change() {
  local fixture="$1"
  printf '%s\n' "$2" >>"${fixture}/remote/README.md"
  git -C "${fixture}/remote" add README.md
  git -C "${fixture}/remote" -c user.name=Test -c user.email=test@example.invalid commit -qm "$2"
}

run_update() {
  local fixture="$1"
  "${HOME}/.local/bin/local-k3s" update >"${fixture}/update.out" 2>&1
}

# A matching remote revision must leave local tracked edits alone, since there
# is no update to apply.
make_fixture current
current="${TMP_DIR}/current"
before="$(git -C "${HOME}/.k3s-vm-lab" rev-parse HEAD)"
printf 'local note\n' >>"${HOME}/.k3s-vm-lab/README.md"
run_update "${current}" || fail 'current revision returned nonzero'
[[ "$(git -C "${HOME}/.k3s-vm-lab" rev-parse HEAD)" == "${before}" ]] || fail 'current revision changed HEAD'
grep -q 'local note' "${HOME}/.k3s-vm-lab/README.md" || fail 'current revision reset tracked edits'
grep -Eiq 'up.to.date|already current|no update' "${current}/update.out" || fail 'current revision not reported'

# A remote change replaces the installed revision and reports both revisions.
make_fixture newer
newer="${TMP_DIR}/newer"
installed_before="$(git -C "${HOME}/.k3s-vm-lab" rev-parse HEAD)"
remote_change "${newer}" 'remote update'
remote_head="$(git -C "${newer}/remote" rev-parse HEAD)"
run_update "${newer}" || fail 'newer remote revision returned nonzero'
[[ "$(git -C "${HOME}/.k3s-vm-lab" rev-parse HEAD)" == "${remote_head}" ]] || fail 'newer remote revision was not installed'
grep -q "${installed_before:0:7}" "${newer}/update.out" || fail 'installed revision not reported'
grep -q "${remote_head:0:7}" "${newer}/update.out" || fail 'remote revision not reported'

# Divergent local history and tracked edits are overwritten by remote main,
# while untracked generated cluster records survive.
make_fixture divergent
divergent="${TMP_DIR}/divergent"
checkout="${HOME}/.k3s-vm-lab"
printf 'local commit\n' >>"${checkout}/README.md"
git -C "${checkout}" add README.md
git -C "${checkout}" -c user.name=Test -c user.email=test@example.invalid commit -qm 'local divergent change'
printf 'uncommitted edit\n' >>"${checkout}/README.md"
mkdir -p "${checkout}/generated/clusters/old-lab"
printf 'existing cluster\n' >"${checkout}/generated/clusters/old-lab/cluster.env"
remote_change "${divergent}" 'remote divergent change'
remote_head="$(git -C "${divergent}/remote" rev-parse HEAD)"
run_update "${divergent}" || fail 'divergent remote revision returned nonzero'
[[ "$(git -C "${checkout}" rev-parse HEAD)" == "${remote_head}" ]] || fail 'divergent history was not aligned with remote main'
grep -q 'remote divergent change' "${checkout}/README.md" || fail 'remote tracked content missing'
! grep -q 'uncommitted edit' "${checkout}/README.md" || fail 'local tracked edit was not overwritten'
grep -q 'existing cluster' "${checkout}/generated/clusters/old-lab/cluster.env" || fail 'generated cluster data was lost'

# Fetch errors are visible and never claim a successful update.
make_fixture fetch_failure
failure="${TMP_DIR}/fetch_failure"
checkout="${HOME}/.k3s-vm-lab"
before="$(git -C "${checkout}" rev-parse HEAD)"
git -C "${checkout}" remote set-url origin "file://${failure}/missing-remote"
if run_update "${failure}"; then
  fail 'fetch failure returned success'
fi
[[ "$(git -C "${checkout}" rev-parse HEAD)" == "${before}" ]] || fail 'fetch failure changed installed revision'
! grep -Eiq 'up.to.date|updated successfully|already current' "${failure}/update.out" || fail 'fetch failure claimed success'

echo 'update test passed'
