#!/usr/bin/env bash

select_node_resources() {
  local node_name="$1"
  local label="$2"
  local choice

  echo ""
  paint bold "Resources for ${node_name} (${label})"
  echo ""
  choice="$(prompt_choice "Select resource size:" \
    "small - 2 CPU / 2G RAM / 20G disk" \
    "medium - 2 CPU / 4G RAM / 30G disk" \
    "large - 4 CPU / 8G RAM / 40G disk" \
    "custom - enter CPU, RAM, and disk")"

  case "${choice}" in
    small*)
      SELECTED_CPUS=2
      SELECTED_MEM="2G"
      SELECTED_DISK="20G"
      ;;
    medium*)
      SELECTED_CPUS=2
      SELECTED_MEM="4G"
      SELECTED_DISK="30G"
      ;;
    large*)
      SELECTED_CPUS=4
      SELECTED_MEM="8G"
      SELECTED_DISK="40G"
      ;;
    custom*)
      SELECTED_CPUS="$(prompt_text "${node_name} CPU cores" "2")"
      SELECTED_MEM="$(prompt_text "${node_name} memory" "4G")"
      SELECTED_DISK="$(prompt_text "${node_name} disk" "30G")"
      ;;
    *)
      die "Unknown resource choice: ${choice}"
      ;;
  esac

  validate_positive_int "${SELECTED_CPUS}" "${node_name} CPU cores"
  validate_size_gb "${SELECTED_MEM}" "${node_name} memory"
  validate_size_gb "${SELECTED_DISK}" "${node_name} disk"
}

collect_build_inputs() {
  local provided_name="$1"
  local os_choice
  local cluster_dir
  local i
  local node_name
  local role

  print_header
  echo "This command creates one fixed k3s control-plane/server VM plus optional worker VMs." >&2
  CLUSTER_NAME="${provided_name:-$(prompt_text "Cluster name" "demo-lab")}"
  validate_cluster_name "${CLUSTER_NAME}"

  cluster_dir="$(cluster_dir_for "${CLUSTER_NAME}")"
  if [[ -e "${cluster_dir}" ]]; then
    die "Cluster directory already exists: ${cluster_dir}. Refusing to create '${CLUSTER_NAME}'. Run 'local-k3s delete ${CLUSTER_NAME}' or clean up the stale directory before building again."
  fi

  if find_cluster_index_by_name "${CLUSTER_NAME}"; then
    if [[ ! -d "${INDEX_CLUSTER_DIR}" || "${INDEX_STATUS}" == "destroyed" || "${INDEX_STATUS}" == "stale" ]]; then
      log_warn "Cluster '${CLUSTER_NAME}' has a stale index entry with status '${INDEX_STATUS}'."
      if prompt_yes_no "Remove the stale index entry and continue?" "n"; then
        remove_cluster_index_entry "${CLUSTER_NAME}"
      else
        die "Build cancelled. Accept stale index cleanup for '${CLUSTER_NAME}' or choose another name."
      fi
    else
      die "Cluster '${CLUSTER_NAME}' is already recorded in $(cluster_index_file) with status '${INDEX_STATUS}' at ${INDEX_CLUSTER_DIR}. Delete it first or use another name."
    fi
  fi

  TOTAL_NODE_COUNT="$(prompt_text "Total node count, including the control-plane/server" "2")"
  validate_positive_int "${TOTAL_NODE_COUNT}" "Total node count"
  WORKER_COUNT=$(( TOTAL_NODE_COUNT - 1 ))

  os_choice="$(prompt_choice "Select Ubuntu version for all VM nodes:" "22.04" "24.04")"
  OS_VERSION="${os_choice}"

  print_host_capacity_summary
  RESOURCE_PROFILE="per-node"
  NODE_NAMES=()
  NODE_ROLES=()
  NODE_CPUS=()
  NODE_MEMS=()
  NODE_DISKS=()

  for ((i=0; i<TOTAL_NODE_COUNT; i++)); do
    if (( i == 0 )); then
      node_name="${CLUSTER_NAME}-server-1"
      role="server"
    else
      node_name="${CLUSTER_NAME}-worker-${i}"
      role="worker"
    fi
    select_node_resources "${node_name}" "${role}"
    NODE_NAMES+=("${node_name}")
    NODE_ROLES+=("${role}")
    NODE_CPUS+=("${SELECTED_CPUS}")
    NODE_MEMS+=("${SELECTED_MEM}")
    NODE_DISKS+=("${SELECTED_DISK}")
  done

  if prompt_yes_no "Install fake-gpu-operator after the cluster is ready?" "n"; then
    FAKE_GPU_ENABLED="true"
  else
    FAKE_GPU_ENABLED="false"
  fi
  FAKE_GPU_STATUS="disabled"
}

