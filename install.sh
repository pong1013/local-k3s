#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${K3S_VM_LAB_REPO_URL:-https://github.com/pong1013/local-k3s.git}"
INSTALL_DIR="${K3S_VM_LAB_INSTALL_DIR:-${HOME}/.k3s-vm-lab}"
LOCAL_BIN_DIR="${HOME}/.local/bin"
BIN_NAME="local-k3s"

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 1; }
echo "==> Installing ${BIN_NAME} from ${REPO_URL}"

if [[ -d "${INSTALL_DIR}/.git" ]]; then
  current_origin="$(git -C "${INSTALL_DIR}" remote get-url origin)"
  case "${current_origin}" in
    "${REPO_URL}"|https://github.com/pong1013/k3s-vm-lab.git|https://github.com/pong1013/k3s-vm-lab|git@github.com:pong1013/k3s-vm-lab.git|git@github.com:pong1013/local-k3s.git)
      git -C "${INSTALL_DIR}" remote set-url origin "${REPO_URL}"
      ;;
    *)
      echo "error: ${INSTALL_DIR} is a checkout of ${current_origin}; refusing to replace it" >&2
      exit 1
      ;;
  esac
elif [[ -e "${INSTALL_DIR}" ]]; then
  [[ -d "${INSTALL_DIR}" ]] || { echo "error: ${INSTALL_DIR} is not a directory" >&2; exit 1; }
  # A prior installation may have left cluster records without its checkout.
  for entry in "${INSTALL_DIR}"/* "${INSTALL_DIR}"/.[!.]* "${INSTALL_DIR}"/..?*; do
    [[ -e "${entry}" || -L "${entry}" ]] || continue
    if [[ "${entry##*/}" != generated ]]; then
      echo "error: ${INSTALL_DIR} contains files outside generated/; refusing to overwrite them" >&2
      exit 1
    fi
  done
  git -C "${INSTALL_DIR}" init
  git -C "${INSTALL_DIR}" remote add origin "${REPO_URL}"
else
  mkdir -p "$(dirname "${INSTALL_DIR}")"
  git clone --branch main "${REPO_URL}" "${INSTALL_DIR}"
fi

git -C "${INSTALL_DIR}" fetch origin main
git -C "${INSTALL_DIR}" checkout -f -B main origin/main
git -C "${INSTALL_DIR}" reset --hard origin/main

mkdir -p "${LOCAL_BIN_DIR}"
new_link="${LOCAL_BIN_DIR}/${BIN_NAME}"
if [[ -e "${new_link}" && ! -L "${new_link}" ]]; then
  echo "error: ${new_link} already exists and is not a symlink" >&2
  exit 1
fi
if [[ -L "${new_link}" ]]; then
  current_target="$(readlink "${new_link}")"
  if [[ "${current_target}" != "${INSTALL_DIR}/scripts/${BIN_NAME}" ]]; then
    echo "error: ${new_link} points elsewhere; refusing to replace it" >&2
    exit 1
  fi
fi
ln -sfn "${INSTALL_DIR}/scripts/${BIN_NAME}" "${new_link}"

legacy_link="${LOCAL_BIN_DIR}/k3s-vm-lab"
if [[ -L "${legacy_link}" ]]; then
  legacy_target="$(readlink "${legacy_link}")"
  if [[ "${legacy_target}" != /* ]]; then
    legacy_target="${LOCAL_BIN_DIR}/${legacy_target}"
  fi
  legacy_parent="$(cd -P "$(dirname "${legacy_target}")" 2>/dev/null && pwd || true)"
  install_real="$(cd -P "${INSTALL_DIR}" && pwd)"
  if [[ -n "${legacy_parent}" && "${legacy_parent}/" == "${install_real}/"* ]]; then
    rm "${legacy_link}"
  fi
fi

if [[ ":${PATH}:" != *":${LOCAL_BIN_DIR}:"* ]]; then
  echo "==> Add this to your shell profile:"
  echo "    export PATH=\"${LOCAL_BIN_DIR}:\$PATH\""
fi

echo "==> Installed ${BIN_NAME}"
