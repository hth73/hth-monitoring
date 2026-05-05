# Samba 4 - Active Directory (Ersatz)

<img src="https://img.shields.io/badge/Samba%204-2196F3?style=flat&logo=codesandbox&labelColor=ffffff&logoColor=2196F3" />

---

[Back home](../README.md)

* [Vorbereitung für den Samba Server](#vorbereitung-für-den-samba-server)
* [Samba Docker Image](#samba-docker-images)
* [Samba Container](#grafana-alloy-agent-installieren)

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

Für den Betrieb des Samba Active Directory Domain Controllers wurde bewusst ein eigenes Docker-Image erstellt, anstatt ein bestehendes Standard-Image zu verwenden.

Der Hauptgrund hierfür ist die vollständige Kontrolle über die Konfiguration und das Verhalten des Systems. Standard-Images sind häufig generisch aufgebaut, enthalten nicht benötigte Komponenten oder lassen sich nur eingeschränkt an spezifische Anforderungen anpassen. In dieser Umgebung war es jedoch notwendig, den Provisionierungsprozess, die DNS-Konfiguration sowie die Integration eigener `Caddy` TLS-Zertifikate gezielt zu steuern.

Durch das eigene Image kann der Initialisierungsprozess (Entrypoint) exakt definiert werden. Dazu gehören unter anderem die automatisierte Domain-Provisionierung, das idempotente Anpassen der smb.conf, das Setzen von DNS-Forwardern sowie die Integration von Zertifikaten für LDAPS. Dies ermöglicht einen reproduzierbaren und konsistenten Aufbau der Umgebung.

```bash

```


