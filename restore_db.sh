#!/usr/bin/env bash
# restore_db.sh
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/restore_db.log"; STATE_FILE="${STATE_DIR}/.state.restore_db"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'fail "[restore_db] aborted"' ERR
log "[restore_db] START"
[[ -n "${DB_ARCHIVE:-}" ]] || fail "DB_ARCHIVE not set in env"
WORK="${INST_DIR}/restore_work"
install -d -m 0755 "$WORK"
ARCH_DST="${WORK}/archive.zip"
cp -f "${DB_ARCHIVE}" "$ARCH_DST"
chown "${ODOO_USER}:${ODOO_GROUP}" "$ARCH_DST" || true
install -d -m 0755 "${WORK}/unzipped"
unzip -o "$ARCH_DST" -d "${WORK}/unzipped" >/dev/null
DUMP="$(find "${WORK}/unzipped" -maxdepth 2 -name dump.sql -print -quit)"
[[ -f "$DUMP" ]] || fail "dump.sql not found in archive"
DBN="${DB_NAME:-$(basename "${DB_ARCHIVE%.zip}")}"
BRANCH="$(awk '/CORE:/{f=1} f&&/id: odoo\/odoo/{g=1} g&&/branch:/{print $2; exit}' "$CONFIG_YAML" | tr -d '\"')"
[[ -n "$BRANCH" ]] && DBN="${BRANCH}.${DBN}"
sudo -u postgres dropdb --if-exists "$DBN"
sudo -u postgres createdb -O "${ODOO_USER}" "$DBN"
sudo -u postgres psql -d "$DBN" -f "$DUMP"
echo "$DBN" > "${INST_DIR}/reports/restored_db.txt"; chown "${ODOO_USER}:${ODOO_GROUP}" "${INST_DIR}/reports/restored_db.txt" || true
echo "DONE" > "$STATE_FILE"; chown "${ODOO_USER}:${ODOO_GROUP}" "$STATE_FILE"
ok "restore_db terminé pour ${DBN}."
