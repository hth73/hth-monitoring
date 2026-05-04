# Blackbox Exporter (E2E-Verfügbarkeitsprüfungen)

<img src="https://img.shields.io/badge/Blackbox%20Exporter-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" />

---

[Back home](../../README.md)

---

## Beschreibung
Zur Überwachung der Erreichbarkeit und Funktionalität der einzelnen Services wird in diesem Setup der Prometheus Blackbox Exporter eingesetzt. Im Gegensatz zu klassischen Exportern, die interne Metriken bereitstellen, prüft der Blackbox Exporter Services von außen („Blackbox Monitoring“).

Dabei werden definierte Endpunkte aktiv abgefragt und Metriken wie Erreichbarkeit, Antwortzeit und Statuscode ermittelt.

### Einsatz im Setup

In dieser Umgebung wird der Blackbox Exporter gezielt für folgende Prüfungen eingesetzt:

- HTTP(S)-Checks für alle zentralen Services (z. B. `Caddy`, `Grafana`, `Loki`, `Prometheus`)
- DNS-Checks zur Überprüfung der internen Namensauflösung über `dnsmasq`

Damit wird sichergestellt, dass die Services nicht nur laufen, sondern auch tatsächlich über ihre FQDNs erreichbar sind.

### HTTP Checks

Die HTTP-Checks prüfen, ob ein Service über HTTPS erreichbar ist und korrekt auf Anfragen reagiert.

Dabei werden unter anderem folgende Aspekte überwacht:

- HTTP-Statuscode (z. B. 200 OK)
- TLS-Verbindung (Zertifikat vorhanden)
- Antwortzeit des Endpunkts

Dies ist besonders relevant, da alle Services in diesem Setup ausschließlich über HTTPS und FQDN angesprochen werden.

### DNS Checks

Zusätzlich werden DNS-Checks durchgeführt, um die Funktionalität des internen DNS-Servers (dnsmasq) zu validieren.

Hierbei wird überprüft:

- ob ein bestimmter FQDN korrekt aufgelöst wird
- ob die Namensauflösung innerhalb des Netzwerks funktioniert

Diese Prüfungen sind essenziell, da das gesamte Setup auf einer funktionierenden DNS-Auflösung basiert.

## Blackbox Ordner-Struktur

```bash
mkdir -p ~/docker/config/blackbox
chmod 0755 ~/docker/config/blackbox
```

## blackbox.yml

```yaml
modules: 
  http_2xx:
    prober: http
    timeout: 10s
    http:
      ip_protocol_fallback: false
      no_follow_redirects: false
      fail_if_not_ssl: true
      preferred_ip_protocol: ip4
      method: GET
      valid_status_codes: [200, 301, 302]
      valid_http_versions: 
        - HTTP/1.1
        - HTTP/2.0
      tls_config:
        insecure_skip_verify: true
  tcp_connect: 
    prober: tcp
    timeout: 10s
    tcp: 
      ip_protocol_fallback: false
      preferred_ip_protocol: ip4
      tls_config: 
        insecure_skip_verify: true
  ssh_banner:
    prober: tcp
    timeout: 10s
    tcp:
      query_response:
      - expect: "^SSH-2.0-"
  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: ip4
      ip_protocol_fallback: true

  dns:
    prober: dns
    timeout: 5s
    dns:
      query_name: mina.htdom.lan
      query_type: A
```

## docker-compose.yaml

```yaml
...

services:
  ...

  blackbox:
    image: docker.io/prom/blackbox-exporter:v0.28.0
    container_name: blackbox
    hostname: blackbox
    networks: [homenet]
    restart: always
    <<: [*default-dns, *default-security]
    volumes:
      - "./config/blackbox/blackbox.yml:/etc/blackbox/blackbox.yml:ro"
    cap_add:
      - NET_RAW
    command:
      - '--config.file=/etc/blackbox/blackbox.yml'
    ports:
      - "9115:9115"
```

## prometheus.yaml

```yaml
...

- job_name: 'blackbox-dns-check'
  metrics_path: /probe
  params:
    module: [ dns ]
  static_configs:
    - targets:
        - 192.168.178.50
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: target
    - target_label: __address__
      replacement: blackbox.htdom.lan:9115      

- job_name: 'blackbox-http-check'
  metrics_path: /probe
  params:
    module: [ http_2xx ]
  static_configs:
    - targets:
      - https://caddy.htdom.lan/metrics
      - https://grafana.htdom.lan/metrics
      - https://loki.htdom.lan/ready
      - https://prometheus.htdom.lan/metrics
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: target
    - target_label: __address__
      replacement: blackbox.htdom.lan:9115
```

## blackbox.yml - Beispiele für weitere E2E Tests

