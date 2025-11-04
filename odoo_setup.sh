#!/usr/bin/env bash
# odoo_setup.sh — CE first; EE obeys skip_list; generate conf & service (no enable/start)
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/odoo_setup.log"; STATE_FILE="${STATE_DIR}/.state.odoo_setup"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'fail "[odoo_setup] aborted"' ERR
log "[odoo_setup] START"
log "Reading CORE from CONFIG_YAML=${CONFIG_YAML}"

declare -A SKIP=(); in_skip=0
while IFS= read -r line; do
  case "$line" in *"skip_list:"*) in_skip=1; continue;; [A-Z]*:*) [[ $in_skip -eq 1 ]] && in_skip=0;; esac
  [[ $in_skip -eq 1 ]] || continue
  case "$line" in *"- "*) k="${line##*- }"; k="${k//\"/}"; k="${k//\'/}"; SKIP["$k"]=1;; esac
done < "$CONFIG_YAML"

clone_repo(){
  local id="$1" url="$2" branch="$3" depth="$4" auth="$5" ssh_key="$6" dest="$7"
  [[ -d "$dest/.git" ]] && { (
    cd "$dest"
    git fetch --depth="${depth:-1}" origin "$branch" || true
    git checkout "$branch"
    git reset --hard "origin/$branch"
  ); return; }
  install -d -m 0755 "$dest"
  if [[ "$auth" == "ssh" && -n "$ssh_key" ]]; then
    GIT_SSH_COMMAND="ssh -i ${ssh_key} -o StrictHostKeyChecking=accept-new" git clone --depth="${depth:-1}" -b "$branch" "$url" "$dest"
  else
    git clone --depth="${depth:-1}" -b "$branch" "$url" "$dest"
  fi
}

# Ensure CE (odoo/odoo) exists first
if [[ ! -x "${SRC_DIR}/odoo-bin" ]]; then
  ce_url="https://github.com/odoo/odoo.git"; ce_branch="15.0"; ce_depth="1"; ce_auth="https"
  # Try to read actual CE config
  in_core=0
  while IFS= read -r line; do
    [[ "$line" == *"CORE:"* ]] && in_core=1 && continue
    [[ "$in_core" -eq 1 && "$line" == *"ADDONS:"* ]] && break
    if [[ "$in_core" -eq 1 ]]; then
      case "$line" in *"id: odoo/odoo"*) :;; esac
      case "$line" in *"url:"*) ce_url="${line#*: }"; ce_url="${ce_url//\"/}"; ce_url="${ce_url//\'/}";;
                             *"branch:"*) ce_branch="${line#*: }"; ce_branch="${ce_branch//\"/}"; ce_branch="${ce_branch//\'/}";;
                             *"depth:"*) ce_depth="${line#*: }";;
                             *"auth:"*)  ce_auth="${line#*: }";;
      esac
    fi
  done < "$CONFIG_YAML" || true
  log "Cloning CE core ${ce_url} (${ce_branch})"
  clone_repo "odoo/odoo" "$ce_url" "$ce_branch" "$ce_depth" "$ce_auth" "" "${SRC_DIR}"
fi

# Clone remaining CORE repos except CE and those in skip_list
in_core=0; cur_id=""; url=""; branch=""; depth="1"; auth="https"; ssh_key=""
while IFS= read -r line; do
  case "$line" in *"CORE:"*) in_core=1; continue;;
       *"ADDONS:"*|*"EXAMPLES:"*) [[ $in_core -eq 1 ]] && in_core=0;;
  esac
  [[ $in_core -eq 1 ]] || continue
  if [[ "$line" == *"id:"* ]]; then
    cur_id="${line#*: }"; cur_id="${cur_id//\"/}"; cur_id="${cur_id//\'/}"
    url=""; branch=""; depth="1"; auth="https"; ssh_key=""
  elif [[ "$line" == *"url:"* ]]; then url="${line#*: }"; url="${url//\"/}"; url="${url//\'/}"
  elif [[ "$line" == *"branch:"* ]]; then branch="${line#*: }"; branch="${branch//\"/}"; branch="${branch//\'/}"
  elif [[ "$line" == *"depth:"* ]]; then depth="${line#*: }"
  elif [[ "$line" == *"auth:"* ]]; then auth="${line#*: }"
  elif [[ "$line" == *"ssh_key_path:"* ]]; then ssh_key="${line#*: }"; ssh_key="${ssh_key//\"/}"; ssh_key="${ssh_key//\'/}"
  elif [[ -z "$line" ]]; then
    [[ "$cur_id" == "odoo/odoo" ]] && continue
    [[ -n "$cur_id" ]] || continue
    [[ "${SKIP[$cur_id]+x}" == x ]] && { log "Skipping ${cur_id} (skip_list)"; continue; }
    dest="${ADDONS_DIR}/${cur_id}"
    log "Clone ${cur_id}"
    clone_repo "$cur_id" "$url" "$branch" "$depth" "$auth" "$ssh_key" "$dest"
  fi
done < "$CONFIG_YAML"

# Generate odoo.conf (do not enable service)
CONF_FILE="${CONF_DIR}/${INSTANCE}.conf"
if [[ ! -f "$CONF_FILE" ]]; then
  cat > "$CONF_FILE" <<EOF
[options]
data_dir = ${INST_DIR}/data
logfile = ${LOG_DIR}/odoo.log
proxy_mode = True
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = ${SRC_DIR}/odoo/addons,${SRC_DIR}/addons
EOF
  chown "${ODOO_USER}:${ODOO_GROUP}" "$CONF_FILE"
  ok "odoo.conf generated: ${CONF_FILE}"
fi

UNIT="/etc/systemd/system/odoo@${INSTANCE}.service"
if [[ ! -f "$UNIT" ]]; then
  cat > "$UNIT" <<EOF
[Unit]
Description=Odoo ${INSTANCE}
After=network.target postgresql.service

[Service]
User=${ODOO_USER}
Group=${ODOO_GROUP}
ExecStart=${INST_DIR}/venv/bin/python ${SRC_DIR}/odoo-bin -c ${CONF_FILE}
Restart=on-failure
Type=simple
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  ok "systemd unit created: ${UNIT} (no start/enable performed)"
fi

echo "DONE" > "$STATE_FILE"; chown "${ODOO_USER}:${ODOO_GROUP}" "$STATE_FILE"
ok "odoo_setup completed."
