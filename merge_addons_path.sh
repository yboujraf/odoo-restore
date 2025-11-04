#!/usr/bin/env bash
# merge_addons_path.sh
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"

CONF_FILE="${CONF_DIR}/${INSTANCE}.conf"
[[ -f "$CONF_FILE" ]] || fail "Missing conf ${CONF_FILE}"

paths=()
[[ -d "${SRC_DIR}/addons" ]] && paths+=("${SRC_DIR}/addons")
[[ -d "${SRC_DIR}/odoo/addons" ]] && paths+=("${SRC_DIR}/odoo/addons")

while IFS= read -r -d '' d; do
  paths+=("${d}")
done < <(find "${ADDONS_DIR}" -mindepth 2 -maxdepth 2 -type d -print0 | sort -z)

AP="$(IFS=,; echo "${paths[*]}")"
if grep -q "^addons_path" "$CONF_FILE"; then
  sed -i -E "s|^addons_path *=.*|addons_path = ${AP}|" "$CONF_FILE"
else
  printf "\naddons_path = %s\n" "$AP" >> "$CONF_FILE"
fi
chown "${ODOO_USER}:${ODOO_GROUP}" "$CONF_FILE" || true
log "Merged addons_path into ${CONF_FILE}"