```yaml
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      valid_http_versions:
        - HTTP/1.1
        - HTTP/2.0
      preferred_ip_protocol: ip4
      method: GET
      tls_config:
        insecure_skip_verify: true
      follow_redirects: true
      enable_http2: true
    tcp:
      ip_protocol_fallback: true
    icmp:
      ip_protocol_fallback: true
      ttl: 64
    dns:
      ip_protocol_fallback: true
      recursion_desired: true
  icmp:
    prober: icmp
    timeout: 5s
    http:
      ip_protocol_fallback: true
      follow_redirects: true
      enable_http2: true
    tcp:
      ip_protocol_fallback: true
    icmp:
      preferred_ip_protocol: ip4
      ip_protocol_fallback: true
      ttl: 64
    dns:
      ip_protocol_fallback: true
      recursion_desired: true
  ssh_banner:
    prober: tcp
    timeout: 10s
    http:
      ip_protocol_fallback: true
      follow_redirects: true
      enable_http2: true
    tcp:
      ip_protocol_fallback: true
      query_response:
        - expect: ^SSH-2.0-
    icmp:
      ip_protocol_fallback: true
      ttl: 64
    dns:
      ip_protocol_fallback: true
      recursion_desired: true
  tcp_connect:
    prober: tcp
    timeout: 10s
    http:
      ip_protocol_fallback: true
      follow_redirects: true
      enable_http2: true
    tcp:
      preferred_ip_protocol: ip4
      tls_config:
        insecure_skip_verify: true
    icmp:
      ip_protocol_fallback: true
      ttl: 64
    dns:
      ip_protocol_fallback: true
      recursion_desired: true
```

## Beispiel Checks

```bash
## variables in Grafana
job - label_values(probe_success, job)
instance - label_values(probe_duration_seconds{job=~"$job"}, instance)

avg(probe_success{job=~"$job", instance=~"$instance"})

count(probe_success{job=~"$job", instance=~"$instance"} == 1)
count(probe_success{job=~"$job", instance=~"$instance"} == 0)

avg(scrape_duration_seconds{job=~"$job", instance=~"$instance"})
avg(scrape_duration_seconds{job="blackbox-http-check", instance=~"https://www.domain.de/metrics"})

avg by (phase) (probe_http_duration_seconds{job=~"$job", instance=~"$instance"})

count_values("http_version", probe_http_version{job=~"$job", instance=~"$instance"})
count by (version) (probe_tls_version_info{job=~"$job", instance=~"$instance"})
count_values("value", probe_http_status_code{job=~"$job", instance=~"$instance"})

(probe_ssl_earliest_cert_expiry{job=~"$job", instance=~"$instance"} - time()) / 3600 / 24
(probe_ssl_earliest_cert_expiry{job=~"blackbox-http-check", instance=~"https://www.domain.de/metrics"} - time()) / 3600 / 24

avg_over_time(probe_duration_seconds{job=~"blackbox-http-check", instance=~"https://www.domain.de/metrics"}[1m])

probe_tls_version_info{job=~"$job", instance=~"$instance"}
probe_http_version{job=~"$job", instance=~"$instance"}

## Debug Ausgabe vom Blackbox Server ausführen
##
curl -s "localhost:9115/probe?target=http://www.domain.de&module=http_2xx" | grep -v '^#'
curl -s "localhost:9115/probe?target=http://www.domain.de&module=tcp_connect" | grep -v '^#'
curl -s "localhost:9115/probe?target=http://www.domain.de&module=icmp" | grep -v '^#'

curl -s "localhost:9115/probe?target=http://www.domain.de&module=http_2xx&debug=true" | grep -v '^#'
curl -s "localhost:9115/probe?target=http://www.domain.de&module=tcp_connect&debug=true" | grep -v '^#'
curl -s "localhost:9115/probe?target=http://www.domain.de&module=icmp&debug=true" | grep -v '^#'

# Logs for the probe:
# ts=2024-12-18 caller=main.go:190 module=http_2xx target=http://www.domain.de level=info msg="Beginning probe" probe=http timeout_seconds=10
# ts=2024-12-18 caller=http.go:328 module=http_2xx target=http://www.domain.de level=info msg="Resolving target address" target=www.domain.de ip_protocol=ip4
# ts=2024-12-18 caller=http.go:328 module=http_2xx target=http://www.domain.de level=info msg="Resolved target address" target=www.domain.de ip=192.168.100.1
# ts=2024-12-18 caller=client.go:259 module=http_2xx target=http://www.domain.de level=info msg="Making HTTP request" url=http://192.168.100.1 host=www.domain.de
# ts=2024-12-18 caller=handler.go:119 module=http_2xx target=http://www.domain.de level=info msg="Received HTTP response" status_code=200
# ts=2024-12-18 caller=main.go:190 module=http_2xx target=http://www.domain.de level=info msg="Probe succeeded" duration_seconds=1.23230353

# ...
# probe_http_redirects 0
# probe_http_ssl 0
# probe_http_status_code 200
# probe_http_version 1.1
# probe_ip_protocol 4
# probe_success 1

# Module configuration:
# prober: http
# timeout: 10s
# http:
#   valid_http_versions:
#   - HTTP/1.1
#   - HTTP/2.0
#   preferred_ip_protocol: ip4
#   method: GET
#   tls_config:
#     insecure_skip_verify: true
#   follow_redirects: true
#   enable_http2: true
```
