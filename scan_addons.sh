#!/usr/bin/env bash
# scan_addons.sh (v2) — fast manifest scan; requirements aggregation
set -Eeuo pipefail; set -o errtrace
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"; require_root
[[ $# -eq 1 ]] || { echo "Usage: $0 ./env/.envINSTANCE" >&2; exit 2; }
ENV_FILE="$1"; load_env_file "$ENV_FILE"
LOG_FILE="${LOG_DIR}/scan_addons.log"; STATE_FILE="${STATE_DIR}/.state.scan_addons"
exec > >(tee -a "$LOG_FILE") 2>&1; trap 'echo "[scan_addons] ERROR"; echo "ERROR" > "$STATE_FILE"' ERR
echo "[scan_addons] START"; echo "PENDING" > "$STATE_FILE"
REPORT_DIR="${INST_DIR}/reports"
MODULES_FS="${REPORT_DIR}/modules_fs.csv"; REQ_ALL="${REPORT_DIR}/requirements.all.txt"; REQ_BY_LIB="${REPORT_DIR}/requirements.by_lib.txt"; REQ_CONFLICTS="${REPORT_DIR}/requirements.conflicts.txt"
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "$TMP_DIR"' EXIT
MFS_TMP="${TMP_DIR}/modules_fs.csv.tmp"; RAL_TMP="${TMP_DIR}/requirements.all.txt.tmp"; RBL_TMP="${TMP_DIR}/requirements.by_lib.txt.tmp"; RCF_TMP="${TMP_DIR}/requirements.conflicts.txt.tmp"
declare -A SKIP=(); in_skip=0
while IFS= read -r line; do case "$line" in *"skip_list:"*) in_skip=1; continue;; [A-Z]*:*) [[ $in_skip -eq 1 ]] && in_skip=0;; esac; [[ $in_skip -eq 1 ]] || continue; case "$line" in *"- "*) k="${line##*- }"; k="${k//\"/}"; k="${k//\'/}"; SKIP["$k"]=1;; esac; done < "$CONFIG_YAML"
ids=(); in_addons=0
while IFS= read -r line; do case "$line" in *"ADDONS:"*) in_addons=1; continue;; *"CORE:"*|*"EXAMPLES:"*) [[ $in_addons -eq 1 ]] && in_addons=0;; esac; [[ $in_addons -eq 1 ]] || continue; case "$line" in *"id:"* ) idv="${line#*: }"; idv="${idv//\"/}"; idv="${idv//\'/}"; ids+=("$idv");; esac; done < "$CONFIG_YAML"
repos=(); for rid in "${ids[@]}"; do [[ -n "$rid" ]] || continue; [[ "${SKIP[$rid]+x}" == x ]] && continue; p="${ADDONS_DIR}/${rid}"; [[ -d "$p" ]] && repos+=("$p"); done
[[ -d "${ADDONS_DIR}/odoo/enterprise" && -z "${SKIP[odoo/enterprise]+x}" ]] && repos+=("${ADDONS_DIR}/odoo/enterprise")
core_roots=(); [[ -d "${SRC_DIR}/addons" ]] && core_roots+=("${SRC_DIR}/addons"); [[ -d "${SRC_DIR}/odoo/addons" ]] && core_roots+=("${SRC_DIR}/odoo/addons")
echo "module,repo_id,rel_path,depends,ext_py" > "$MFS_TMP"; : > "$RAL_TMP"
parse_manifest_py(){ local manifest="$1"; python3 - <<'PY' "$manifest"
import ast, sys, pathlib
mf = pathlib.Path(sys.argv[1])
try:
    txt = mf.read_text(encoding='utf-8', errors='ignore')
    obj = ast.literal_eval(txt)
    dep = obj.get('depends') or []
    ext = (obj.get('external_dependencies') or {}).get('python') or []
    dep = [str(x) for x in dep if isinstance(x, str)]
    ext = [str(x) for x in ext if isinstance(x, str)]
    print("DEP=" + "|".join(dep)); print("EXT=" + "|".join(ext))
except Exception:
    print("DEP="); print("EXT=")
PY
}
walk_repo(){ local root="$1" base="$2" rid="$3"
  while IFS= read -r -d '' mf; do addon_dir="$(dirname "$mf")"; module="$(basename "$addon_dir")"; rel="${addon_dir#$base/}"
    out="$(parse_manifest_py "$mf")"; depends="$(printf '%s\n' "$out" | sed -n 's/^DEP=//p')"; extpy="$(printf '%s\n' "$out" | sed -n 's/^EXT=//p')"
    printf "%s,%s,%s,%s,%s\n" "$module" "$rid" "$rel" "$depends" "$extpy" >> "$MFS_TMP"
    if [[ -f "${addon_dir}/requirements.txt" ]]; then { echo "# BEGIN ${rid}:${rel}"; cat "${addon_dir}/requirements.txt"; echo "# END ${rid}:${rel}"; echo; } >> "$RAL_TMP"; fi
    if [[ -n "$extpy" ]]; then { echo "# BEGIN ${rid}:${rel} (external_dependencies.python)"; IFS='|' read -r -a arr <<< "$extpy"; for p in "${arr[@]}"; do [[ -n "$p" ]] && echo "$p"; done; echo "# END ${rid}:${rel}"; echo; } >> "$RAL_TMP"; fi
  done < <(find "$root" -type f -name "__manifest__.py" -print0)
}
for r in "${repos[@]}"; do walk_repo "$r" "$r" "${r#${ADDONS_DIR}/}"; done
for cr in "${core_roots[@]}"; do walk_repo "$cr" "$cr" "odoo/odoo"; done

