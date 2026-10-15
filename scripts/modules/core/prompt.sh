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

# Return selected option numbers, one per line; keep all UI on stderr.
prompt_multi_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  local tokens=()
  local selected=" "
  local answer token i valid

  paint cyan "${prompt}" >&2
  echo "" >&2
  for ((i=0; i<${#options[@]}; i++)); do
    echo "  $((i+1))) ${options[$i]}" >&2
  done

  while true; do
    if ! IFS= read -r -p "$(paint cyan "Enter option numbers (space-separated; Enter skips all)" 2): " answer; then
      echo "Add-on selection cancelled: input ended." >&2
      return 1
    fi
    IFS=$' \t' read -r -a tokens <<< "${answer}"
    selected=" "
    valid=true
    for token in ${tokens[@]+"${tokens[@]}"}; do
      # Compare strings rather than evaluating user input as shell arithmetic.
      valid=false
      for ((i=1; i<=${#options[@]}; i++)); do
        if [[ "${token}" == "${i}" ]]; then
          valid=true
          [[ "${selected}" == *" ${i} "* ]] || selected+="${i} "
          break
        fi
      done
      [[ "${valid}" == true ]] || break
    done
    if [[ "${valid}" == true ]]; then
      for ((i=1; i<=${#options[@]}; i++)); do
        [[ "${selected}" != *" ${i} "* ]] || printf '%s\n' "${i}"
      done
      return 0
    fi
    echo "Invalid option, please try again. Enter numbers separated by spaces." >&2
  done
}
