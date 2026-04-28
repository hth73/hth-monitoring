#!/bin/bash
set -euo pipefail

ROOT_CRT="/opt/caddy/data/caddy/pki/authorities/local/root.crt"
SRC_CRT="/opt/caddy/data/caddy/certificates/local/dc.htdom.lan/dc.htdom.lan.crt"
SRC_KEY="/opt/caddy/data/caddy/certificates/local/dc.htdom.lan/dc.htdom.lan.key"

DST="/opt/samba/certs"

changed=0

copy_if_changed() {
  local src="$1"
  local dst="$2"

  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    cp "$src" "$dst"
    echo "Updated: $dst"
    changed=1
  fi
}

copy_if_changed "$ROOT_CRT" "$DST/root.crt"
copy_if_changed "$SRC_CRT" "$DST/dc.htdom.lan.crt"
copy_if_changed "$SRC_KEY" "$DST/dc.htdom.lan.key"

chmod 0644 "$DST/root.crt"
chmod 0644 "$DST/dc.htdom.lan.crt"
chmod 0600 "$DST/dc.htdom.lan.key"

# Samba reload
if [ "$changed" -eq 1 ]; then
  echo "Reload Samba TLS"
  docker exec dc smbcontrol all reload-config
fi
