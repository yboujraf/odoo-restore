#!/usr/bin/env bash
set -Eeuo pipefail
systemctl stop 'odoo@*' 2>/dev/null || true
rm -rf /opt/staging/instances/* 2>/dev/null || true
echo Purged.
