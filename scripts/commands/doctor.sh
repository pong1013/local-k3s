#!/usr/bin/env bash

do_doctor() {
  local failed="false"

  log_info "Running local-k3s doctor checks"
  echo ""

  doctor_check_command "chien-dev" "required" || failed="true"
  doctor_check_command "multipass" "required" || failed="true"
  doctor_check_command "ssh" "required" || failed="true"
  doctor_check_command "scp" "required" || failed="true"
  doctor_check_command "kubectl" "required" || failed="true"
  doctor_check_command "curl" "required" || failed="true"
  doctor_check_command "helm" "optional" || true
  doctor_check_command "jq" "optional" || true

  echo ""
  print_host_resources

  echo ""
  if [[ "${failed}" == "true" ]]; then
    die "Doctor found missing required tools."
  fi

  log_success "Doctor checks completed."
}
