# Samba 4 - Active Directory (Ersatz)

<img src="https://img.shields.io/badge/Samba%204-2196F3?style=flat&logo=simkl&labelColor=ffffff&logoColor=2196F3" />

---

[Back home](../README.md)

* [Vorbereitung für den Samba Server](#vorbereitung-für-den-samba-server)
* [Samba Docker Image](#samba-docker-images)
* [Samba Docker Container](#samba-docker-container)
* [Domain Checks](#domain-checks)
* [Kerberos einrichten](#kerberos-einrichten)
* [Windows Client der Domain hinzufügen](#windows-client-der-domain-hinzufügen)

---

## Beschreibung
In dieser Umgebung wird Samba als Active Directory Domain Controller (AD DC) eingesetzt, um eine zentrale Identitäts- und Infrastrukturverwaltung bereitzustellen, ohne auf proprietäre Microsoft-Serverlösungen angewiesen zu sein. Samba implementiert die wesentlichen AD-Funktionen wie LDAP, Kerberos und DNS und ermöglicht damit eine vollständige Integration von Linux- und Windows-Systemen in einer gemeinsame Domäne.

Der integrierte DNS-Server ist dabei ein zentraler Bestandteil der Architektur. Er stellt die notwendige Namensauflösung sowie die für Active Directory erforderlichen SRV-Records bereit, die für Kerberos-Authentifizierung, Service Discovery und Domain-Join-Prozesse zwingend notwendig sind. Durch die Kombination aus Samba AD und internem DNS entsteht eine konsistente und autoritative Namensauflösung innerhalb der Domäne.

Der Einsatz von Samba AD verfolgt mehrere Ziele:
Zum einen ermöglicht er eine zentrale Benutzer- und Gruppenverwaltung, wodurch Authentifizierung und Autorisierung systemübergreifend vereinheitlicht werden. Zum anderen bildet er die Grundlage für Single Sign-On (SSO), sodass Benutzer sich einmal anmelden und anschließend auf verschiedene Dienste wie Grafana, interne Webanwendungen oder zukünftige OIDC-/LDAP-basierte Systeme zugreifen können.

Darüber hinaus dient die Lösung als Integrationspunkt für weitere Infrastrukturkomponenten. Dienste wie Reverse Proxy (Caddy), Monitoring (Prometheus, Grafana, Blackbox Exporter) oder zukünftige Authentifizierungsdienste (z. B. Authelia) können direkt an das Verzeichnis angebunden werden. Dadurch entsteht eine klar strukturierte, zentral verwaltete und erweiterbare Infrastruktur.

## Vorbereitung für den Samba Server

Damit sich der Samba Active Directory Domain Controller wie ein vollwertiger Domain Controller im Netzwerk verhält, wird ein `Macvlan-Netzwerk` eingesetzt. Dieses ermöglicht es, Containern eine eigene IP-Adresse im lokalen Netzwerk zuzuweisen.

Dadurch treten die Dienste als eigenständige Netzwerkteilnehmer mit eigener MAC- und IP-Adresse auf und sind direkt im LAN erreichbar. Eine Umsetzung über NAT oder Port-Mapping ist somit nicht erforderlich.

Insbesondere für Infrastrukturkomponenten wie Samba AD mit DNS, Kerberos und LDAP ist dieses Verhalten essenziell, da diese Dienste eine direkte und konsistente Erreichbarkeit im Netzwerk voraussetzen.

```bash
docker network create -d macvlan \
  --subnet=192.168.178.0/24 \
  --gateway=192.168.178.1 \
  -o parent=eth0 \
  macvlan_ad

docker network inspect macvlan_ad
```

Da Container im `Macvlan-Netzwerk` standardmäßig nicht direkt vom Docker-Host erreichbar sind, wurde auf dem Host ein zusätzliches Macvlan-Interface konfiguriert (nicht persistent).

Dieses Interface ermöglicht die Kommunikation zwischen dem Host-System und den im Macvlan-Netzwerk betriebenen Containern, indem eine direkte Route zum Container-Netz geschaffen wird.

`Nach einem Reboot des Raspberry Pi's, muss die konfiguration neu gesetzt werden!`

```bash
# Interface erstelle
sudo ip link add macvlan0 link eth0 type macvlan mode bridge

## IP vergeben (freie IP im gleichen Netzwerk)
sudo ip addr add 192.168.178.200/24 dev macvlan0

## Interface aktivieren
sudo ip link set macvlan0 up

## Route setzen
sudo ip route add 192.168.178.50 dev macvlan0
```

## Samba Docker Images

Für den Betrieb des Samba Active Directory Domain Controllers wurde ein eigenes Docker-Image erstellt, anstatt ein bestehendes Standard-Image zu verwenden.

Der Hauptgrund war die vollständige Kontrolle über die Konfiguration und das Verhalten des Systems. Standard-Images sind häufig generisch aufgebaut, enthalten nicht benötigte Komponenten oder lassen sich nur eingeschränkt an spezifische Anforderungen anpassen. In dieser Umgebung war es jedoch notwendig, den Provisionierungsprozess, die DNS-Konfiguration sowie die Integration eigener `Caddy` TLS-Zertifikate gezielt zu steuern.

Durch das eigene Image kann der Initialisierungsprozess (Entrypoint) exakt definiert werden. Dazu gehören unter anderem die automatisierte Domain-Provisionierung, das idempotente Anpassen der `smb.conf`, das Setzen von DNS-Forwardern sowie die Integration von `Caddy` Zertifikaten für LDAPS. Dies ermöglicht einen reproduzierbaren und konsistenten Aufbau der Umgebung.

### Dockerfile
```bash
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
      samba \
      krb5-user \
      winbind \
      smbclient \
      dnsutils \
      iproute2 \
      procps \
      ldap-utils \
      && rm -rf /var/lib/apt/lists/*

# Entrypoint Script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/var/lib/samba", "/etc/samba"]

EXPOSE 53 88 135 137/udp 138/udp 139 389 445 464 636

ENTRYPOINT ["/entrypoint.sh"]
```

### entrypoint.sh

```bash
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

# --- default smb.conf vor erstem provisioning löschen
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

# --- sicherstellen dass neue smb.conf existiert
if [ ! -f "$SMB_CONF" ]; then
  echo "ERROR: smb.conf missing after provisioning!"
  exit 1
fi

# --- TLS-Certs von Caddy unter [global] einfügen
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

# --- DNS Forwarder setzen
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
```

## Samba Docker Container

### Samba Ordner Struktur und Caddy Zertifikate

```bash
sudo mkdir -p /opt/samba/certs
sudo chmod -R 0750 /opt/samba

sudo cp /opt/caddy/data/caddy/pki/authorities/local/root.crt /opt/samba/certs
sudo cp /opt/caddy/data/caddy/certificates/local/dc.htdom.lan/dc.htdom.lan.crt /opt/samba/certs
sudo cp /opt/caddy/data/caddy/certificates/local/dc.htdom.lan/dc.htdom.lan.key /opt/samba/certs

sudo chmod 0644 "/opt/samba/certs/root.crt"
sudo chmod 0644 "/opt/samba/certs/dc.htdom.lan.crt"
sudo chmod 0600 "/opt/samba/certs/dc.htdom.lan.key"
```

### docker-compose.yaml

Das `ADMIN_PASSWORD` wurde in eine `.env` Datei ausgelagert.

```bash
---
x-dns: &default-dns
  dns:
    - 192.168.178.50
    - 192.168.178.1
...
networks:
  ...
  macvlan_ad:
    external: true

services:
  dc:
    build: ./samba
    container_name: dc
    hostname: dc.htdom.lan
    privileged: true
    networks:
      macvlan_ad:
        ipv4_address: 192.168.178.50
    dns:
      - 127.0.0.1
    restart: always
    volumes:
      - "/opt/samba:/var/lib/samba"
      - "/opt/samba/certs:/certs:ro"
    environment:
      - REALM=HTDOM.LAN
      - DOMAIN=HTDOM
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - DNS_FORWARDER=192.168.178.1
```

## Domain Checks

Es benötigte einige durchgänge bis der Samba DC erfolgreich lief. Die Domain-Provisionierung konnte leider immer nur einmal duchgeführt werden. Für jede relevante Konfigurationsänderung war daher ein vollständiger Reset des persistenten Datenverzeichnisses `/opt/samba` erforderlich.

Darüber hinaus mussten Änderungen am Entrypoint-Skript durch einen erneuten Build des Docker-Images in den Container integriert werden. Dieser Prozess erhöhte den initialen Aufwand, führte jedoch zu einer klar definierten und reproduzierbaren Bereitstellung des Systems.

Aber irgendwann lief der Container und es konnte getestet werden:

```bash
nslookup dc.htdom.lan 192.168.178.50
nslookup -type=SRV _ldap._tcp.htdom.lan 192.168.178.50
nslookup -type=SRV _kerberos._udp.htdom.lan 192.168.178.50

nc -zv dc.htdom.lan 636
# Connection to dc.htdom.lan (192.168.178.50) 636 port [tcp/ldaps] succeeded!

docker exec -it dc dig dc.htdom.lan @127.0.0.1
# ...
# ;; QUESTION SECTION:
# ;dc.htdom.lan.      IN  A

# ;; ANSWER SECTION:
# dc.htdom.lan.   900 IN  A 192.168.178.50

# ;; AUTHORITY SECTION:
# htdom.lan.    3600  IN  SOA dc.htdom.lan. hostmaster.htdom.lan. 12 900 600 86400 3600

LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://dc.htdom.lan -D "Administrator@htdom.lan" -w 'MySuperSecurePWD!' -b "DC=htdom,DC=lan" -s base
# # extended LDIF
# #
# # LDAPv3
# # base <DC=htdom,DC=lan> with scope baseObject
# ...

# # htdom.lan
# dn: DC=htdom,DC=lan
# objectClass: top
# objectClass: domain
# objectClass: domainDNS
# ...
# uSNCreated: 10
# name: htdom
# ...
# objectCategory: CN=Domain-DNS,CN=Schema,CN=Configuration,DC=htdom,DC=lan
```

## Kerberos einrichten

```bash
sudo apt install krb5-user -y
sudo vi /etc/krb5.conf

# ---

[logging]
  default = FILE:/var/log/krb5/krb5.log
  kdc = FILE:/var/log/krb5/krb5kdc.log
  admin_server = FILE:/var/log/krb5/kadmind.log

[libdefaults]
  default_realm = HTDOM.LAN
  dns_lookup_realm = true
  dns_lookup_kdc = true
  ticket_lifetime = 24h
  renew_lifetime = 7d
  forwardable = true

## The following krb5.conf variables are only for MIT Kerberos.
  kdc_timesync = 1
  ccache_type = 4
  forwardable = true
  proxiable = true

[realms]
  HTDOM.LAN = {
    kdc = dc.htdom.lan
    admin_server = dc.htdom.lan
}

[domain_realm]
  .htdom.lan = HTDOM.LAN
  htdom.lan = HTDOM.LAN
```

```bash
nc -zv 192.168.178.50 88  # TCP Port 88
nc -zvu 192.168.178.50 88 # UDP Port 88
nmap -sU -p 88 192.168.178.50
host -t SRV _kerberos._udp.htdom.lan 192.168.178.50

# KRB5_TRACE=/dev/stdout kinit Administrator@HTDOM.LAN
kinit administrator@HTDOM.LAN
klist
# Ticket cache: FILE:/tmp/krb5cc_1000
# Default principal: Administrator@HTDOM.LAN

# Valid starting       Expires              Service principal
# 04/28/2026 19:15:12  04/29/2026 05:15:12  krbtgt/HTDOM.LAN@HTDOM.LAN
#   renew until 05/05/2026 19:15:08

smbclient -L //dc.htdom.lan -U Administrator@HTDOM.LAN --use-kerberos=required
# Password for [Administrator@HTDOM.LAN]:

#   Sharename       Type      Comment
#   ---------       ----      -------
#   sysvol          Disk      
#   netlogon        Disk      
#   IPC$            IPC       IPC Service (Samba 4.17.12-Debian)
# SMB1 disabled -- no workgroup available
```

## Windows Client der Domain hinzufügen

In diesen Setup wird ein Windows 11 Client als Verwaltungseinheit genutzt, das Computerkonto wird der Domäne hinzugefügt und auf dem Client werden die AD-DC RSAT Tools installiert um die Samba Domänen verwalten zu können.

```powershell
## IPv6 muss auf dem Client deaktiviert werden, um mit der Samba Domäne kommunizieren zu können.
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6

## DNS Server setzen
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("192.168.178.50")
Get-DnsClientServerAddress

ipconfig /flushdns
ipconfig /displaydns

ping dc.htdom.lan
ping htdom.lan
nslookup dc.htdom.lan

nslookup -type=SRV _kerberos._udp.htdom.lan
nslookup -type=SRV _ldap._tcp.htdom.lan

## Computerkonto der Domäne hinzufügen
Add-Computer -DomainName "htdom.lan" -NewName "adm01" -Restart

## RSAT Tools installieren
Windows + I --> System --> Optional Features --> RSAT Tools
```
