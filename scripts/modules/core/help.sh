#!/usr/bin/env bash

print_help() {
  cat <<'EOF'
local-k3s - VM-backed local k3s lab installer

Usage:
  local-k3s doctor
  local-k3s create [cluster-name]
  local-k3s status [cluster-name] [wide]
  local-k3s report [cluster-name]
  local-k3s start <cluster-name>
  local-k3s stop <cluster-name>
  local-k3s delete <cluster-name>
  local-k3s update
  local-k3s help

Topology:
  create creates 1 fixed control-plane/server VM plus optional workers.
  You choose the total node count, including the server.

Commands:
  doctor   Check required local tools and host resources.
  create   Create Multipass VM nodes through chien-dev, install k3s, merge kubeconfig, and write a report.
  status   Show formatted VM and Kubernetes status for a cluster; add wide for raw node details.
  report   Show a formatted terminal report and keep report.md on disk.
  start    Start stopped cluster VMs and wait for Kubernetes nodes to become Ready.
  stop     Stop cluster VMs without deleting generated files or kubeconfig entries.
  delete   Delete cluster VMs, kubeconfig entries, index entry, and generated files.
  update   Compare the installed checkout with remote main and update it when changed.
EOF
}
