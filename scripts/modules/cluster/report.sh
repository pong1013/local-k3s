#!/usr/bin/env bash

write_cluster_env() {
  local cluster_name="$1"
  local env_file
  env_file="$(cluster_env_for "${cluster_name}")"

  {
    printf "CLUSTER_ID=%q\n" "${CLUSTER_ID}"
    printf "CLUSTER_NAME=%q\n" "${CLUSTER_NAME}"
    printf "OS_VERSION=%q\n" "${OS_VERSION}"
    printf "TOTAL_NODE_COUNT=%q\n" "${TOTAL_NODE_COUNT}"
    printf "WORKER_COUNT=%q\n" "${WORKER_COUNT}"
    printf "RESOURCE_PROFILE=%q\n" "${RESOURCE_PROFILE}"
    printf "SERVER_NAME=%q\n" "${SERVER_NAME}"
    printf "SERVER_IP=%q\n" "${SERVER_IP}"
    printf "KUBE_CONTEXT=%q\n" "${KUBE_CONTEXT}"
    printf "KUBECONFIG_PATH=%q\n" "${KUBECONFIG_PATH}"
    printf "KUBECONFIG_BACKUP=%q\n" "${KUBECONFIG_BACKUP}"
    printf "FAKE_GPU_ENABLED=%q\n" "${FAKE_GPU_ENABLED}"
    printf "FAKE_GPU_STATUS=%q\n" "${FAKE_GPU_STATUS}"
    printf "MONITORING_ENABLED=%q\n" "${MONITORING_ENABLED:-false}"
    printf "MONITORING_STATUS=%q\n" "${MONITORING_STATUS:-disabled}"
    printf "K3S_VERSION=%q\n" "${K3S_VERSION}"
    printf "BUILD_STATUS=%q\n" "${BUILD_STATUS}"
    printf "CREATED_AT=%q\n" "${CREATED_AT}"
  } > "${env_file}"
}

append_node_record() {
  local cluster_name="$1"
  local node_name="$2"
  local role="$3"
  local ip="$4"
  local cpus="$5"
  local memory="$6"
  local disk="$7"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${node_name}" "${role}" "${ip}" "${cpus}" "${memory}" "${disk}" >> "$(nodes_file_for "${cluster_name}")"
}

render_report() {
  local cluster_name="$1"
  local report_file
  local nodes_file
  local node_name
  local role
  local ip
  local cpus
  local memory
  local disk

  report_file="$(report_file_for "${cluster_name}")"
  nodes_file="$(nodes_file_for "${cluster_name}")"

  {
    echo "# local-k3s Report: ${CLUSTER_NAME}"
    echo ""
    echo "- Build status: ${BUILD_STATUS}"
    echo "- Cluster ID: ${CLUSTER_ID:-unknown}"
    echo "- Created at: ${CREATED_AT}"
    echo "- OS version: Ubuntu ${OS_VERSION}"
    echo "- Total nodes: ${TOTAL_NODE_COUNT}"
    echo "- Worker nodes: ${WORKER_COUNT}"
    echo "- Resource mode: ${RESOURCE_PROFILE}"
    echo "- k3s version: ${K3S_VERSION:-unknown}"
    echo "- Kube context: ${KUBE_CONTEXT}"
    echo "- Kubeconfig: ${HOME}/.kube/config"
    echo "- Kubeconfig backup: ${KUBECONFIG_BACKUP}"
    echo "- Local cluster kubeconfig copy: ${KUBECONFIG_PATH}"
    echo "- fake-gpu-operator: ${FAKE_GPU_STATUS}"
    echo "- Prometheus monitoring: ${MONITORING_STATUS:-disabled}"
    echo ""
    echo "## Nodes"
    echo ""
    echo "| Name | Role | IP | CPU | RAM | Disk |"
    echo "| --- | --- | --- | --- | --- | --- |"
    if [[ -f "${nodes_file}" ]]; then
      while IFS=$'\t' read -r node_name role ip cpus memory disk; do
        echo "| ${node_name} | ${role} | ${ip} | ${cpus} | ${memory} | ${disk} |"
      done < "${nodes_file}"
    fi
    echo ""
    echo "## Useful commands"
    echo ""
    echo '```bash'
    echo "kubectl config use-context ${KUBE_CONTEXT}"
    echo "kubectl get nodes -o wide"
    echo "kubectl get pods -A"
    echo "local-k3s status ${CLUSTER_NAME}"
    echo "local-k3s status ${CLUSTER_NAME} --wide"
    echo "local-k3s start ${CLUSTER_NAME}"
    echo "local-k3s stop ${CLUSTER_NAME}"
    echo "local-k3s delete ${CLUSTER_NAME}"
    echo '```'
  } > "${report_file}"
}

