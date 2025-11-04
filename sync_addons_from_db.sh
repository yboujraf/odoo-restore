#!/usr/bin/env bash
# sync_addons_from_db.sh — clone ADDONS repos & merge addons_path
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/sync_addons_from_db.log"; STATE_FILE="${STATE_DIR}/.state.sync_addons_from_db"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'fail "[sync_addons_from_db] aborted"' ERR
log "[sync_addons_from_db] START"

declare -A SKIP=(); in_skip=0
while IFS= read -r line; do
  case "$line" in *"skip_list:"*) in_skip=1; continue;; [A-Z]*:*) [[ $in_skip -eq 1 ]] && in_skip=0;; esac
  [[ $in_skip -eq 1 ]] || continue
  case "$line" in *"- "*) k="${line##*- }"; k="${k//\"/}"; k="${k//\'/}"; SKIP["$k"]=1;; esac
done < "$CONFIG_YAML"

clone_repo(){
  local id="$1" url="$2" branch="$3" depth="$4" auth="$5" ssh_key="$6" dest="$7"
  [[ "${SKIP[$id]+x}" == x ]] && { log "Skipping ${id} (skip_list)"; return; }
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

in_addons=0; cur_id=""; url=""; branch=""; depth="1"; auth="https"; ssh_key=""
while IFS= read -r line; do
  case "$line" in *"ADDONS:"*) in_addons=1; continue;;
       *"CORE:"*|*"EXAMPLES:"*|*"skip_list:"*) [[ $in_addons -eq 1 ]] && in_addons=0;;
  esac
  [[ $in_addons -eq 1 ]] || continue
  if [[ "$line" == *"id:"* ]]; then
    cur_id="${line#*: }"; cur_id="${cur_id//\"/}"; cur_id="${cur_id//\'/}"
    url=""; branch=""; depth="1"; auth="https"; ssh_key=""
  elif [[ "$line" == *"url:"* ]]; then url="${line#*: }"; url="${url//\"/}"; url="${url//\'/}"
  elif [[ "$line" == *"branch:"* ]]; then branch="${line#*: }"; branch="${branch//\"/}"; branch="${branch//\'/}"
  elif [[ "$line" == *"depth:"* ]]; then depth="${line#*: }"
  elif [[ "$line" == *"auth:"* ]]; then auth="${line#*: }"
  elif [[ "$line" == *"ssh_key_path:"* ]]; then ssh_key="${line#*: }"; ssh_key="${ssh_key//\"/}"; ssh_key="${ssh_key//\'/}"
  elif [[ -z "$line" ]]; then
    [[ -n "$cur_id" ]] || continue
    dest="${ADDONS_DIR}/${cur_id}"
    log "Clone ${cur_id}"
    clone_repo "$cur_id" "$url" "$branch" "$depth" "$auth" "$ssh_key" "$dest"
  fi
done < "$CONFIG_YAML"

"${SCRIPT_DIR}/merge_addons_path.sh" "$ENV_FILE"

echo "DONE" > "$STATE_FILE"; chown "${ODOO_USER}:${ODOO_GROUP}" "$STATE_FILE"
ok "sync_addons_from_db completed (addons repos prepared)."
