#!/usr/bin/env bash
# core_prepare.sh
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/core_prepare.log"; STATE_FILE="${STATE_DIR}/.state.core_prepare"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'fail "[core_prepare] aborted"' ERR
log "[core_prepare] START"
install -d -o "${ODOO_USER}" -g "${ODOO_GROUP}" -m 0755 "${INST_DIR}/venv"
if [[ ! -x "${INST_DIR}/venv/bin/python" ]]; then
  log "Creating Python venv at ${INST_DIR}/venv"
  apt_ensure python3-venv python3-pip python3-dev build-essential
  sudo -u "${ODOO_USER}" python3 -m venv "${INST_DIR}/venv"
  sudo -u "${ODOO_USER}" "${INST_DIR}/venv/bin/python" -m pip install --upgrade pip wheel setuptools
fi
echo "DONE" > "$STATE_FILE"; chown "${ODOO_USER}:${ODOO_GROUP}" "$STATE_FILE"
ok "core_prepare done."
