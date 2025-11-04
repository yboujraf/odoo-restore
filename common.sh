#!/usr/bin/env bash
# common.sh
set -Eeuo pipefail
# Colors
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; NC='\033[0m'
ts(){ date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log(){ echo -e "$(ts) ${BLU}$*${NC}"; }
ok(){  echo -e "$(ts) ${GRN}$*${NC}"; }
warn(){echo -e "$(ts) ${YLW}$*${NC}"; }
fail(){echo -e "$(ts) ${RED}ERROR: $*${NC}" >&2; exit 1; }

require_root(){ [[ $EUID -eq 0 ]] || fail "Run as root"; }

load_env_file(){
  local f="$1"
  [[ -f "$f" ]] || fail "Env file not found: $f"
  set -a; . "$f"; set +a
  : "${INSTANCE:?INSTANCE missing}"
  : "${CONFIG_YAML:?CONFIG_YAML missing}"
  : "${BASE_DIR:=/opt/odoo}"
  : "${STAGING_ROOT:=/opt/staging}"
  : "${INST_DIR:=${STAGING_ROOT}/instances/${INSTANCE}}"
  : "${SRC_DIR:=${INST_DIR}/src}"
  : "${ADDONS_DIR:=${INST_DIR}/addons}"
  : "${CONF_DIR:=${INST_DIR}/conf}"
  : "${LOG_DIR:=${INST_DIR}/logs}"
  : "${STATE_DIR:=${INST_DIR}/state}"
  : "${ODOO_USER:=odoo}"
  : "${ODOO_GROUP:=odoo}"
  export INSTANCE CONFIG_YAML BASE_DIR STAGING_ROOT INST_DIR SRC_DIR ADDONS_DIR CONF_DIR LOG_DIR STATE_DIR ODOO_USER ODOO_GROUP
  install -d -m 0755 -o "${ODOO_USER}" -g "${ODOO_GROUP}" "${INST_DIR}" "${SRC_DIR}" "${ADDONS_DIR}" "${CONF_DIR}" "${LOG_DIR}" "${STATE_DIR}" "${INST_DIR}/reports"
}

apt_ensure(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -qq || true
  [[ $# -gt 0 ]] && apt-get install -y -qq "$@"
}
