# Node-Exporter (Metrics) & Grafana Alloy (Logs) Agents

<img src="https://img.shields.io/badge/Node%20Exporter-E6522C?style=flat&logo=prometheus&labelColor=ffffff&logoColor=E6522C" /> <img src="https://img.shields.io/badge/Grafana%20Alloy-F46800?style=flat&logo=grafana&labelColor=ffffff&logoColor=F46800" />

---

[Back home](../../README.md)

* [Node Exporter Agent installieren](#node-exporter-agent-installieren-und-mit-tls-absichern)
* [Windows Exporter Agent installieren](#windows-exporter-als-binary-installieren)
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
sudo chown -R root:node_exporter /etc/node_exporter
sudo chmod 0755 /etc/node_exporter

sudo mkdir /var/lib/node_exporter
sudo chown -R node_exporter:node_exporter /var/lib/node_exporter
sudo chmod 0750 /var/lib/node_exporter

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

```yaml
- job_name: 'grafana.htdom.lan'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ["grafana.htdom.lan"]
```

Das Bash Skript erzeugt eine neue Datei in dem Ordner `/etc/node_exporter` mit dem Namen `config.yaml` Diese wird als Startparameter in der Systemd Datei referenziert.

```yaml
tls_server_config:
  cert_file: /etc/node_exporter/mina.htdom.lan.crt
  key_file: /etc/node_exporter/mina.htdom.lan.key
```

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

## Windows Exporter als Binary installieren

Auf den Windows Servern wollte ich ursprünglich die vorgefertigte MSI Datei verwenden um diesen Agent installieren zu können.
Da es hier aber Probleme gab die Zertifikate im Setup Aufruf mitzugeben, haben ich mich entschieden, nur über das Binary zu arbeiten. Die Software wurde vorab heruntergeladen und in eine Windows Ordner Freigabe abgelegt. (\\server.domain.de\software$\windows_exporter)

Auf jeden Windows Server öffnet man dann einen Explorer und über die Adresszeile navigiert man dann zur Windows Ordner Freigabe. Danach startet man die vorab abgelegte Batch Datei "install_windows_exporter.cmd"

Diese Batchdatei installiert das Windows Exporter Binary, OpenSSL Light und erstellt das passende Self-Sign Zertifikat.
Damit am Schluss der Windows Service sauber läuft wurde der Service einmal komplett manuel eingerichtet und über die Windows Registry wurde ein fertiger Reg-Dump erstellt, dieser Reg-Dump wird später als Import in jeder Installation mitgegeben.

Windows Exporter --> https://github.com/prometheus-community/windows_exporter/releases-<br>
OpenSSL Light --> https://slproweb.com/products/Win32OpenSSL.html<br>
Windows Registry Pfad --> HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\windows_exporter

## config.yaml

```yaml
---
collectors:
  enabled:  cpu,cs,iis,logical_disk,net,os,service,system,logon,process,textfile
collector:
  service:
    services-where: Name='windows_exporter'
  scheduled_task:
    include: /Microsoft/.+
log:
  level: debug
scrape:
  timeout-margin: 0.5
telemetry:
  path: /metrics
  max-requests: 5
```

## windows_exporter.req (Example Code)

```powershell
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\windows_exporter]
"Type"=dword:00000010
"Start"=dword:00000002
"ErrorControl"=dword:00000001
"ImagePath"=hex(2):22,00,43,00,3a,00,5c,00,70,00,72,00,6f,00,6d,00,65,00,74,00,\
68,00,65,00,75,00,73,00,2d,00,65,00,78,00,70,00,6f,00,72,00,74,00,65,00,72,\
00,5c,00,77,00,69,00,6e,00,64,00,6f,00,77,00,73,00,5f,00,65,00,78,00,70,00,\
6f,00,72,00,74,00,65,00,72,00,2d,00,30,00,2e,00,32,00,35,00,2e,00,31,00,2e,\
00,65,00,78,00,65,00,22,00,20,00,2d,00,2d,00,63,00,6f,00,6e,00,66,00,69,00,\
67,00,2e,00,66,00,69,00,6c,00,65,00,3d,00,22,00,43,00,3a,00,5c,00,70,00,72,\
00,6f,00,6d,00,65,00,74,00,68,00,65,00,75,00,73,00,2d,00,65,00,78,00,70,00,\
6f,00,72,00,74,00,65,00,72,00,5c,00,63,00,6f,00,6e,00,66,00,69,00,67,00,2e,\
00,79,00,61,00,6d,00,6c,00,22,00,20,00,2d,00,2d,00,77,00,65,00,62,00,2e,00,\
63,00,6f,00,6e,00,66,00,69,00,67,00,2e,00,66,00,69,00,6c,00,65,00,3d,00,22,\
00,43,00,3a,00,5c,00,70,00,72,00,6f,00,6d,00,65,00,74,00,68,00,65,00,75,00,\
73,00,2d,00,65,00,78,00,70,00,6f,00,72,00,74,00,65,00,72,00,5c,00,77,00,65,\
00,62,00,63,00,6f,00,6e,00,66,00,69,00,67,00,2e,00,79,00,61,00,6d,00,6c,00,\
22,00,20,00,2d,00,2d,00,77,00,65,00,62,00,2e,00,6c,00,69,00,73,00,74,00,65,\
00,6e,00,2d,00,61,00,64,00,64,00,72,00,65,00,73,00,73,00,20,00,30,00,2e,00,\
30,00,2e,00,30,00,2e,00,30,00,3a,00,39,00,31,00,30,00,30,00,00,00
"DisplayName"="windows_exporter"
"DependOnService"=hex(7):77,00,6d,00,69,00,41,00,70,00,53,00,72,00,76,00,00,00,\
00,00
"ObjectName"="LocalSystem"
"Description"="Exports Prometheus metrics about the system"
"FailureActions"=hex:00,00,00,00,01,00,00,00,01,00,00,00,03,00,00,00,14,00,00,\
00,01,00,00,00,60,ea,00,00,01,00,00,00,60,ea,00,00,01,00,00,00,60,ea,00,00
```

## install_windows_exporter.cmd

```powershell
@ECHO OFF
CLS

SET EXP_VER=0.31.6
SET SSL_VER=4_0_0
SET NET_SHARE=\\server.domain.de\software$\windows_exporter
SET ENV_DIR=C:\prometheus-exporter
SET SSL_DIR=C:\OpenSSL

net stop windows_exporter
IF EXIST "%ENV_DIR%" DEL /F /Q "%ENV_DIR%"
sc delete windows_exporter

:: create windows-exporter environment
IF NOT EXIST "%ENV_DIR%" MKDIR "%ENV_DIR%"
IF NOT EXIST "%ENV_DIR%\textfile_inputs" MKDIR "%ENV_DIR%\textfile_inputs"

:: copy windows-exporter binary ::::::::::::::::::::::::::::::::::::::::::::::::
COPY /Y "%NET_SHARE%\windows_exporter-%EXP_VER%.exe" "%ENV_DIR%\windows_exporter-%EXP_VER%.exe"
COPY /Y "%NET_SHARE%\config.yaml" "%ENV_DIR%

:: install openssl light
START /WAIT "...." "%NET_SHARE%\Win64OpenSSL_Light-%SSL_VER%.exe" /DIR="%SSL_DIR%" /VERYSILENT /NORESTART

:: change hostname and dnsdomain to lowercase for the certificate request
FOR /F "delims=" %%s IN ('powershell -command "$env:COMPUTERNAME.ToLower()"') DO @set COMPUTERNAME=%%s
FOR /F "delims=" %%s IN ('powershell -command "$env:USERDNSDOMAIN.ToLower()"') DO @set USERDNSDOMAIN=%%s

set CERT_FQDN=%COMPUTERNAME%.%USERDNSDOMAIN%

:: create self-sign certificate for the windows-exporter
"%SSL_DIR%\bin\openssl.exe" req -new -newkey rsa -days 365 -nodes -x509 -keyout "%ENV_DIR%\%CERT_FQDN%.key" -out "%ENV_DIR%\%CERT_FQDN%.crt" -subj "/C=DE/ST=Bayern/L=Muenchen/O=HTH Inc./CN=%CERT_FQDN%" -addext "subjectAltName = DNS:%CERT_FQDN%"

echo tls_server_config:> "%ENV_DIR%\webconfig.yaml"
echo   cert_file: %ENV_DIR%\%CERT_FQDN%.crt>> "%ENV_DIR%\webconfig.yaml"
echo   key_file: %ENV_DIR%\%CERT_FQDN%.key>> "%ENV_DIR%\webconfig.yaml"

.. create windows_exporter service
sc create windows_exporter binPath= \"C:\prometheus-exporter\windows_exporter.exe\"
REG IMPORT "%NET_SHARE%\windows_exporter.reg"

:: open prometheus server port 9100
netsh advfirewall firewall delete rule name="prometheus server (inbound tcp 9100)"
netsh advfirewall firewall add rule name= "prometheus server (inbound tcp 9100)" dir=in action=allow protocol=TCP localport=9100

:: start service
net start windows_exporter
```

## Grafana Alloy Agent installieren

### Logging Konzept in einem Ubuntu System

In einem Debian/Ubuntu System gibt es folgendes Logging Konzept:

```bash
# --------------------------------------------------
# journald (journalctl)
# --------------------------------------------------
journald ist der zentrale Logging-Dienst von systemd. Er sammelt Logs von allen Diensten, die über systemd gestartet werden.
Dies umfasst einen Großteil der Systemdienste, was journalctl zu einer sehr wichtigen Quelle für Logs macht.  
# sudo systemctl list-unit-files --state=enabled

# --------------------------------------------------
# rsyslog
# --------------------------------------------------
rsyslog ist ein traditioneller Syslog-Dienst
rsyslog empfängt Logs von verschiedenen Quellen und schreibt diese in Textdateien unter /var/log/

# --------------------------------------------------
# Fazit
# --------------------------------------------------
Standardmäßig leitet Ubuntu viele Logs von journald an rsyslog weiter. Das bedeutet, dass viele Logs sowohl in journald als auch in den traditionellen Logdateien zu finden sind.
/var/log/syslog und /var/log/auth.log sind typische Logdateien, die von rsyslog verwaltet werden, jedoch werden die Daten die diese Dateien beinhalten auch von Journalctl verwaltet.

Weitere wichtige Logdateien auf einen Default Ubuntu System:

- /var/log/syslog: Allgemeine Systemmeldungen. # (Wird nach journald geschrieben)
- /var/log/auth.log: Authentifizierungsversuche # (Wird nach journald geschrieben)
- /var/log/kern.log: Kernel-Meldungen. # (Wird nach journald geschrieben)
- /var/log/dmesg: Kernelringpuffer # (Wird nach journald geschrieben)
- /var/lib/docker/containers: Alle Logs der Docker Container # (Wird nach journald geschrieben)
- /var/log/apt/history.log: APT-Paketverwaltungsaktivitäten.
- /var/log/alternatives.log (Alternativen-System von Debian-basierten Linux-Distributionen)
- /var/log/apport.log (Apport-Fehlerberichterstattungssystems auf Ubuntu-Systemen) 
- /var/log/bootstrap.log (dpkg und Update Informationen)
- /var/log/dpkg.log (Software und Update Installationen)
```

### Grafana Alloy Agent Installation

```bash
cd /tmp
VERSION="$(curl --silent -qI https://github.com/grafana/alloy/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}')"
# ${VERSION} = v1.15.1
# ${VERSION#v} = 1.15.1

wget https://github.com/grafana/alloy/releases/download/${VERSION}/alloy-linux-arm64.zip # ARM64
unzip alloy-linux-arm64.zip
chmod +x alloy-linux-arm64
sudo mv alloy-linux-arm64 /usr/local/bin/alloy

sudo mkdir /etc/alloy
sudo vi /etc/alloy/config.alloy
sudo vi /etc/systemd/system/grafana-alloy-agent.service
```

## config.alloy (Journal Daemon Logs Beispiel)

```bash
logging {
    level  = "debug"
    format = "logfmt"
}

loki.relabel "journalctl" {
    forward_to = []

    rule {
        source_labels = ["__journal__transport"]
        regex         = "kernel"
        action        = "drop"
    }

    rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
    }

    rule {
        source_labels = ["__journal__transport"]
        target_label  = "transport"
    }

    rule {
        source_labels = ["__journal__cmdline"]
        target_label  = "_cmdline"
    }

    rule {
        source_labels = ["__journal_priority"]
        target_label  = "_priority"
    }

    rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "priority"
    }

    rule {
        source_labels = ["__journal_syslog_identifier"]
        target_label  = "syslog_identifier"
    }

    rule {
        source_labels = ["__journal_syslog_message_severity"]
        target_label  = "level"
    }

    rule {
        source_labels = ["__journal_syslog_message_facility"]
        target_label  = "syslog_facility"
    }
}

loki.source.journal "journalctl" {
    max_age       = "12h0m0s"
    path          = "/var/log/journal"
    relabel_rules = loki.relabel.journalctl.rules
    forward_to    = [loki.write.grafana_loki.receiver]
    labels        = {
        job = "journalctl",
    }
}

loki.write "grafana_loki" {
    endpoint {
        url = "https://loki.htdom.lan/loki/api/v1/push"

        tls_config {
            insecure_skip_verify = true
        }
    }

    external_labels = {
        job = "alloy-agent",
        host = "mina.htdom.lan",
    }
}
```

## config.alloy (rsyslog Daemon Logs Beispiel)

```bash
logging {
  level  = "debug"
  format = "logfmt"
}

local.file_match "var_log_logs" {
  path_targets = [{ "__path__" = "/var/log/*.log" }]
  sync_period  = "5s"
}

local.file_match "var_log_apt_history" {
  path_targets = [{ "__path__" = "/var/log/apt/history.log" }]
  sync_period  = "5s"
}

local.file_match "var_log_syslog" {
    path_targets = [{ "__path__" = "/var/log/syslog" }]
    sync_period = "5s"
}

local.file_match "var_log_dmesg" {
    path_targets = [{ "__path__" = "/var/log/dmesg" }]
    sync_period = "5s"
}

loki.source.file "log_scrape" {
  targets = concat(
    local.file_match.var_log_logs.targets,
    local.file_match.var_log_apt_history.targets,
    local.file_match.var_log_syslog.targets,
    local.file_match.var_log_dmesg.targets,
  )
  forward_to = [loki.process.filter_logs.receiver]
  tail_from_end = true
}

loki.process "filter_logs" {
  stage.drop {
    source = ""
    expression = ".*Connection closed by authenticating user root"
    drop_counter_reason = "noisy"
  }
  stage.drop {
    source = ""
    expression = ".*session (opened|closed) for user root.*"
    drop_counter_reason = "sudo_session_activity"
  }
  forward_to = [loki.write.grafana_loki.receiver]
}

loki.write "grafana_loki" {
  endpoint {
    url = "https://loki.htdom.lan/loki/api/v1/push"

    tls_config {
      insecure_skip_verify = true
    }
  }

  external_labels = {
    job = "alloy-agent",
    host = "mina.htdom.lan",
  }
}
```

## Grafana Alloy Systemd Datei

```bash
[Unit]
Description=Grafana Alloy Agent
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/bin/
ExecStart=/usr/local/bin/alloy run --server.http.listen-addr=0.0.0.0:3200 /etc/alloy/config.alloy
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## Loki Metriken abfrage

```bash
## Wichtige Metriken um zu sehen ob Logs übertragen werden.
## Logs werden erst an Loki gesendet, wenn es neue Einträge in den Logs gibt.
## Wenn keine Einträge geschrieben werden, wird auch nichts an Loki übertragen.
##
curl -sk http://mina.htdom.lan:3200/metrics | grep loki

# HELP loki_source_file_file_bytes_total Number of bytes total.
# TYPE loki_source_file_file_bytes_total gauge
loki_source_file_file_bytes_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/alternatives.log"} 153
loki_source_file_file_bytes_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/apport.log"} 0
loki_source_file_file_bytes_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/auth.log"} 78978
...

# HELP loki_source_file_read_bytes_total Number of bytes read.
# TYPE loki_source_file_read_bytes_total gauge
loki_source_file_read_bytes_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/alternatives.log"} 153
loki_source_file_read_bytes_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/apport.log"} 0
loki_source_file_read_bytes_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/auth.log"} 78978
...

# HELP loki_source_file_read_lines_total Number of lines read.
# TYPE loki_source_file_read_lines_total counter
loki_source_file_read_lines_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/apt/history.log"} 6
loki_source_file_read_lines_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/dpkg.log"} 38
loki_source_file_read_lines_total{component_id="loki.source.file.log_scrape",component_path="/",path="/var/log/syslog"} 22
...

# HELP loki_write_sent_bytes_total Number of bytes sent.
# TYPE loki_write_sent_bytes_total counter
loki_write_sent_bytes_total{component_id="loki.write.grafana_loki",component_path="/",host="loki.htdom.lan"} 5275

# HELP loki_write_sent_entries_total Number of log entries sent to the ingester.
# TYPE loki_write_sent_entries_total counter
loki_write_sent_entries_total{component_id="loki.write.grafana_loki",component_path="/",host="loki.htdom.lan"} 71

curl -Gk -s 'https://loki.htdom.lan/loki/api/v1/query_range' --data-urlencode 'query={job="alloy-agent"}' | jq -r '.'
curl -Gk -s 'https://loki.htdom.lan/loki/api/v1/query_range' --data-urlencode 'query={host="mina.htdom.lan"}' | jq -r '.'
```
