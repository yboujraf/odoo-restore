#!/usr/bin/env bash
# install_requirements.sh — obeys deps state; only-if-needed; optional constraints.txt
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/install_requirements.log"; STATE_FILE="${STATE_DIR}/.state.install_requirements"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[install_requirements] START"; echo "PENDING" > "$STATE_FILE"
REPORT_DIR="${INST_DIR}/reports"; MISSING_CSV="${REPORT_DIR}/missing_addons.csv"; CLEAN_REQ="${REPORT_DIR}/requirements.clean.txt"; CONSTRAINTS_TXT="${REPORT_DIR}/constraints.txt"; DEPS_STATE="${REPORT_DIR}/state.txt"
[[ -f "$MISSING_CSV" ]] || fail "Missing $MISSING_CSV (run gate_missing.sh)"
[[ $(wc -l < "$MISSING_CSV") -le 1 ]] || fail "Missing addons still present"
[[ -f "$DEPS_STATE" ]] || fail "Missing deps state (run gate_deps.sh)"
grep -q "READY_INSTALL" "$DEPS_STATE" || fail "Deps not READY_INSTALL"
[[ -f "$CLEAN_REQ" ]] || fail "Missing $CLEAN_REQ"
EXTRA=(); [[ -s "$CONSTRAINTS_TXT" ]] && EXTRA+=( -c "$CONSTRAINTS_TXT" )
sudo -u "${ODOO_USER}" "${INST_DIR}/venv/bin/python" -m pip install --upgrade --upgrade-strategy only-if-needed -r "$CLEAN_REQ" "${EXTRA[@]}"
sudo -u "${ODOO_USER}" "${INST_DIR}/venv/bin/python" -m pip check || true
echo "DONE" > "$STATE_FILE"
echo "[install_requirements] OK"
