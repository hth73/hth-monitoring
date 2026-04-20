# Setting up a monitoring environment using Docker Compose.

<img src="https://img.shields.io/badge/Raspberry%20Pi-A22846?style=flat&logo=Raspberry%20Pi&labelColor=ffffff&logoColor=A22846" /> <img src="https://img.shields.io/badge/Ubuntu%20Server-E95420?style=flat&logo=Ubuntu&labelColor=ffffff&logoColor=E95420" /> <img src="https://img.shields.io/badge/Docker%20Compose-2496ED?style=flat&logo=docker&labelColor=ffffff&logoColor=2496ED" /> <img src="https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" /> <img src="https://img.shields.io/badge/Node%20Exporter-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" /> <img src="https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" /> <img src="https://img.shields.io/badge/Grafana%20Loki-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" /> <img src="https://img.shields.io/badge/Grafana%20Alloy-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" /> <img src="https://img.shields.io/badge/Caddy-1F88C0?style=flat&logo=caddy&labelColor=ffffff&logoColor=1F88C0" /> <img src="https://img.shields.io/badge/dnsmasq-6d06aa?style=flat&logo=nextdns&labelColor=ffffff&logoColor=6d06aa" /> <img src="https://img.shields.io/badge/Pocked%20ID-262626?style=flat&logo=passport&labelColor=ffffff&logoColor=262626" />

---

### Inhaltsverzeichnis

* [DNS Server](config/dnsmasq/README.md)
* [Prometheus Server](config/prometheus/README.md)
* [Grafana Server](config/grafana/README.md)
* [Loki Server](config/loki/README.md)

---

## Beschreibung

In meinem Homelab betreibe ich einen Monitoring Stack bestehend aus Prometheus, Grafana und Loki sowie weiteren Komponenten (siehe Badges). Dieses Repository beschreibt die eingesetzte Architektur und zeigt, wie das Setup verwendet und angepasst werden kann.

Ein zentrales Ziel des Setups ist es, alle Services über vollständig qualifizierte Domainnamen (FQDN) erreichbar zu machen. Dadurch entsteht eine konsistente und realitätsnahe Umgebung, ähnlich wie in produktiven Infrastrukturen.

Für die interne Namensauflösung kommt `dnsmasq` zum Einsatz. Die TLS-Terminierung sowie die Ausstellung und Verwaltung von Zertifikaten erfolgt über `Caddy`. Dabei werden ausschließlich interne (self-signed) Zertifikate verwendet, sodass alle Services verschlüsselt über HTTPS erreichbar sind.

Die Reihenfolge und Abhängigkeiten der einzelnen Services sind weiter oben im Repository dokumentiert (siehe Inhaltsverzeichnis).

Das Repository dient sowohl als Referenz für andere als auch als persönliche Dokumentation zum Nachschlagen.

Ich versuche, alle relevanten Schritte möglichst detailliert zu dokumentieren, um die Nachvollziehbarkeit zu gewährleisten. Aufgrund der Vielzahl an Komponenten kann es dennoch zu abweichendem Verhalten in anderen Umgebungen kommen.

Das hier enthaltene Setup läuft in meiner Umgebung stabil und wird bei Bedarf kontinuierlich angepasst und erweitert.

---

### Raspberry Pi Setup

- Pironman 5 NVMe M.2 SSD PCIe Mini PC Case for Raspberry Pi 5
- Crucial SSD M.2 PCIe Gen4 NVMe Hard Drive
- Raspberry Pi 5 (16GB)
- Adapter/Gehäuse für M.2 NVMe PCIe mit USB-C Kabel
- SD-Karte für den ersten Boot (~16GB)

Um die SD-Karte und die NVMe vorzubereiten, installiere ich mir den Raspberry Pi Imager.
https://www.raspberrypi.com/software/

Jetzt kopiere man das Ubuntu Server 24.04 ARM Image über das Raspberry Pi Imager Tool auf die SD-Karte und die NVMe Platte.
Bevor die SD-Karte und die NVMe unmountet wird, müssen noch ein paar Anpassungen in dem Image gemacht werden.

### NVMe Boot vorbereiten

```bash
## Config.txt anpassen (auf der NVMe /boot/firmware/config.txt)

[all]
#arm_64bit=1
#kernel=vmlinuz
#cmdline=cmdline.txt
#initramfs initrd.img followkernel
dtparam=pciex1_gen=3 # Dieser Parameter aktiviert den PCI Express Port mit der Generation 3 auf dem Raspberry Pi 5
```

### Bootloader konfigurieren
Jetzt wird alles zusammengebaut, der Rasperry Pi wird mit der SD-Karte und eingebauter NVMe das erste mal gestartet.
Danach muss der Bootloader konfiguriert werden, damit der Rasperry Pi über die NVMe Festplatte startet.