print_report_terminal() {
  local cluster_name="$1"
  local nodes_file
  local node_name
  local role
  local ip
  local cpus
  local memory
  local disk

  load_cluster_env "${cluster_name}"
  nodes_file="$(nodes_file_for "${cluster_name}")"

  paint bold "local-k3s report: ${CLUSTER_NAME}"
  echo ""
  paint bold "Overview"
  echo ""
  printf "%-18s %s\n" "Status:" "$(paint_status "${BUILD_STATUS}")"
  printf "%-18s %s\n" "Cluster ID:" "${CLUSTER_ID:-unknown}"
  printf "%-18s %s\n" "Created:" "${CREATED_AT}"
  printf "%-18s Ubuntu %s\n" "OS:" "${OS_VERSION}"
  printf "%-18s %s total / %s workers\n" "Nodes:" "${TOTAL_NODE_COUNT}" "${WORKER_COUNT}"
  printf "%-18s %s\n" "k3s:" "${K3S_VERSION:-unknown}"
  printf "%-18s %s\n" "fake GPU:" "$(paint_status "${FAKE_GPU_STATUS}")"
  printf "%-18s %s\n" "Monitoring:" "$(paint_status "${MONITORING_STATUS:-disabled}")"

  echo ""
  paint bold "Paths"
  echo ""
  printf "%-18s %s\n" "Context:" "${KUBE_CONTEXT}"
  printf "%-18s %s\n" "Kubeconfig:" "${HOME}/.kube/config"
  printf "%-18s %s\n" "Backup:" "${KUBECONFIG_BACKUP}"
  printf "%-18s %s\n" "Local copy:" "${KUBECONFIG_PATH}"

  echo ""
  paint bold "Nodes"
  echo ""
  printf "%-28s %-8s %-15s %-6s %-8s %-8s\n" "NAME" "ROLE" "IP" "CPU" "RAM" "DISK"
  printf "%-28s %-8s %-15s %-6s %-8s %-8s\n" "----------------------------" "--------" "---------------" "------" "--------" "--------"
  if [[ -f "${nodes_file}" ]]; then
    while IFS=$'\t' read -r node_name role ip cpus memory disk; do
      printf "%-28s %-8s %-15s %-6s %-8s %-8s\n" "${node_name}" "${role}" "${ip}" "${cpus}" "${memory}" "${disk}"
    done < "${nodes_file}"
  fi

  echo ""
  paint bold "Useful commands"
  echo ""
  paint bold "Daily"
  echo ""
  echo "kubectl config use-context ${KUBE_CONTEXT}"
  echo "local-k3s status ${CLUSTER_NAME}"
  echo "local-k3s status ${CLUSTER_NAME} wide"
  echo ""
  paint bold "Lifecycle"
  echo ""
  echo "local-k3s start ${CLUSTER_NAME}"
  echo "local-k3s stop ${CLUSTER_NAME}"
  echo "local-k3s delete ${CLUSTER_NAME}"
  echo ""
  paint bold "Raw diagnostics"
  echo ""
  echo "kubectl get nodes -o wide"
  echo "kubectl get pods -A"
  echo ""
  log_info "Markdown report: $(report_file_for "${cluster_name}")"
}
