# Prometheus Server

<img src="https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" /> <img src="https://img.shields.io/badge/Node%20Exporter-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" />

---

[Back home](../../README.md)

---

## Beschreibung

Prometheus ist ein Open-Source-Monitoring- und Alerting-System, das ursprünglich von SoundCloud entwickelt wurde und heute Teil der Cloud Native Computing Foundation (CNCF) ist. Es ist in Go geschrieben und hat sich als Standardlösung im Cloud- und Container-Umfeld etabliert.

Warum Prometheus?

Im Gegensatz zu klassischen Monitoringlösungen wie Nagios, Icinga oder Zabbix setzt Prometheus auf einen modularen Aufbau und eine speziell für Metriken optimierte Speicherung.

Die Metrikdaten werden in einer Zeitreihendatenbank (TSDB) gespeichert. Jede Metrik ist dabei an einen Zeitstempel gebunden, wodurch Abfragen über Zeiträume effizient und performant durchgeführt werden können.

Für die Abfrage der Daten stellt Prometheus mit PromQL eine eigene, leistungsfähige Abfragesprache bereit. Ein weiterer zentraler Unterschied ist das Pull-Prinzip:
Prometheus fragt die konfigurierten Targets in regelmäßigen Abständen aktiv ab und sammelt so die Metrikdaten.

Einsatz in diesem Setup

- In diesem Homelab übernimmt Prometheus die zentrale Sammlung und Speicherung aller Metriken:
- Systemmetriken über Node Exporter
- Container- und Service-Metriken
- später: E2E-Monitoring über Blackbox Exporter

Die gesammelten Daten werden anschließend in Grafana visualisiert.

## Funktionsweise des Prometheus Servers

Prometheus basiert auf dem sogenannten White-Box-Monitoring.
Das bedeutet, dass überwachte Anwendungen ihre internen Metriken selbst bereitstellen müssen. Diese werden über sogenannte Exporter im Prometheus-Format zur Verfügung gestellt.

https://prometheus.io/docs/instrumenting/exporters/

Der Prometheus-Server ruft diese Metriken regelmäßig per HTTP(S) ab (Pull-Prinzip), standardmäßig über den Endpunkt: `/metrics`
Viele Exporter verwenden standardisierte Ports, z. B.: `Node Exporter: TCP 9100`

## Service Discovery und Konfiguration

Die Konfiguration des Prometheus Servers erfolgt über die Datei: `prometheus.yaml`. Hier werden sowohl globale Parameter als auch die zu überwachenden Targets definiert.

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 60s

