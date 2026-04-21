# Loki Server

<img src="https://img.shields.io/badge/Grafana%20Loki-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" />

---

[Back home](../../README.md)

---

## Beschreibung
Für die zentrale Verarbeitung und Analyse von Logdaten wird in diesem Setup Grafana Loki eingesetzt. Loki ist ein Log-Aggregationssystem, das speziell für die Integration mit Grafana entwickelt wurde und sich durch eine effiziente, labelbasierte Speicherung auszeichnet.

Die Logs der einzelnen Systeme werden über einen Agent gesammelt und anschließend an den Loki-Server übertragen.

Anfangs wurde hierfür der Grafana Promtail Agent verwendet. Da Promtail jedoch Ende März 2026 das End-of-Life (EOL) erreicht, wird in diesem Setup der Grafana Alloy Agent als Alternative eingesetzt.

Grafana Alloy übernimmt dabei die Rolle des Log-Collectors und sendet die gesammelten Logdaten an Loki.

## Loki Ordner-Struktur

```bash
mkdir -p ~/docker/config/loki
chmod -R 755 ~/docker/config/loki

sudo mkdir -p /opt/loki/data
sudo chown -R 10001:10001 /opt/loki/data
sudo chmod -R 750 /opt/loki/data
```

## Loki Server Konfiguration

```bash
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  grpc_server_max_recv_msg_size: 104857600 # 100 Mb
  grpc_server_max_send_msg_size: 104857600 # 100 Mb

ingester_client:
  grpc_client_config:
    max_recv_msg_size: 104857600 # 100 Mb
    max_send_msg_size: 104857600 # 100 Mb

ingester:
  chunk_encoding: snappy
  chunk_idle_period: 3h
  chunk_target_size: 3072000
  max_chunk_age: 2h

  wal:
    dir: /loki/wal
    flush_on_shutdown: true

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2023-01-05
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: loki_index_
        period: 24h

limits_config:
  ingestion_rate_mb: 20
  ingestion_burst_size_mb: 30
  per_stream_rate_limit: "3MB"
  per_stream_rate_limit_burst: "10MB"
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  retention_period: 744h
  max_query_length: 0h
```

## Docker Compose Datei

```yaml
...

services:
  ...
  
  loki:
    image: docker.io/grafana/loki:3.7.1
    container_name: loki
    hostname: loki
    user: "10001:10001"
    networks: [homenet]
    restart: always
    <<: [*default-dns, *default-security]
    tmpfs:
      - /tmp
    volumes:
      - "./config/loki/loki-config.yaml:/etc/loki/loki-config.yaml:ro"
      - "/opt/loki/data:/loki"
    command: 
      -config.file=/etc/loki/loki-config.yaml
      -config.expand-env=true
    ports:
      - "3100:3100"
```

## Loki Web Endpoints

```bash
https://loki.htdom.local/ready
https://loki.htdom.local/config
https://loki.htdom.local/metrics
https://loki.htdom.local/ring
```

## Beispiel Abfragen ob Loki Daten zurückliefert

```bash
## https://loki.htdom.local/ready
## https://loki.htdom.local/metrics
##
curl -Gk -s "https://loki.htdom.local/loki/api/v1/labels" | jq -r '.'
curl -Gk -s "https://loki.htdom.local/loki/api/v1/label/host/values" | jq -r '.data[]'
curl -Gk -s "https://loki.htdom.local/loki/api/v1/query_range" --data-urlencode 'query=sum(rate({job="varlogs"}[10m])) by (level)' --data-urlencode 'step=300' | jq
curl -Gk -s "https://loki.htdom.local/loki/api/v1/query_range" --data-urlencode 'query={job="varlogs"}' | jq -r '.'

curl -sk "https://loki.htdom.local/loki/api/v1/series" --data-urlencode 'match[]={host=~"mina.*"}' | jq -r '.'
curl -sk "https://loki.htdom.local/loki/api/v1/series" --data-urlencode 'match[]={syslog_identifier=~"sshd*"}' | jq -r '.'
curl -sk "https://loki.htdom.local/loki/api/v1/series" --data-urlencode 'match[]={priority=~"error*"}' | jq -r '.'

curl -Gk -s "https://loki.htdom.local/loki/api/v1/query" --data-urlencode 'query=sum(rate({syslog_identifier="sshd"}[30m])) by (unit)' | jq -r '.'
curl -Gk -s "https://loki.htdom.local/loki/api/v1/query_range" --data-urlencode 'query={syslog_identifier="sshd"}' | jq -r '.'

## Unix Timestamp berücksichtigen beim hinzufügen von Datensätzen (--> [1715785516]000000000 <--)
## https://www.unixtimestamp.com/

## Daten an Loki senden und wieder abfragen
##
curl -Sk -H "Content-Type: application/json" -XPOST -s https://loki.htdom.local/loki/api/v1/push --data-raw '{"streams": [{ "stream": { "app": "app1" }, "values": [ [ "1715785516000000000", "random log line" ] ] }]}'

## entry for stream '{app="app1"}' has timestamp too old: 2022-05-29T20:18:38Z, oldest acceptable timestamp is: 2024-05-08T15:02:04Z

curl -k https://loki.htdom.local/loki/api/v1/labels
## {"status":"success","data":["_cmdline","_priority","app","host_name","job","priority","syslog_identifier","transport","unit"]}

curl -k https://loki.htdom.local/loki/api/v1/label/app/values
## {"status":"success","data":["app1"]}

curl -Gk -Ss https://loki.htdom.local/loki/api/v1/query_range --data-urlencode 'query={app="app1"}' | jq -r '.'
# {
#   "status": "success",
#   "data": {
#     "resultType": "streams",
#     "result": [
#       {
#         "stream": {
#           "app": "app1"
#         },
#         "values": [
#           [
#             "1715785516000000000",
#             "random log line"
#           ]
#         ]
#       }
#     ],
```