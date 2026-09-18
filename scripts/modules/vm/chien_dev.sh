#!/usr/bin/env bash

ensure_chien_dev() {
  require_command "chien-dev" "Install dev-environment-setup first; local-k3s uses chien-dev to create VM nodes."
}

ensure_multipass() {
  require_command "multipass" "Install Multipass first."
}

create_vm_node() {
  local name="$1"
  local os_version="$2"
  local cpus="$3"
  local memory="$4"
  local disk="$5"

  log_info "Creating VM node ${name} (${cpus} CPU, ${memory} RAM, ${disk} disk, Ubuntu ${os_version})"
  ENV=vm OS="${os_version}" VM_CPUS="${cpus}" VM_MEM="${memory}" VM_DISK="${disk}" chien-dev create "${name}"
}

vm_info() {
  local name="$1"
  multipass info "${name}"
}

vm_ip() {
  local name="$1"
  local ip=""

  if has_command jq; then
    ip="$(multipass info "${name}" --format json | jq -r ".info.\"${name}\".ipv4[0] // empty")"
  fi

  if [[ -z "${ip}" ]]; then
    ip="$(multipass info "${name}" | awk '/IPv4/{print $2; exit}')"
  fi

  [[ -n "${ip}" ]] || die "Could not determine IP for VM ${name}."
  echo "${ip}"
}

vm_state() {
  local name="$1"

  if has_command jq; then
    multipass info "${name}" --format json | jq -r ".info.\"${name}\".state // \"Unknown\""
  else
    multipass info "${name}" | awk -F': +' '/State/{print $2; exit}'
  fi
}

stop_vm_node() {
  local name="$1"
  if multipass info "${name}" >/dev/null 2>&1; then
    log_info "Stopping VM node ${name}"
    multipass stop "${name}"
  fi
}

start_vm_node() {
  local name="$1"
  if multipass info "${name}" >/dev/null 2>&1; then
    log_info "Starting VM node ${name}"
    multipass start "${name}"
  fi
}

delete_vm_node() {
  local name="$1"
  if multipass info "${name}" >/dev/null 2>&1; then
    log_info "Deleting VM node ${name}"
    multipass delete "${name}" >/dev/null 2>&1 || true
  fi
}

delete_vm_node_required() {
  local name="$1"
  if multipass info "${name}" >/dev/null 2>&1; then
    log_info "Deleting VM node ${name}"
    multipass delete "${name}" >/dev/null 2>&1
  fi
}

purge_deleted_vms() {
  multipass purge >/dev/null 2>&1 || true
}
