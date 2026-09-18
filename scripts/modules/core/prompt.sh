#!/usr/bin/env bash

print_header() {
  paint cyan "=============================================="
  echo ""
  paint bold " local-k3s | VM-backed local k3s lab"
  echo ""
  paint cyan "=============================================="
  echo ""
}

prompt_text() {
  local prompt="$1"
  local default="${2:-}"
  local answer

  if [[ -n "${default}" ]]; then
    read -r -p "$(paint cyan "${prompt}") (default=${default}): " answer
    echo "${answer:-${default}}"
  else
    read -r -p "$(paint cyan "${prompt}"): " answer
    echo "${answer}"
  fi
}

prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  local i
  local choice

  paint cyan "${prompt}" >&2
  echo "" >&2
  for ((i=0; i<${#options[@]}; i++)); do
    echo "  $((i+1))) ${options[$i]}" >&2
  done

  while true; do
    read -r -p "$(paint cyan "Enter option number" 2): " choice >&2
    if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return
    fi
    printf "%s\n" "$(paint yellow "Invalid option, please try again." 2)" >&2
  done
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local answer

  if [[ "${default}" == "y" ]]; then
    read -r -p "$(paint cyan "${prompt}") [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "$(paint cyan "${prompt}") [y/N]: " answer
    answer="${answer:-N}"
  fi

  [[ "${answer}" =~ ^[Yy]$ ]]
}
