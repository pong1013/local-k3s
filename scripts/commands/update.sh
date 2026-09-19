#!/usr/bin/env bash

do_update() {
  if [[ "$#" -ne 0 ]]; then
    die "Usage: local-k3s update"
  fi

  command -v git >/dev/null 2>&1 || die "Git is required to update local-k3s."

  local install_dir="${K3S_VM_LAB_INSTALL_DIR:-${HOME}/.k3s-vm-lab}"
  if [[ ! -d "${install_dir}/.git" ]]; then
    die "No local-k3s installation checkout found at ${install_dir}. Install it first."
  fi

  local installed_revision remote_revision
  installed_revision="$(git -C "${install_dir}" rev-parse --verify HEAD^{commit})" || die "Could not read the installed revision."

  if ! git -C "${install_dir}" fetch origin +refs/heads/main:refs/remotes/origin/main; then
    die "Could not fetch remote main; local-k3s was not updated."
  fi
  remote_revision="$(git -C "${install_dir}" rev-parse --verify refs/remotes/origin/main^{commit})" || die "Could not read remote main revision."

  log_info "Installed revision: ${installed_revision}"
  log_info "Remote main revision: ${remote_revision}"

  if [[ "${installed_revision}" == "${remote_revision}" ]]; then
    log_success "local-k3s is up to date."
    return 0
  fi

  if ! git -C "${install_dir}" checkout -f -B main "${remote_revision}"; then
    die "Could not align the installation with remote main."
  fi
  if ! git -C "${install_dir}" reset --hard "${remote_revision}"; then
    die "Could not complete the update to remote main."
  fi

  local updated_revision
  updated_revision="$(git -C "${install_dir}" rev-parse --verify HEAD^{commit})" || die "Could not verify the updated revision."
  if [[ "${updated_revision}" != "${remote_revision}" ]]; then
    die "Updated revision does not match remote main."
  fi

  log_success "local-k3s updated to ${updated_revision}."
}
