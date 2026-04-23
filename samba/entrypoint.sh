#!/bin/bash
set -e

SAMBA_DIR="/var/lib/samba"

# DEBUG
echo "REALM=${REALM}"
echo "DOMAIN=${DOMAIN}"
echo "ADMIN_PASSWORD=${ADMIN_PASSWORD}"

# ❗ Hard fail wenn Passwort fehlt
if [ -z "$ADMIN_PASSWORD" ]; then
  echo "ERROR: ADMIN_PASSWORD is empty!"
  exit 1
fi

# ❗ Debian default config entfernen
rm -f /etc/samba/smb.conf

if [ ! -f "$SAMBA_DIR/private/sam.ldb" ]; then
  echo ">>> Provisioning Samba AD..."

  samba-tool domain provision \
    --use-rfc2307 \
    --realm="$REALM" \
    --domain="$DOMAIN" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASSWORD"
    
  cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
fi

echo ">>> Starting Samba AD DC..."
exec samba -i -M single