rule_files:
  - /etc/prometheus/rules/*.yaml

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "server1"
    static_configs:
      - targets: ["192.168.xxx.xxx:9100"]

  - job_name: "server2"
    static_configs:
      - targets: ["192.168.xxx.xxx:9100"]
```

Neben statischen Targets unterstützt Prometheus auch automatische Service Discovery. Somit würden neue Maschine automatisch mit Prometheus überwacht.
https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config

```yaml
- job_name: node_exporter_metrics
  scheme: https
  tls_config:
    insecure_skip_verify: true
  ec2_sd_configs:
    - region: xxx
      profile: xxx
      port: 9100
      refresh_interval: 30m
      filters:
        - name: tag:prometheus_machine_tag # value=enabled or disabled
          values:
            - enabled
 ...
```

## Time Series Database (TSDB)

Prometheus speichert alle Metriken in einer eigenen Zeitreihendatenbank (TSDB).
In diesem Setup werden die Daten über ein Docker Volume persistent gespeichert. `/prometheus = /opt/prometheus/data`

```bash
/prometheus
├── 01HKMCDPDFJXZ3GPE7J0HJGQXK # Is a Data Block - ULID - like UUID but lexicographically sortable and encoding the creation time
│   ├── chunks                 # Contains the raw chunks of data points for various series - No long a single file per series
│   │   └── 000001
│   ├── index                  # index of data - lots of black magic find the data by labels
│   ├── meta.json              # readable meta data - the state of our storage and the data it contains
│   └── tombstones             # deleted data will be recorded into this file, instead removing from chunk file
├── chunks_head                # in memory data
│   ├── 000001
│   └── 000002
├── lock
├── queries.active
└── wal                        # Write-Ahead Log - The WAL segements would be truncated to "checkpoint.X" directory
    ├── 00000004
    ├── 00000005
    ├── 00000006
    ├── 00000007
    └── checkpoint.00000003
        └── 00000000

Hinweis:
 - Die Daten werden alle 2 Stunden auf der Festplatte gespeichert.
 - WAL wird zur Datenwiederherstellung verwendet.
 - 2-Stunden-Block könnte die Datenabfrage effizienter machen.

# Universally Unique Lexicographically Sortable Identifier (ULID)
ULID, or Universally Unique Lexicographically Sortable Identifier, tries to strike a balance. 
The first part of a ULID is a timestamp, the second part is random. 
This makes them sortable like auto-increment IDs, but still unique like UUIDs.
```

### Server-Konfiguration (Docker)

Nicht alle Parameter werden über die `prometheus.yaml` gesetzt. Ein Teil der Konfiguration erfolgt über Startparameter im Container.

```bash
command:
  - '--web.page-title=Prometheus Monitoring'
  - '--storage.tsdb.path=/prometheus'
  - '--storage.tsdb.retention.time=30d'
  - '--config.file=/etc/prometheus/prometheus.yaml'
  - '--web.config.file=/etc/prometheus/web_config.yaml'
  - '--web.console.libraries=/usr/share/prometheus/console_libraries'
  - '--web.console.templates=/usr/share/prometheus/consoles'
  - '--web.external-url=https://prometheus.htdom.local'
  - '--web.enable-lifecycle'
  - '--web.enable-admin-api'
```

## Prometheus Ordner-Struktur

```bash
mkdir -p ~/docker/config/prometheus
chmod -R 755 ~/docker/config/prometheus

sudo mkdir -p /opt/prometheus/data
sudo chown -R 65534:65534 /opt/prometheus/data
sudo chmod 750 /opt/prometheus/data
```

## Prometheus Konfiguration bei Bedarf Online aktualisieren

```bash
# vi ~/docker/docker-compose.yaml
# --web.enable-lifecycle

curl -Xk POST https://prometheus.htdom.local/-/reload
```

## prometheus.yaml Datei anlegen

```bash
## Global Prometheus Server Config
global:
  scrape_interval: 15s
  evaluation_interval: 60s

## Rules and alerts are read from the specified file(s)
rule_files:
  - /etc/prometheus/rules/*.yaml

## Prometheus Server Config
scrape_configs:
- job_name: 'prometheus.htdom.local'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ['prometheus.htdom.local']

- job_name: 'grafana.htdom.local'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ["grafana.htdom.local"]

- job_name: 'loki.htdom.local'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ["loki.htdom.local"]

- job_name: 'mina.htdom.local'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ["mina.htdom.local:9100"]
```

## Docker Compose Datei

```bash
---
x-dns: &default-dns
  dns:
    - 192.168.178.3

x-security: &default-security
  read_only: true
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL

networks:
  homenet:
    name: homenet
    driver: bridge

services:
  prometheus:
    image: docker.io/prom/prometheus:v3.11.2
    container_name: prometheus
    hostname: prometheus
    user: "65534:65534"
    networks: [homenet]  
    restart: always
    <<: [*default-dns, *default-security]
    tmpfs:
      - /tmp
    volumes:
      - "./config/prometheus:/etc/prometheus:ro"
      - "/opt/prometheus/data:/prometheus"
    command:
      - '--web.page-title=Prometheus Monitoring'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--config.file=/etc/prometheus/prometheus.yaml'
      - '--web.config.file=/etc/prometheus/web_config.yaml'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.external-url=https://prometheus.htdom.local'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    ports:
      - 9090:9090
```

## Prometheus Web UI

```bash
https://prometheus.htdom.local
```
