# Node-Exporter (Metrics) & Grafana Alloy (Logs) Agents

<img src="https://img.shields.io/badge/Node%20Exporter-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" /> <img src="https://img.shields.io/badge/Grafana%20Alloy-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" />

---

[Back home](../../README.md)

* [Node Exporter Agent installieren](#node-exporter-agent-installieren-und-mit-tls-absichern)
* [Grafana Alloy Agent installieren](#grafana-alloy-agent-installieren)

---

## Beschreibung
Zur Erfassung von Metriken und Logdaten werden zusätzliche Agenten eingesetzt, die auf den jeweiligen Systemen laufen.

Der Node Exporter stellt Systemmetriken (z. B. CPU, RAM, Netzwerk) für Prometheus bereit, während Grafana Alloy die Sammlung und Weiterleitung von Logdaten an Loki übernimmt.

## Node Exporter Agent installieren und mit TLS absichern

```bash
sudo groupadd node_exporter
sudo useradd --system --gid node_exporter --shell /bin/false --comment "Node Exporter Service User" node_exporter

## Ordner Struktur auf dem jeweiligen Hostsystem
sudo mkdir /etc/node_exporter
sudo chmod 0755 /etc/node_exporter
sudo chown -R root:node_exporter /etc/node_exporter

sudo mkdir /var/lib/node_exporter
sudo chown -R node_exporter:node_exporter /var/lib/node_exporter

cd /tmp
VERSION="$(curl --silent -qI https://github.com/prometheus/node_exporter/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}')"
# ${VERSION} = v1.11.0
# ${VERSION#v} = 1.11.0

## ARM64
sudo wget "https://github.com/prometheus/node_exporter/releases/download/${VERSION}/node_exporter-${VERSION#v}.linux-arm64.tar.gz"
sudo tar xvfz node_exporter-${VERSION#v}.linux-arm64.tar.gz
sudo mv node_exporter-${VERSION#v}.linux-arm64/node_exporter /usr/local/bin/
sudo rm -r node_exporter-${VERSION#v}.linux-arm64 node_exporter-${VERSION#v}.linux-arm64.tar.gz

# ---

# Zusätzliche Services bei Bedarf an Prometheus übergeben
sudo vi /etc/default/node_exporter

NODE_EXPORTER_OPTS="--collector.systemd --collector.systemd.unit-whitelist="(gitea).service""
# oder
NODE_EXPORTER_OPTS="--collector.systemd --collector.systemd.unit-whitelist="(gitea|apache2|usw).service""
```

## Self-Sign Zertifikat für den Node-Exporter

Der Prometheus Node Exporter (bzw. Windows Exporter) ist ein schlanker, in Go geschriebener Agent, der als Daemon bzw. Service auf Linux und Windows Systemen läuft. Er sammelt Systemmetriken wie CPU, Arbeitsspeicher, Festplatten und Netzwerkstatistiken.

Diese Metriken werden über einen HTTP-Endpunkt im Prometheus-Format bereitgestellt, standardmäßig auf Port 9100. Der Prometheus-Server ruft diesen Endpunkt im Pull-Verfahren regelmäßig ab ("scraping").

Um den Zugriff auf den `/metrics`-Endpunkt abzusichern, wird in diesem Setup TLS eingesetzt. Dafür wird ein selbstsigniertes Zertifikat verwendet.


```bash
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
```

Anpassungen an der `prometheus.yaml` um TLS verwenden zu können ist der Parameter `scheme: https` und `tls_config`. 

```bash
- job_name: 'grafana.htdom.local'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ["grafana.htdom.local"]
```

Das Bash Skript erzeugt eine neue Datei in dem Ordner `/etc/node_exporter` mit dem Namen `config.yaml` Diese wird als Startparameter in der Systemd Datei referenziert.

## Node Exporter Systemd Datei

```bash
[Unit]
Description=Prometheus Node Exporter
After=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --web.config.file="/etc/node_exporter/config.yaml" \
  --collector.systemd \
  --collector.textfile \
  --collector.textfile.directory=/var/lib/node_exporter \
  --web.listen-address=0.0.0.0:9100 \
  --web.telemetry-path=/metrics \
  --web.disable-exporter-metrics

Restart=always
RestartSec=1
StartLimitInterval=0

ProtectHome=yes
NoNewPrivileges=yes

ProtectSystem=strict
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=yes

[Install]
WantedBy=multi-user.target
```

## Grafana Alloy Agent installieren