setup_build_logging() {
  local cluster_name="$1"
  local log_file
  log_file="$(log_file_for "${cluster_name}")"
  touch "${log_file}"
  exec 3>&1 4>&2
  K3S_VM_LAB_CONSOLE="true"
  log_info "Build log: ${log_file}"
  exec >> "${log_file}" 2>&1
}

progress_step() {
  log_console_step "$*"
  log_step "$*"
}

progress_success() {
  log_console_success "$*"
  log_success "$*"
}

do_build() {
  local provided_name="${1:-}"
  local cluster_dir
  local nodes_file
  local raw_kubeconfig
  local worker_name
  local worker_ip
  local token
  local i
  local node_name
  local role
  local cpus
  local memory
  local disk
  local ip
  local -a created_nodes=()

  ensure_chien_dev
  ensure_multipass
  require_command "ssh" "Install OpenSSH client."
  require_command "kubectl" "Install kubectl."

  collect_build_inputs "${provided_name}"
  if [[ "${FAKE_GPU_ENABLED}" == "true" ]]; then
    require_command "helm" "Install Helm before selecting fake-gpu-operator."
  fi
  ensure_node_capacity NODE_CPUS NODE_MEMS NODE_DISKS "${TOTAL_NODE_COUNT}"

  CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  CLUSTER_ID="$(generate_cluster_id)"
  SERVER_NAME="${CLUSTER_NAME}-server-1"
  SERVER_IP=""
  KUBE_CONTEXT="k3s-vm-lab-${CLUSTER_NAME}-${CLUSTER_ID}"
  KUBECONFIG_PATH="$(kubeconfig_file_for "${CLUSTER_NAME}")"
  KUBECONFIG_BACKUP="none"
  K3S_VERSION="unknown"
  BUILD_STATUS="in-progress"
  nodes_file="$(nodes_file_for "${CLUSTER_NAME}")"

  ensure_kube_context_is_available "${KUBE_CONTEXT}"

  cluster_dir="$(cluster_dir_for "${CLUSTER_NAME}")"
  ensure_cluster_dirs "${CLUSTER_NAME}"
  setup_build_logging "${CLUSTER_NAME}"

  : > "${nodes_file}"
  write_cluster_index_entry "${CLUSTER_ID}" "${CLUSTER_NAME}" "${KUBE_CONTEXT}" "${BUILD_STATUS}" "${cluster_dir}" "${CREATED_AT}"

  on_build_exit() {
    local status=$?
    trap - EXIT INT TERM
    if (( status == 0 )); then
      return 0
    fi
    BUILD_STATUS="failed"
    write_cluster_env "${CLUSTER_NAME}" || true
    update_cluster_index_status "${CLUSTER_NAME}" "${BUILD_STATUS}" || true
    render_report "${CLUSTER_NAME}" || true
    cleanup_created_nodes created_nodes
    log_console_error "Build failed. Log retained at $(log_file_for "${CLUSTER_NAME}")"
    log_error "Build failed. Log retained at $(log_file_for "${CLUSTER_NAME}")"
    exit "${status}"
  }
  trap on_build_exit EXIT
  trap 'exit 130' INT TERM

  progress_step "Creating control-plane VM ${SERVER_NAME}"
  create_vm_node "${SERVER_NAME}" "${OS_VERSION}" "${NODE_CPUS[0]}" "${NODE_MEMS[0]}" "${NODE_DISKS[0]}"
  created_nodes+=("${SERVER_NAME}")
  progress_step "Resolving IP for ${SERVER_NAME}"
  SERVER_IP="$(vm_ip "${SERVER_NAME}")"
  append_node_record "${CLUSTER_NAME}" "${SERVER_NAME}" "server" "${SERVER_IP}" "${NODE_CPUS[0]}" "${NODE_MEMS[0]}" "${NODE_DISKS[0]}"
  progress_step "Waiting for SSH on ${SERVER_NAME} (${SERVER_IP})"
  wait_for_ssh "${SERVER_IP}"
  progress_step "Installing k3s server on ${SERVER_NAME}"
  install_k3s_server "${SERVER_IP}" "${SERVER_NAME}"

  progress_step "Reading k3s join token"
  token="$(k3s_node_token "${SERVER_IP}")"

  for ((i=1; i<TOTAL_NODE_COUNT; i++)); do
    worker_name="${NODE_NAMES[i]}"
    progress_step "Creating worker VM ${worker_name}"
    create_vm_node "${worker_name}" "${OS_VERSION}" "${NODE_CPUS[i]}" "${NODE_MEMS[i]}" "${NODE_DISKS[i]}"
    created_nodes+=("${worker_name}")
    progress_step "Resolving IP for ${worker_name}"
    worker_ip="$(vm_ip "${worker_name}")"
    append_node_record "${CLUSTER_NAME}" "${worker_name}" "worker" "${worker_ip}" "${NODE_CPUS[i]}" "${NODE_MEMS[i]}" "${NODE_DISKS[i]}"
    progress_step "Waiting for SSH on ${worker_name} (${worker_ip})"
    wait_for_ssh "${worker_ip}"
    progress_step "Joining ${worker_name} to the k3s cluster"
    install_k3s_worker "${worker_ip}" "${worker_name}" "${SERVER_IP}" "${token}"
  done

  raw_kubeconfig="${cluster_dir}/k3s.raw.yaml"
  progress_step "Fetching kubeconfig from ${SERVER_NAME}"
  fetch_server_kubeconfig "${SERVER_IP}" "${raw_kubeconfig}"
  progress_step "Normalizing kubeconfig context ${KUBE_CONTEXT}"
  normalize_kubeconfig "${raw_kubeconfig}" "${KUBECONFIG_PATH}" "${SERVER_IP}" "${KUBE_CONTEXT}"
  progress_step "Waiting for Kubernetes nodes to become Ready"
  wait_for_nodes_ready "${KUBECONFIG_PATH}"

  if [[ "${FAKE_GPU_ENABLED}" == "true" ]]; then
    progress_step "Installing fake-gpu-operator"
    if install_fake_gpu_operator "${KUBECONFIG_PATH}" "${nodes_file}"; then
      FAKE_GPU_STATUS="installed"
    else
      FAKE_GPU_STATUS="failed"
      log_console_warn "fake-gpu-operator install failed; cluster will be kept. See $(log_file_for "${CLUSTER_NAME}") for pod diagnostics."
      log_warn "fake-gpu-operator install failed; continuing with cluster ready for debugging."
    fi
  fi

  progress_step "Merging kubeconfig into ${HOME}/.kube/config"
  KUBECONFIG_BACKUP="$(merge_kubeconfig "${KUBECONFIG_PATH}" "${KUBE_CONTEXT}")"
  progress_step "Reading k3s version"
  K3S_VERSION="$(k3s_version "${SERVER_IP}")"
  BUILD_STATUS="ready"
  progress_step "Writing cluster metadata and report"
  write_cluster_env "${CLUSTER_NAME}"
  update_cluster_index_status "${CLUSTER_NAME}" "${BUILD_STATUS}"
  render_report "${CLUSTER_NAME}"

  trap - EXIT INT TERM
  progress_success "Cluster ${CLUSTER_NAME} is ready."
  log_console_info "Report: $(report_file_for "${CLUSTER_NAME}")"
  log_info "Report: $(report_file_for "${CLUSTER_NAME}")"
}
