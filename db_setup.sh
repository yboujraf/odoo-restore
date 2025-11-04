#!/usr/bin/env bash
# db_setup.sh
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/db_setup.log"; STATE_FILE="${STATE_DIR}/.state.db_setup"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'fail "[db_setup] aborted"' ERR
log "[db_setup] START"
apt_ensure postgresql unzip git
systemctl enable postgresql || true
echo "DONE" > "$STATE_FILE"; chown "${ODOO_USER}:${ODOO_GROUP}" "$STATE_FILE"
ok "db_setup done."
