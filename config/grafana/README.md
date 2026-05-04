# Grafana Server

<img src="https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" />

---

[Back home](../../README.md)

---

## Beschreibung
Grafana wird in diesem Setup als zentrales Visualisierungstool eingesetzt, um Metriken und Logdaten übersichtlich darzustellen. Es ermöglicht die Analyse von Zeitreihendaten sowie den Vergleich von Metriken und Logs über eine einheitliche Oberfläche.

Als Datenquellen werden unter anderem Prometheus (für Metriken) und Loki (für Logs) verwendet.

Die verwendeten Dashboards stammen aus der offiziellen Grafana Dashboard Library: https://grafana.com/grafana/dashboards

## Grafana Ordner-Struktur

```bash
mkdir -p ~/docker/config/grafana/provisioning/{datasources,dashboards,plugins,alerting}
chmod 0755 ~/docker/config/grafana

sudo mkdir -p /opt/grafana/data
sudo chown -R 472:472 /opt/grafana/data
sudo chmod 0750 /opt/grafana/data
```

## Grafana Konfiguration ohne OIDC

```bash
[server]
  protocol = http
  http_port = 3000
  domain = htdom.lan
  root_url = https://grafana.htdom.lan

[users]
viewers_can_edit = true ;Allow users to see the Explore Tab (Logs)

[analytics]
  check_for_updates = true

[auth]
  disable_login_form = false
  oauth_auto_login = false
  login_cookie_name = grafana_session
  oauth_state_cookie_max_age = 60
  enable_login_token = true
  oauth_allow_insecure_email_lookup=true

[security]
  cookie_secure = true
  cookie_samesite = lax

[auth.basic]
  enabled = false

[log]
  mode = console file
  level = error

[log.console]
  level = error
  format = console

[log.file]
  level = error
  format = text
  log_rotate = true
  max_lines = 1000000
  max_size_shift = 28
  daily_rotate = true
  max_days = 7
```

## Docker Compose Datei

```yaml
...

services:
  ...
  
  grafana:
    image: docker.io/grafana/grafana:13.0.1
    container_name: grafana
    hostname: grafana
    user: "472:472"
    networks: [homenet]
    restart: always
    <<: [*default-dns, *default-security]
    volumes:
      - "./config/grafana:/etc/grafana:ro"
      - "/opt/grafana/data:/var/lib/grafana"
    ports:
      - "3000:3000"
```

## Grafana Web UI

```bash
https://grafana.htdom.lan # admin/admin
```

## Grafana Data Sources konfigurieren
Home -> Connections -> Data sources -> Add new data source -> Prometheus
https://grafana.htdom.lan/connections/datasources
