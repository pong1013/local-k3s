#!/usr/bin/env bash

cleanup_vm_nodes() {
  local node
  local failed=0

  for node in "$@"; do
    if ! clean_vm_node "${node}"; then
      failed=1
    fi
  done
  (( failed == 0 ))
}

cleanup_recorded_nodes() {
  local nodes_file="$1"
  local node_name role ip cpus memory disk
  local nodes=()

  [[ -f "${nodes_file}" ]] || return 0
  while IFS=$'\t' read -r node_name role ip cpus memory disk; do
    nodes+=("${node_name}")
  done < "${nodes_file}"
  (( ${#nodes[@]} > 0 )) || return 0
  cleanup_vm_nodes "${nodes[@]}"
}

cleanup_created_nodes() {
  local array_name="$1"
  local nodes=()
  eval "nodes=(\"\${${array_name}[@]}\")"

  if (( ${#nodes[@]} == 0 )); then
    return 0
  fi

  log_warn "Build failed. Cleaning up created VM nodes."
  cleanup_vm_nodes "${nodes[@]}"
}
