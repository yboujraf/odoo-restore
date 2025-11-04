#!/usr/bin/env bash
# db_export_modules.sh (v2)
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/db_export_modules.log"; STATE_FILE="${STATE_DIR}/.state.db_export_modules"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "[db_export_modules] ERROR"; echo "ERROR" > "$STATE_FILE"' ERR
echo "[db_export_modules] START"; echo "PENDING" > "$STATE_FILE"
CONF_FILE="${CONF_DIR}/${INSTANCE}.conf"; OUT="${INST_DIR}/reports/modules_db.csv"
DBN="${DB_NAME:-}"
[[ -z "$DBN" && -f "${INST_DIR}/reports/restored_db.txt" ]] && DBN="$(head -n1 "${INST_DIR}/reports/restored_db.txt" | tr -d ' \t\r')"
if [[ -z "$DBN" && -n "${DB_ARCHIVE:-}" ]]; then base="$(basename -- "${DB_ARCHIVE}")"; DBN="${base%.zip}"; fi
if [[ -z "$DBN" && -f "$CONF_FILE" ]]; then DBN="$(sed -n -E 's/^\s*db_name\s*=\s*(.*)$/\1/p' "$CONF_FILE" | tail -n1 | tr -d ' \t\r')"; fi
DBH="$(sed -n -E 's/^\s*db_host\s*=\s*(.*)$/\1/p' "$CONF_FILE" | tail -n1 | tr -d ' \t\r')"
DBP="$(sed -n -E 's/^\s*db_port\s*=\s*(.*)$/\1/p' "$CONF_FILE" | tail -n1 | tr -d ' \t\r')"
DBU="$(sed -n -E 's/^\s*db_user\s*=\s*(.*)$/\1/p' "$CONF_FILE" | tail -n1 | tr -d ' \t\r')"
DBW="$(sed -n -E 's/^\s*db_password\s*=\s*(.*)$/\1/p' "$CONF_FILE" | tail -n1 | tr -d ' \t\r')"
PSQL=(psql -At); [[ -n "$DBH" ]] && PSQL+=(-h "$DBH"); [[ -n "$DBP" ]] && PSQL+=(-p "$DBP"); [[ -n "$DBU" ]] && { PSQL+=(-U "$DBU"); export PGPASSWORD="$DBW"; }
RUN_AS="${DBU:-postgres}"
if [[ -z "$DBN" ]]; then echo "ERROR: Cannot determine DB name"; exit 1; fi
DB_LIST="$(sudo -u "$RUN_AS" "${PSQL[@]}" -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate=false")" || true
if ! grep -Fxq -- "$DBN" <<< "$DB_LIST"; then
  BRANCH="$(awk '/CORE:/{f=1} f&&/id: odoo\/odoo/{g=1} g&&/branch:/{print $2; exit}' "$CONFIG_YAML" | tr -d '\"')"
  CAND="${BRANCH:+${BRANCH}.}${DBN}"
  if grep -Fxq -- "$CAND" <<< "$DB_LIST"; then echo "[db_export_modules] Using fallback DB name: $CAND"; DBN="$CAND"; fi
fi
echo "module,state" > "$OUT"
sudo -u "$RUN_AS" "${PSQL[@]}" -d "$DBN" -c "SELECT name, state FROM ir_module_module ORDER BY name" >> "$OUT"
echo "$DBN" > "${INST_DIR}/reports/restored_db.txt"
chown "${ODOO_USER}:${ODOO_GROUP}" "${INST_DIR}/reports/restored_db.txt" "$OUT" || true
echo "DONE" > "$STATE_FILE"
echo "[db_export_modules] wrote $(($(wc -l < "$OUT")-1)) modules from DB '$DBN'"
