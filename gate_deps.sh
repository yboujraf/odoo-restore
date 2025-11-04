#!/usr/bin/env bash
# gate_deps.sh — "gate_deps.fix" version: normalize reqs, optional env/constraints.yml -> reports/constraints.txt, suggest file on conflicts
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/gate_deps.log"; STATE_FILE="${STATE_DIR}/.state.gate_deps"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[gate_deps] START"; echo "PENDING" > "$STATE_FILE"
REPORT_DIR="${INST_DIR}/reports"; REQ_ALL="${REPORT_DIR}/requirements.all.txt"; CLEAN_REQ="${REPORT_DIR}/requirements.clean.txt"; REQ_CONFLICTS="${REPORT_DIR}/requirements.conflicts.txt"
REQ_BY_LIB="${REPORT_DIR}/requirements.by_lib.txt"; CONSTRAINTS_YML="${SCRIPT_DIR}/env/constraints.yml"; CONSTRAINTS_TXT="${REPORT_DIR}/constraints.txt"; SUGGEST_YML="${REPORT_DIR}/constraints.suggested.yml"; DEPS_STATE="${REPORT_DIR}/state.txt"
[[ -f "$REQ_ALL" ]] || fail "Missing $REQ_ALL (run scan_addons.sh)"
python3 - <<'PY' "$REQ_ALL" "$CLEAN_REQ"
import sys, re, pathlib
req_all, clean_req = map(pathlib.Path, sys.argv[1:3])
COMMENT=re.compile(r'^\s*#'); EMPTY=re.compile(r'^\s*$'); NAME_RE=re.compile(r'^\s*([A-Za-z0-9_.\-]+)')
TRAILING_OP=re.compile(r'\s*([<>=!~]=?|===)\s*$'); EXTRA_SPACES=re.compile(r'\s+')
def can_parse(line:str)->bool:
    s=line.strip()
    try:
        from packaging.requirements import Requirement; Requirement(s); return True
    except Exception: pass
    try:
        __import__('pkg_resources').Requirement.parse(s); return True
    except Exception: return False
clean=[]
for raw in req_all.read_text(encoding='utf-8', errors='ignore').splitlines():
    line=raw.rstrip('\n')
    if line.startswith('# BEGIN ') or line.startswith('# END ') or COMMENT.match(line) or EMPTY.match(line):
        clean.append(line); continue
    s=line.strip()
    if s.startswith(('-e ','--extra-index-url','--index-url','--find-links','-f ','--trusted-host')) or 'git+' in s or '://' in s:
        clean.append(line); continue
    if can_parse(s):
        clean.append(s); continue
    orig=s; s=TRAILING_OP.sub('', s); s=EXTRA_SPACES.sub(' ', s).strip()
    if can_parse(s):
        clean.append(s); continue
    m=NAME_RE.match(s); clean.append(m.group(1) if m else f"# INVALID: {orig}")
clean_req.write_text('\n'.join(clean).rstrip()+'\n', encoding='utf-8')
PY

STATE="READY_INSTALL"
if [[ -s "$REQ_CONFLICTS" ]]; then
  STATE="PENDING_CONSTRAINTS"
  python3 - <<'PY' "$REQ_CONFLICTS" "$SUGGEST_YML"
import sys, pathlib
conf, out = map(pathlib.Path, sys.argv[1:3])
sug=["# Suggested constraints (copy to env/constraints.yml)"]
for line in conf.read_text(encoding='utf-8', errors='ignore').splitlines():
    if ':' not in line: continue
    pkg, specs = line.split(':',1)
    pkg=pkg.strip().lower(); specs=specs.strip()
    parts=[p.strip() for p in specs.split(',') if p.strip()]
    ranges=[p for p in parts if not p.startswith('==')]
    suggestion=ranges[0] if ranges else parts[0]
    sug.append(f"{pkg}: \"{suggestion}\"")
out.write_text('\n'.join(sug)+'\n', encoding='utf-8')
PY
fi

if [[ -f "$CONSTRAINTS_YML" ]]; then
  python3 - <<'PY' "$CONSTRAINTS_YML" "$CONSTRAINTS_TXT"
import sys, pathlib
yml, out = map(pathlib.Path, sys.argv[1:3])
lines=[]
for line in yml.read_text(encoding='utf-8', errors='ignore').splitlines():
    s=line.strip()
    if not s or s.startswith('#') or ':' not in s: continue
    k,v = s.split(':',1)
    k=k.strip().lower().strip('"\''); v=v.strip().strip('"\'')
    if not k or not v: continue
    lines.append(f"{k}{v}" if v and v[0] in "<>=!~" else f"{k}=={v}")
out.write_text('\n'.join(lines).rstrip()+'\n', encoding='utf-8')
PY
  STATE="READY_INSTALL"
fi

echo "$STATE" > "$DEPS_STATE"; chown "${ODOO_USER}:${ODOO_GROUP}" "$DEPS_STATE" 2>/dev/null || true
echo "DONE" > "$STATE_FILE"
echo "[gate_deps] deps state=$STATE"
