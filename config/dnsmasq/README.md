# DNS Server

<img src="https://img.shields.io/badge/dnsmasq-6d06aa?style=flat&logo=nextdns&labelColor=ffffff&logoColor=6d06aa" />

---

[back to home](../../README.md)

---

## Beschreibung

Um auf dem Raspberry Pi einen eigenen DNS-Server zu betreiben, sind einige Anpassungen am lokalen System erforderlich. Diese betreffen insbesondere die bestehende Namensauflösung und die Integration mit Docker.

Das hier beschriebene Setup basiert auf mehreren aufeinander aufbauenden Komponenten. In diesem Abschnitt wird ausschließlich der DNS-Server `dnsmasq` betrachtet. Das vollständige Zusammenspiel aller Services ist in den anderen Abschnitten dokumentiert.

Der DNS-Server übernimmt die interne Namensauflösung im Homelab und stellt sicher, dass alle Services über ihre jeweiligen FQDNs erreichbar sind. Externe Anfragen werden an den Upstream-DNS (z. B. den Router) weitergeleitet.

Erst in Kombination mit den weiteren Komponenten (insbesondere Reverse Proxy und TLS) ergibt sich das vollständige und funktionierende Gesamtsystem.

### Allgemeine Docker Ordner-Struktur starten
```bash
mkdir -p ~/docker/config/dnsmasq
chmod -R 755 ~/docker/config/dnsmasq
```

### dnsmasq Container Vorbereitung

```bash
sudo vi ~/docker/config/dnsmasq/dnsmasq.conf

interface=eth0
domain=htdom.local
local=/htdom.local/
host-record=caddy.htdom.local,192.168.178.3
host-record=dns.htdom.local,192.168.178.3
host-record=grafana.htdom.local,192.168.178.3
host-record=loki.htdom.local,192.168.178.3
host-record=mina.htdom.local,192.168.178.3
host-record=prometheus.htdom.local,192.168.178.3

# Weiterleitung aller anderen Anfragen an den Upstream-DNS Server
server=192.168.178.1
```

### Docker Compose und Docker Environment Datei vorbereiten

```bash
sudo vi ~/docker/.env
FQDN=htdom.local

sudo vi ~/docker/docker-compose.yaml
dnsmasq:
  image: docker.io/dockurr/dnsmasq:2.92
  container_name: dns
  hostname: dns.${FQDN}
  network_mode: "host"
  restart: always
  volumes:
    - "./config/dnsmasq:/etc/dnsmasq.d"
  cap_add:
    - NET_ADMIN
  command: --interface=eth0 -r
```

### Raspberry Pi - DNS Server anpassen

```bash
sudo vi /etc/systemd/resolved.conf
[Resolve]
DNS=192.168.178.3 # DNS Container
FallbackDNS=192.168.178.1 # Upstream-DNS
DNSStubListener=no
Domains=htdom.local

# ---

sudo systemctl restart systemd-resolved
sudo systemctl status systemd-resolved
sudo reboot

# ---

cat /etc/resolv.conf
nameserver 192.168.178.3
nameserver 192.168.178.1
nameserver 8.8.8.8
# Too many DNS servers configured, the following entries may be ignored.
# ...
search htdom.local

# ---

resolvectl status
# Global
#            Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
#     resolv.conf mode: uplink
#          DNS Servers: 192.168.178.3
# Fallback DNS Servers: 192.168.178.1
#           DNS Domain: htdom.local

# Link 2 (eth0)
#     Current Scopes: DNS
#          Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
#        DNS Servers: 192.168.178.1 8.8.8.8 fd00::ca0e:14ff:fe74:63d 2001:9e8:a571:8000:ca0e:14ff:fe74:63d 2001:9e8:a57a:d00:ca0e:14ff:fe74:63d
#         DNS Domain: htdom.local

# ---

docker run --rm -it alpine cat /etc/resolv.conf                                                           
# ...
# nameserver 192.168.178.3
# nameserver 192.168.178.1
# search htdom.local

# ---

docker logs dns --follow
# dnsmasq: started, version 2.92 cachesize 150
# dnsmasq: compile time options: IPv6 GNU-getopt no-DBus no-UBus no-i18n no-IDN DHCP DHCPv6 no-Lua TFTP no-conntrack ipset no-nftset auth DNSSEC loop-detect inotify dumpfile
# dnsmasq: using nameserver 192.168.178.1#53
# ...
# dnsmasq: using only locally-known addresses for htdom.local
# dnsmasq: read /etc/hosts - 8 names
# dnsmasq: exiting on receipt of SIGTERM

# ---

sudo ps aux | grep dnsmasq
# /sbin/tini -- /usr/bin/dnsmasq.sh --interface=eth0 -r
# dnsmasq --conf-file=/etc/dnsmasq.custom --no-daemon --no-resolv

# ---

sudo lsof -i:53
# COMMAND   PID USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME
# dnsmasq 92383 root    4u  IPv4 4171368      0t0  UDP *:domain 
# dnsmasq 92383 root    5u  IPv4 4171369      0t0  TCP *:domain (LISTEN)
# dnsmasq 92383 root    6u  IPv6 4171370      0t0  UDP *:domain 
# dnsmasq 92383 root    7u  IPv6 4171371      0t0  TCP *:domain (LISTEN)

# ---

sudo netstat -tulnp | grep :53
# tcp        0      0 0.0.0.0:53              0.0.0.0:*               LISTEN      92383/dnsmasq       
# tcp6       0      0 :::53                   :::*                    LISTEN      92383/dnsmasq       
# udp        0      0 0.0.0.0:53              0.0.0.0:*                           92383/dnsmasq       
# udp        0      0 0.0.0.0:5353            0.0.0.0:*                           714/avahi-daemon: r 
# udp6       0      0 :::53                   :::*                                92383/dnsmasq       
# udp6       0      0 :::5353                 :::*                                714/avahi-daemon: r

# ---

nslookup mina.htdom.local 192.168.178.1
# Server:   192.168.178.1
# Address:  192.168.178.1#53

# ** server can't find mina.htdom.local: NXDOMAIN

# ---

nslookup mina.htdom.local 192.168.178.3
# Server:   192.168.178.3
# Address:  192.168.178.3#53

# Name: mina.htdom.local
# Address: 192.168.178.3
```
