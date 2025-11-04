#!/usr/bin/env bash
# wrapper.sh — orchestrates the pipeline (idempotent via state files)
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root

[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"

log "CONFIG_YAML=${CONFIG_YAML}"
log "UC mode: ${UC_MODE:-AUTO}"

run_step(){
  local sh="$1"; local name="$(basename "$sh" .sh)"
  local st="${STATE_DIR}/.state.${name}"
  log "NEXT: Running: ${name}"
  if [[ -f "$st" && "$(cat "$st")" == "DONE" ]]; then
    ok "${name} already DONE, skipping"
    return
  fi
  "${SCRIPT_DIR}/${sh}" "$ENV_FILE"
  log "${name}.sh finished."
}

run_step core_prepare.sh
run_step db_setup.sh
run_step odoo_setup.sh
run_step restore_db.sh
run_step sync_addons_from_db.sh

# Reports pipeline (safe; logs+state inside)
"${SCRIPT_DIR}/run_reports.sh" "$ENV_FILE" || true

ok "Pipeline terminé."
log "NEXT: Vérifie ${CONF_DIR}/${INSTANCE}.conf et ${LOG_DIR}/*.log"
log "NEXT: Démarre manuellement quand prêt: systemctl start odoo@${INSTANCE}.service"
