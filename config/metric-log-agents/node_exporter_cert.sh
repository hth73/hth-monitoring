#!/usr/bin/env bash
set -ex

CONFIG_PATH="/etc/node_exporter"
CERT_FQDN="$(hostname --fqdn)"

openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
  -keyout "${CONFIG_PATH}/${CERT_FQDN}.key" \
  -out "${CONFIG_PATH}/${CERT_FQDN}.crt" \
  -subj "/C=DE/ST=Bayern/L=Muenchen/O=HTH Inc./CN=${CERT_FQDN}" \
  -addext "subjectAltName = DNS:${CERT_FQDN}"

tee -a "${CONFIG_PATH}/config.yaml" <<EOF >/dev/null
tls_server_config:
  cert_file: /etc/node_exporter/${CERT_FQDN}.crt
  key_file: /etc/node_exporter/${CERT_FQDN}.key

EOF

chown -R node_exporter:node_exporter "${CONFIG_PATH}"
chmod 0750 "${CONFIG_PATH}"
