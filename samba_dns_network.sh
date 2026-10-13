#!/usr/bin/env bash
set -euo pipefail

# Interface erstelle
sudo ip link add macvlan0 link eth0 type macvlan mode bridge

## IP vergeben (freie IP im gleichen Netzwerk)
sudo ip addr add 192.168.178.200/24 dev macvlan0

## Interface aktivieren
sudo ip link set macvlan0 up

## Route setzen
sudo ip route add 192.168.178.50 dev macvlan0

nslookup dc.htdom.lan 192.168.178.50
nslookup -type=SRV _ldap._tcp.htdom.lan 192.168.178.50
nslookup -type=SRV _kerberos._udp.htdom.lan 192.168.178.50