python3 - <<'PY' "$RAL_TMP" "$RBL_TMP" "$RCF_TMP"
import sys, re, collections
req_file, bylib_file, conflicts_file = sys.argv[1:4]
name_re = re.compile(r'^\s*([A-Za-z0-9_.\-]+)')
spec_re = re.compile(r'([<>=!~]=?\s*[^,\s#;]+)')
bylib = collections.defaultdict(set)
with open(req_file, 'r', encoding='utf-8') as f:
    for line in f:
        s = line.strip()
        if not s or s.startswith('#'): continue
        m = name_re.match(s)
        if not m: continue
        name = m.group(1).lower()
        specs = spec_re.findall(s)
        spec = ','.join(sorted(set([x.replace(' ', '') for x in specs]))) if specs else ''
        bylib[name].add(spec or '*')
with open(bylib_file, 'w', encoding='utf-8') as out:
    for name in sorted(bylib):
        out.write(f"{name}: {', '.join(sorted(bylib[name]))}\n")
conf = []
try:
    from packaging.specifiers import SpecifierSet
    from packaging.version import Version
    def ok(specs):
        real=[s for s in specs if s and s!='*']
        if not real: return True
        pins=[s for s in real if s.startswith('==')]
        if pins:
            v=pins[0][2:]
            try: vv=Version(v)
            except Exception: return False
            return all(SpecifierSet(sp).contains(vv, prereleases=True) for sp in real)
        for cv in ['0','1','2','3','10','20','36','36.0','36.1','37','38','100']:
            try: vv=Version(cv)
            except Exception: continue
            if all(SpecifierSet(sp).contains(vv, prereleases=True) for sp in real):
                return True
        return False
    for name,specs in bylib.items():
        if not ok(specs):
            conf.append(f"{name}: {', '.join(sorted(set([s for s in specs if s and s!='*'])))}")
except Exception:
    for name,specs in bylib.items():
        s=[x for x in specs if s and s!='*']
        if len(set(s))>1:
            conf.append(f"{name}: {', '.join(sorted(set(s)))}")
with open(conflicts_file, 'w', encoding='utf-8') as out:
    for c in conf: out.write(c + "\n")
PY

install -m 0644 "$MFS_TMP" "$MODULES_FS"; install -m 0644 "$RAL_TMP" "$REQ_ALL"; install -m 0644 "$RBL_TMP" "$REQ_BY_LIB"; install -m 0644 "$RCF_TMP" "$REQ_CONFLICTS"
chown "${ODOO_USER}:${ODOO_GROUP}" "$MODULES_FS" "$REQ_ALL" "$REQ_BY_LIB" "$REQ_CONFLICTS" 2>/dev/null || true
echo "DONE" > "$STATE_FILE"
echo "[scan_addons] END"
