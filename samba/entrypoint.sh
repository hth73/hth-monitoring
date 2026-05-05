#!/bin/bash
set -e

SAMBA_DIR="/var/lib/samba"
SMB_CONF="/etc/samba/smb.conf"

echo "REALM=${REALM}"
echo "DOMAIN=${DOMAIN}"

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "ERROR: ADMIN_PASSWORD is empty!"
  exit 1
fi

# --- smb.conf vor erstem Provisioning löschen
if [ ! -f "$SAMBA_DIR/private/sam.ldb" ]; then
  echo ">>> First run → removing default smb.conf"
  rm -f "$SMB_CONF"

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

# --- sicherstellen dass smb.conf existiert
if [ ! -f "$SMB_CONF" ]; then
  echo "ERROR: smb.conf missing after provisioning!"
  exit 1
fi

# --- TLS in [global] einfügen (idempotent)
if ! grep -q "tls enabled" "$SMB_CONF"; then
  echo ">>> Inject TLS config"

  awk '
  BEGIN {added=0}
  /^\[global\]/ {
    print
    print "    tls enabled = yes"
    print "    tls keyfile = /certs/dc.htdom.lan.key"
    print "    tls certfile = /certs/dc.htdom.lan.crt"
    print "    tls cafile = /certs/root.crt"
    added=1
    next
  }
  {print}
  END {
    if (added==0) {
      print "[global]"
      print "    tls enabled = yes"
      print "    tls keyfile = /certs/dc.htdom.lan.key"
      print "    tls certfile = /certs/dc.htdom.lan.crt"
      print "    tls cafile = /certs/root.crt"
    }
  }
  ' "$SMB_CONF" > /tmp/smb.conf && mv /tmp/smb.conf "$SMB_CONF"
fi

# --- DNS Forwarder setzen (idempotent)
DNS_FWD="${DNS_FORWARDER:-192.168.178.1}"

if grep -q "dns forwarder" "$SMB_CONF"; then
  # ersetzen falls vorhanden
  sed -i "s|dns forwarder = .*|dns forwarder = ${DNS_FWD}|" "$SMB_CONF"
else
  # einfügen in [global]
  awk -v fwd="$DNS_FWD" '
  BEGIN {added=0}
  /^\[global\]/ {
    print
    print "    dns forwarder = " fwd
    added=1
    next
  }
  {print}
  END {
    if (added==0) {
      print "[global]"
      print "    dns forwarder = " fwd
    }
  }
  ' "$SMB_CONF" > /tmp/smb.conf && mv /tmp/smb.conf "$SMB_CONF"
fi

# --- resolv.conf fix
cat <<EOF > /etc/resolv.conf
nameserver 127.0.0.1
search htdom.lan
EOF

echo ">>> Starting Samba AD DC..."
exec samba -i -M single
