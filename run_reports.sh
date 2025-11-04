#!/usr/bin/env bash
# run_reports.sh — orchestrates reports (idempotent)
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-}"; [[ -n "$ENV_FILE" ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
"${SCRIPT_DIR}/db_export_modules.sh" "$ENV_FILE"
"${SCRIPT_DIR}/scan_addons.sh" "$ENV_FILE"
"${SCRIPT_DIR}/gate_missing.sh" "$ENV_FILE"
"${SCRIPT_DIR}/gate_deps.sh" "$ENV_FILE"
DEPS_STATE="$(
  . "${SCRIPT_DIR}/common.sh"
  load_env_file "$ENV_FILE"
  echo "${INST_DIR}/reports/state.txt"
)"
if [[ -f "$DEPS_STATE" ]] && grep -q "READY_INSTALL" "$DEPS_STATE"; then
  "${SCRIPT_DIR}/install_requirements.sh" "$ENV_FILE"
else
  echo "Skip install: deps state is $(cat "$DEPS_STATE" 2>/dev/null || echo UNKNOWN)"
fi
