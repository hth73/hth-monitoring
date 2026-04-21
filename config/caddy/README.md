# Reverse Proxy & PKI & Container Hardening

<img src="https://img.shields.io/badge/Caddy-1F88C0?style=flat&logo=caddy&labelColor=ffffff&logoColor=1F88C0" />

---

[Back home](../../README.md)<br>

[Container Hardening (Docker Compose)](#container-hardening-docker-compose)<br>
[YAML Anchors (Wiederverwendbare Konfiguration)](#yaml-anchors-wiederverwendbare-konfiguration)

---

## Beschreibung

Um alle Container über HTTPS abzusichern, wird ein Reverse Proxy auf Basis von `Caddy` eingesetzt. Caddy ist ein Open-Source-Webserver, der sich insbesondere durch die automatische Verwaltung von TLS-Zertifikaten auszeichnet. In diesem Setup werden interne (Self-signed) Zertifikate verwendet.

Der Reverse Proxy übernimmt die TLS-Terminierung und stellt sicher, dass alle Services verschlüsselt über ihre jeweiligen FQDNs erreichbar sind. Eingehende HTTP/HTTPS-Anfragen werden dabei zentral entgegengenommen und an die entsprechenden Container im Hintergrund weitergeleitet.


## Caddy Ordner-Struktur

```bash
mkdir -p ~/docker/config/caddy
chmod -R 755 ~/docker/config/caddy

sudo mkdir -p /opt/caddy/{data,config}
sudo chown -R 65534:65534 /opt/caddy
sudo chmod -R 750 /opt/caddy

## Hier findet man später alle Zertifikate für die Umgebung
##
sudo ls -la /opt/caddy/data/caddy/pki/authorities/local 
# -rwxr-x--- 1 nobody nogroup  680 Apr 19 14:35 intermediate.crt
# -rwxr-x--- 1 nobody nogroup  227 Apr 19 14:35 intermediate.key
# -rwxr-x--- 1 nobody nogroup  631 Apr 19 14:35 root.crt
# -rwxr-x--- 1 nobody nogroup  227 Apr 19 14:35 root.key

sudo ls -la /opt/caddy/data/caddy/certificates/local 
# drwxr-x--- 2 nobody nogroup 4096 Apr 20 16:18 grafana.htdom.local
# drwxr-x--- 2 nobody nogroup 4096 Apr 20 17:08 loki.htdom.local
# drwxr-x--- 2 nobody nogroup 4096 Apr 20 14:58 prometheus.htdom.local
```

## Caddyfile

```bash
## Caddyfile für die Weiterleitung und Zertifikatserstellung anlegen
##
vi ~/docker/config/caddy/Caddyfile

grafana.htdom.local {
  reverse_proxy http://grafana.htdom.local:3000
  tls internal
}

loki.htdom.local {
  reverse_proxy http://loki.htdom.local:3100
  tls internal
}

prometheus.htdom.local {
  reverse_proxy http://prometheus.htdom.local:9090
  tls internal
}
```

## Container Hardening (Docker Compose)

Zur Absicherung der Container wird ein minimaler Sicherheits-Standard umgesetzt. Ziel ist es, die Angriffsfläche zu reduzieren und nur die unbedingt notwendigen Rechte zu vergeben ("Least Privilege").

`read_only: true` setzt das Root-Filesystem des Containers auf "read-only". Dadurch können Prozesse im Container keine Änderungen außerhalb definierter Volumes vornehmen.

```bash
  read_only: true
```

`security_opt: no-new-privileges` verhindert, dass Prozesse innerhalb des Containers zusätzliche Privilegien erlangen (z. B. über setuid-Binaries).

```bash
  security_opt:
    - no-new-privileges:true
```

`cap_drop: ALL` Entfernt alle Linux-Capabilities vom Container. Linux-Capabilities sind feingranulare Kernel-Rechte (z. B. Netzwerk- oder Systemzugriffe).

```bash
  cap_drop:
    - ALL
```

`cap_add (gezielte Freigabe)` fügt gezielt benötigte Capabilities wieder hinzu. `NET_BIND_SERVICE` erlaubt das binden an privilegierte Ports (<1024), z. B. Port 80 oder 443.

```bash
  cap_add:
    - NET_BIND_SERVICE
```

`tmpfs` bindet ein temporäres Dateisystem im RAM ein. Vorteil davon ist: keine persistenten Daten auf Festplatte, schnellerer Zugriff und automatische Bereinigung beim Container-Neustart

```bash
  tmpfs:
    - /tmp
```

## YAML Anchors (Wiederverwendbare Konfiguration)

Um wiederkehrende Konfigurationen zu vermeiden, werden sogenannte YAML Anchors verwendet. Der Anchor wird mit `&default-dns` oder `&default-security` definiert und kann später in einer YAML Datei referenziert werden.

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
  tmpfs:
    - /tmp
```

Verwendung in einer YAML Datei (docker-compose.yaml)

```bash
services:
  grafana:
    image: docker.io/grafana/grafana:13.0.1
    ...
    <<: *default-dns
```

Mehrere Anchors können kombiniert werden, um z. B. DNS- und Security-Konfiguration gemeinsam zu nutzen.

```bash
<<: [*default-dns, *default-security]
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
  tmpfs:
    - /tmp

networks:
  homenet:
    name: homenet
    driver: bridge

services:
  dnsmasq:
    ...

  caddy:
    image: docker.io/caddy:2.11.2
    container_name: caddy
    hostname: caddy
    user: "65534:65534"
    networks: [homenet]
    restart: always
    <<: [*default-dns, *default-security]
    cap_add:
      - NET_BIND_SERVICE
    volumes:
      - "./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
      - "/opt/caddy/data:/data"
      - "/opt/caddy/config:/config"
    ports:
      - "80:80"
      - "443:443"
```
