#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 2 ]] || { echo 'Usage: $0 INSTANCE odoo_log_path' >&2; exit 2; }
INSTANCE="$1"; LOG="$2"
[[ -f "$LOG" ]] || { echo 'missing log' >&2; exit 1; }
grep -E 'filestore|base_path' "$LOG" || echo 'No filestore entries found'
