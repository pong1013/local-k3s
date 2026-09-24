#!/usr/bin/env bash

capture_monitoring_diagnostics() {
  local kubeconfig="$1"
  log_warn "Prometheus monitoring did not become Ready. Capturing diagnostics."
  kubectl --kubeconfig "${kubeconfig}" -n monitoring get pods -o wide || true
  kubectl --kubeconfig "${kubeconfig}" -n monitoring get deployments -o wide || true
  kubectl --kubeconfig "${kubeconfig}" -n monitoring get statefulsets -o wide || true
  kubectl --kubeconfig "${kubeconfig}" -n monitoring get events --sort-by=.lastTimestamp || true
  kubectl --kubeconfig "${kubeconfig}" -n monitoring describe pods || true
}

install_monitoring_stack() {
  local kubeconfig="$1"
  local active_pods='status.phase!=Succeeded'

  if ! helm upgrade --install kube-prometheus-stack kube-prometheus-stack \
    --repo https://prometheus-community.github.io/helm-charts \
    --namespace monitoring --create-namespace --wait --timeout 10m \
    --kubeconfig "${kubeconfig}"; then
    capture_monitoring_diagnostics "${kubeconfig}"
    return 1
  fi

  if ! kubectl --kubeconfig "${kubeconfig}" -n monitoring get pods --no-headers \
    --field-selector="${active_pods}" | grep -q .; then
    log_warn "No active monitoring pods were created."
    capture_monitoring_diagnostics "${kubeconfig}"
    return 1
  fi

  if ! kubectl --kubeconfig "${kubeconfig}" -n monitoring wait \
    --for=condition=Ready pods --all --field-selector="${active_pods}" --timeout=600s; then
    capture_monitoring_diagnostics "${kubeconfig}"
    return 1
  fi
}

# Build output is redirected to build.log; ask through the original console.
prompt_keep_cluster_after_monitoring_failure() {
  local answer
  console_err_printf "Keep the newly created cluster despite monitoring failure? [Y/n]: "
  if ! IFS= read -r answer; then
    answer=""
  fi
  [[ ! "${answer}" =~ ^[Nn]$ ]]
}

delete_new_cluster_after_monitoring_failure() {
  local array_name="$1"
  local cluster_dir="$2"
  local node
  local failed=0
  local -a nodes=()
  eval "nodes=(\"\${${array_name}[@]}\")"

  for node in "${nodes[@]}"; do
    if ! multipass delete --purge "${node}"; then
      log_warn "Could not permanently delete VM ${node}."
      failed=1
    fi
  done
  (( failed == 0 )) || return 1

  remove_cluster_index_entry "${CLUSTER_NAME}" || return 1
  rm -rf "${cluster_dir}"
}
