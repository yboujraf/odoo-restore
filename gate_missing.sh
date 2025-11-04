#!/usr/bin/env bash
# gate_missing.sh
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/gate_missing.log"; STATE_FILE="${STATE_DIR}/.state.gate_missing"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[gate_missing] START"; echo "PENDING" > "$STATE_FILE"
DB_CSV="${INST_DIR}/reports/modules_db.csv"; FS_CSV="${INST_DIR}/reports/modules_fs.csv"; OUT="${INST_DIR}/reports/missing_addons.csv"
[[ -f "$DB_CSV" ]] || fail "Missing $DB_CSV (run db_export_modules.sh)"
[[ -f "$FS_CSV" ]] || fail "Missing $FS_CSV (run scan_addons.sh)"
python3 - <<'PY' "$DB_CSV" "$FS_CSV" "$OUT"
import sys, csv, pathlib
db, fs, out = map(pathlib.Path, sys.argv[1:4])
dbmods=set()
with db.open() as f:
    for i,row in enumerate(csv.reader(f)):
        if i==0: continue
        if len(row)>=2 and row[1].strip().lower() in ('installed','to upgrade','to install'):
            dbmods.add(row[0])
fsmods=set()
with fs.open() as f:
    for i,row in enumerate(csv.reader(f)):
        if i==0: continue
        if len(row)>=1: fsmods.add(row[0])
miss=sorted(dbmods - fsmods)
with out.open('w', newline='') as f:
    w=csv.writer(f); w.writerow(['module']); [w.writerow([m]) for m in miss]
PY
if [[ $(wc -l < "$OUT") -gt 1 ]]; then echo "[gate_missing] MISSING $(($(wc -l < "$OUT")-1)) addons"; echo "DONE" > "$STATE_FILE"; exit 1; fi
echo "DONE" > "$STATE_FILE"; echo "[gate_missing] No missing addons"
