#!/usr/bin/env bash

print_node_state_summary() {
  local nodes_file="$1"
  local title="${2:-Cluster nodes}"
  local node_name
  local role
  local ip
  local cpus
  local memory
  local disk
  local state

  paint bold "${title}"
  echo ""
  printf "%-28s %-8s %-12s %-15s %-6s %-8s %-8s\n" "NAME" "ROLE" "VM STATE" "IP" "CPU" "RAM" "DISK"
  printf "%-28s %-8s %-12s %-15s %-6s %-8s %-8s\n" "----------------------------" "--------" "------------" "---------------" "------" "--------" "--------"
  if [[ -f "${nodes_file}" ]]; then
    while IFS=$'\t' read -r node_name role ip cpus memory disk; do
      if multipass info "${node_name}" >/dev/null 2>&1; then
        state="$(vm_state "${node_name}")"
      else
        state="missing"
      fi
      printf "%-28s %-8s %-12s %-15s %-6s %-8s %-8s\n" "${node_name}" "${role}" "${state}" "${ip}" "${cpus}" "${memory}" "${disk}"
    done < "${nodes_file}"
  fi
}

adopt_legacy_cluster_index() {
  local cluster_name="$1"
  local cluster_dir="$2"
  local cluster_id

  load_cluster_env "${cluster_name}"

  if [[ "${CLUSTER_NAME}" != "${cluster_name}" ]]; then
    die "Cluster '${cluster_name}' has mismatched metadata name '${CLUSTER_NAME}'. Refusing to infer kubeconfig ownership."
  fi
  if [[ -z "${KUBE_CONTEXT:-}" || "${KUBE_CONTEXT}" != k3s-vm-lab-* ]]; then
    die "Cluster '${cluster_name}' is missing from $(cluster_index_file), and its kube context is not clearly managed by k3s-vm-lab. Refusing to delete."
  fi

  cluster_id="${CLUSTER_ID:-legacy}"
  if [[ "${cluster_id}" == "unknown" ]]; then
    cluster_id="legacy"
  fi
  CLUSTER_ID="${cluster_id}"

  log_warn "Cluster '${cluster_name}' is missing from $(cluster_index_file); adopting legacy metadata from cluster.env."
  write_cluster_index_entry "${cluster_id}" "${CLUSTER_NAME}" "${KUBE_CONTEXT}" "${BUILD_STATUS}" "${cluster_dir}" "${CREATED_AT}"
  write_cluster_env "${cluster_name}" || true
}

do_stop() {
  local cluster_name="${1:-}"
  local nodes_file
  local node_name
  local role
  local ip
  local cpus
  local memory
  local disk
  local cluster_dir
  local env_file

  if [[ -z "${cluster_name}" ]]; then
    die "Usage: local-k3s stop <cluster-name>"
  fi

  validate_cluster_name "${cluster_name}"
  cluster_dir="$(cluster_dir_for "${cluster_name}")"
  nodes_file="$(nodes_file_for "${cluster_name}")"
  env_file="$(cluster_env_for "${cluster_name}")"
  [[ -d "${cluster_dir}" ]] || die "Cluster '${cluster_name}' not found."

  [[ -f "${env_file}" ]] || die "Cluster '${cluster_name}' is incomplete: missing ${env_file}. Run 'local-k3s delete ${cluster_name}' to clean it."

  load_cluster_env "${cluster_name}"

  if [[ "${BUILD_STATUS}" == "stopped" || "${BUILD_STATUS}" == "destroy-stopped" ]]; then
    BUILD_STATUS="stopped"
    write_cluster_env "${cluster_name}"
    update_cluster_index_status "${cluster_name}" "${BUILD_STATUS}"
    render_report "${cluster_name}" || true
    log_info "Cluster '${cluster_name}' is already stopped."
    print_node_state_summary "${nodes_file}" "Stopped cluster nodes"
    return 0
  fi

  if ! prompt_yes_no "Stop cluster '${cluster_name}' VM nodes?" "n"; then
    log_info "Stop cancelled."
    return 0
  fi

  BUILD_STATUS="stopping"
  write_cluster_env "${cluster_name}"
  update_cluster_index_status "${cluster_name}" "${BUILD_STATUS}"
  render_report "${cluster_name}" || true

  if [[ -f "${nodes_file}" ]]; then
    while IFS=$'\t' read -r node_name role ip cpus memory disk; do
      stop_vm_node "${node_name}"
    done < "${nodes_file}"
  fi

  BUILD_STATUS="stopped"
  write_cluster_env "${cluster_name}"
  update_cluster_index_status "${cluster_name}" "${BUILD_STATUS}"
  render_report "${cluster_name}" || true
  log_success "Cluster '${cluster_name}' VM nodes are stopped."
  print_node_state_summary "${nodes_file}" "Stopped cluster nodes"
}

