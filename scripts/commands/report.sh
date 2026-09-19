#!/usr/bin/env bash

do_report() {
  local cluster_name="${1:-}"
  local report_file

  if [[ -z "${cluster_name}" ]]; then
    die "Usage: local-k3s report <cluster-name>"
  fi

  validate_cluster_name "${cluster_name}"
  report_file="$(report_file_for "${cluster_name}")"
  [[ -f "${report_file}" ]] || die "Report not found: ${report_file}"
  print_report_terminal "${cluster_name}"
}
