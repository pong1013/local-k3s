#!/usr/bin/env bash

capture_cert_manager_diagnostics() {
  local kubeconfig="$1"
  log_warn "cert-manager installation or readiness failed. Capturing diagnostics."
  kubectl --kubeconfig "${kubeconfig}" -n cert-manager get pods -o wide || true
  kubectl --kubeconfig "${kubeconfig}" -n cert-manager get deployments -o wide || true
  kubectl --kubeconfig "${kubeconfig}" -n cert-manager get jobs -o wide || true
  kubectl --kubeconfig "${kubeconfig}" -n cert-manager get events --sort-by=.lastTimestamp || true
  kubectl --kubeconfig "${kubeconfig}" -n cert-manager describe pods || true
}

install_cert_manager() {
  local kubeconfig="$1"
  local deployment

  # The chart's default startup API check hook verifies webhook/API usability.
  if ! helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
    --namespace cert-manager --create-namespace --set crds.enabled=true \
    --wait --timeout 10m --kubeconfig "${kubeconfig}"; then
    capture_cert_manager_diagnostics "${kubeconfig}"
    return 1
  fi

  for deployment in cert-manager cert-manager-cainjector cert-manager-webhook; do
    if ! kubectl --kubeconfig "${kubeconfig}" -n cert-manager rollout status \
      "deployment/${deployment}" --timeout=600s; then
      capture_cert_manager_diagnostics "${kubeconfig}"
      return 1
    fi
  done

  if ! kubectl --kubeconfig "${kubeconfig}" wait --for=condition=Established \
    crd/certificates.cert-manager.io crd/certificaterequests.cert-manager.io \
    crd/issuers.cert-manager.io crd/clusterissuers.cert-manager.io \
    crd/orders.acme.cert-manager.io crd/challenges.acme.cert-manager.io --timeout=600s; then
    capture_cert_manager_diagnostics "${kubeconfig}"
    return 1
  fi
}