```bash
## Konfiguration ansehen
sudo rpi-eeprom-config

## Bootloader editieren
sudo -E rpi-eeprom-config --edit

BOOT_ORDER=0xf416 # Diese Einstellung muss angepasst werden! Damit versucht der Pi zuerst von der NVMe zu booten.
PCIE_PROBE=1 # Diese Einstellung ist wichtig, wenn der NVMe-Adapter kein offizieller Raspberry Pi HAT+ ist (was bei 95 % der Adapter so ist)

# Bedeutung:
# 4 = NVMe/PCIe Boot
# 1 = SD Boot
# 6 = USB Boot
# f = wiederholen

## Bootloader aktualisieren und Neu starten
sudo rpi-eeprom-update -a
sudo reboot
```

```bash
lsblk          
# NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
# loop0         7:0    0  42.9M  1 loop /snap/snapd/24787
# nvme0n1     259:0    0 465.8G  0 disk 
# |-nvme0n1p1 259:1    0   512M  0 part /boot/firmware
# `-nvme0n1p2 259:2    0 465.3G  0 part /

sudo dmesg | grep -i nvme
# [    2.487401] nvme nvme0: pci function 0000:01:00.0
# [    2.492132] nvme 0000:01:00.0: enabling device (0000 -> 0002)
# [    2.534057] nvme nvme0: 4/0/0 default/read/poll queues
# [    2.540775]  nvme0n1: p1 p2
# [    3.943694] EXT4-fs (nvme0n1p2): mounted filesystem 9276ecfd-6dd5-4e22-9a91-2afafd0a53a3 ro with ordered data mode. Quota mode: none.
# [    4.920132] EXT4-fs (nvme0n1p2): re-mounted 9276ecfd-6dd5-4e22-9a91-2afafd0a53a3 r/w. Quota mode: none.
# [   12.986381] block nvme0n1: No UUID available providing old NGUID
```

### Netzwerkkarte konfigurieren

```bash
sudo vi /etc/netplan/50-cloud-init.yaml
# network:
#   version: 2
#   renderer: networkd
#   ethernets:
#     eth0:
#       dhcp4: no
#       addresses:
#         - 192.168.178.3/24
#       routes:
#         - to: default
#           via: 192.168.178.1
#       nameservers:
#         addresses: [192.168.178.1, 8.8.8.8]
#         search: [htdom.local]

sudo netplan apply
```

### Pironman5 Software installieren
Die Lüfter sind noch extrem laut und das Display von dem Gehäuse funktioniert noch nicht.

```bash
## Dokumentation
## https://docs.sunfounder.com/projects/pironman5/de/latest/pironman5/set_up/set_up_rpi_os.html
sudo apt update && sudo apt install git python3 python3-pip python3-setuptools -y

cd ~
git clone -b base https://github.com/sunfounder/pironman5.git --depth 1
cd ~/pironman5
sudo python3 install.py
sudo reboot
```

Nachdem die Software installiert wurde, reagiert das Display und zeigt Daten an.

```bash
## Der passende Pironman 5 Service
sudo systemctl status pironman5.service
sudo systemctl [start/stop/restart/enable] pironman5.service

## Dashboard
http://mina.htdom.local:34001

## Weitere Konfigurations Möglichkeiten
## https://docs.sunfounder.com/projects/pironman5/de/latest/pironman5/control/control_with_commands.html#anzeige-der-grundkonfigurationen
sudo pironman5 -c
                    
# {
#     "system": {
#         "data_interval": 1,
#         "rgb_color": "#0a1aff",
#         "rgb_brightness": 50,
#         "rgb_style": "breathing",
#         "rgb_speed": 50,
#         "rgb_enable": true,
#         ...
```

```bash
## Lüfter konfigurieren (Default = 0)
sudo pironman5 -gm 2

# 4: Leise: Die RGB-Lüfter werden bei 70°C aktiviert.
# 3: Ausgewogen: Die RGB-Lüfter werden bei 67,5°C aktiviert.
# 2: Kühl: Die RGB-Lüfter werden bei 60°C aktiviert.
# 1: Leistung: Die RGB-Lüfter werden bei 50°C aktiviert.
# 0: Immer An: Die RGB-Lüfter sind immer eingeschaltet.
```
### System Locale konfigurieren

```bash
## perl: warning: Please check that your locale settings:
sudo vi /etc/default/locale

# Default Ubuntu locale
LANG=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_ALL=en_US.UTF-8

sudo reboot
```

### Software auf dem Raspberry Pi installieren

```bash
sudo apt update && sudo apt upgrade -y

# https://docs.docker.com/engine/install/ubuntu
# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl git vim
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER

sudo systemctl enable --now docker
sudo systemctl status docker
```
