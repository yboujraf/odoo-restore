# odoo-migration snapshot — gate_deps.fix position (v3.1.5)

This is a **full project snapshot** aligned with the point where `gate_deps.fix.zip` was requested.
It includes all working scripts with logs + state and conservative behavior.

## Apply
```bash
unzip -o odoo-migration-snapshot-gate_deps_fix-v3.1.5.zip -d /opt/odoo-migration
chmod +x /opt/odoo-migration/*.sh /opt/odoo-migration/tools/*.sh
```

## Run (idempotent)
```bash
cd /opt/odoo-migration
./wrapper.sh ./env/.env15_uc02
```

Reports/logs/state go to:
- `${INST_DIR}/reports`
- `${INST_DIR}/logs`
- `${INST_DIR}/state`