do_start() {
  local cluster_name="${1:-}"
  local nodes_file
  local node_name
  local role
  local ip
  local cpus
  local memory
  local disk
  local cluster_dir
  local env_file

  if [[ -z "${cluster_name}" ]]; then
    die "Usage: local-k3s start <cluster-name>"
  fi

  validate_cluster_name "${cluster_name}"
  cluster_dir="$(cluster_dir_for "${cluster_name}")"
  nodes_file="$(nodes_file_for "${cluster_name}")"
  env_file="$(cluster_env_for "${cluster_name}")"
  [[ -d "${cluster_dir}" ]] || die "Cluster '${cluster_name}' not found."
  [[ -f "${env_file}" ]] || die "Cluster '${cluster_name}' is incomplete: missing ${env_file}. Run 'local-k3s delete ${cluster_name}' to clean it."

  load_cluster_env "${cluster_name}"

  if [[ "${BUILD_STATUS}" == "ready" ]]; then
    log_info "Cluster '${cluster_name}' is already marked ready."
    print_node_state_summary "${nodes_file}" "Cluster nodes"
    return 0
  fi

  if ! prompt_yes_no "Start cluster '${cluster_name}' VM nodes?" "n"; then
    log_info "Start cancelled."
    return 0
  fi

  BUILD_STATUS="starting"
  write_cluster_env "${cluster_name}"
  update_cluster_index_status "${cluster_name}" "${BUILD_STATUS}"
  render_report "${cluster_name}" || true

  if [[ -f "${nodes_file}" ]]; then
    while IFS=$'\t' read -r node_name role ip cpus memory disk; do
      start_vm_node "${node_name}"
    done < "${nodes_file}"
  fi

  if [[ -n "${SERVER_IP:-}" ]]; then
    log_info "Waiting for SSH on ${SERVER_NAME} (${SERVER_IP})"
    wait_for_ssh "${SERVER_IP}"
  fi

  if [[ -f "${KUBECONFIG_PATH}" ]]; then
    log_info "Waiting for Kubernetes nodes to become Ready"
    wait_for_nodes_ready "${KUBECONFIG_PATH}"
  fi

  BUILD_STATUS="ready"
  write_cluster_env "${cluster_name}"
  update_cluster_index_status "${cluster_name}" "${BUILD_STATUS}"
  render_report "${cluster_name}" || true
  log_success "Cluster '${cluster_name}' VM nodes are started."
  print_node_state_summary "${nodes_file}" "Started cluster nodes"
}

do_delete() {
  local cluster_name="${1:-}"
  local nodes_file
  local node_name
  local role
  local ip
  local cpus
  local memory
  local disk
  local cluster_dir
  local env_file
  local delete_kube_context
  local kube_backup

  if [[ -z "${cluster_name}" ]]; then
    die "Usage: local-k3s delete <cluster-name>"
  fi

  validate_cluster_name "${cluster_name}"
  cluster_dir="$(cluster_dir_for "${cluster_name}")"
  nodes_file="$(nodes_file_for "${cluster_name}")"
  env_file="$(cluster_env_for "${cluster_name}")"
  [[ -d "${cluster_dir}" ]] || die "Cluster '${cluster_name}' not found."

  if [[ ! -f "${env_file}" ]]; then
    log_warn "Cluster '${cluster_name}' is incomplete: missing ${env_file}."
    if ! prompt_yes_no "Delete incomplete cluster '${cluster_name}' recorded VM nodes and generated files?" "n"; then
      log_info "Delete cancelled."
      return 0
    fi
    if [[ -f "${nodes_file}" ]]; then
      while IFS=$'\t' read -r node_name role ip cpus memory disk; do
        delete_vm_node_required "${node_name}"
      done < "${nodes_file}"
      purge_deleted_vms
    fi
    rm -rf "${cluster_dir}"
    remove_cluster_index_entry "${cluster_name}"
    log_success "Incomplete cluster '${cluster_name}' deleted."
    return 0
  fi

  if ! find_cluster_index_by_name "${cluster_name}"; then
    adopt_legacy_cluster_index "${cluster_name}" "${cluster_dir}"
    find_cluster_index_by_name "${cluster_name}" || die "Cluster '${cluster_name}' could not be added to $(cluster_index_file). Refusing to delete."
  fi
  delete_kube_context="${INDEX_KUBE_CONTEXT}"

  load_cluster_env "${cluster_name}"

  if ! prompt_yes_no "Permanently delete cluster '${cluster_name}' VM nodes, kubeconfig entries, index entry, and generated files?" "n"; then
    log_info "Delete cancelled."
    return 0
  fi

  BUILD_STATUS="deleting"
  write_cluster_env "${cluster_name}"
  update_cluster_index_status "${cluster_name}" "${BUILD_STATUS}"
  render_report "${cluster_name}" || true

  if [[ -f "${nodes_file}" ]]; then
    while IFS=$'\t' read -r node_name role ip cpus memory disk; do
      delete_vm_node_required "${node_name}"
    done < "${nodes_file}"
    purge_deleted_vms
  fi

  kube_backup="$(remove_kubeconfig_identity "${delete_kube_context}")"
  log_info "Kubeconfig backup: ${kube_backup}"
  remove_cluster_index_entry "${cluster_name}"
  rm -rf "${cluster_dir}"
  log_success "Cluster '${cluster_name}' deleted."
}
