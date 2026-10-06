# LBW - desinstalador del router de ABAJO - lbw-wizard.sh v3.1
# LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later - https://github.com/NedualV/lbw-wizard
# Uso EN EL ROUTER DE ABAJO: /import file-name=lbw-router2-remove.rsc verbose=yes
:log warning "LBW: revirtiendo router de abajo"

# 1. Lo que LBW agrego hacia el balanceador
:do { /ip dhcp-client remove [find where comment="LBW:uplink"] } on-error={}
:do { /ip route remove [find where comment~"^LBW:uplink"] } on-error={}
:do { /ip address remove [find where comment="LBW:uplink"] } on-error={}
:foreach c in=[/ip dhcp-client find where comment~"^LBW:uplink-prev:"] do={
  :local cm [/ip dhcp-client get $c comment]
  /ip dhcp-client set $c comment=[:pick $cm 16 [:len $cm]]
}

# 2. Devolver las otras salidas que se apartaron
:foreach c in=[/ip dhcp-client find where comment~"^PRE-LBW-ADR:"] do={
  :local cm [/ip dhcp-client get $c comment]
  /ip dhcp-client set $c add-default-route=yes comment=[:pick $cm 12 [:len $cm]]
}
:do {
  :foreach c in=[/interface pppoe-client find where comment~"^PRE-LBW-ADR:"] do={
    :local cm [/interface pppoe-client get $c comment]
    /interface pppoe-client set $c add-default-route=yes comment=[:pick $cm 12 [:len $cm]]
  }
} on-error={}
:foreach r in=[/ip route find where comment~"^PRE-LBW:"] do={
  :local c [/ip route get $r comment]
  /ip route set $r disabled=no comment=[:pick $c 8 [:len $c]]
}

# 3. NAT y FastTrack de vuelta
:foreach r in=[/ip firewall nat find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall nat get $r comment]
  /ip firewall nat set $r disabled=no comment=[:pick $c 8 [:len $c]]
}
:foreach r in=[/ip firewall filter find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall filter get $r comment]
  /ip firewall filter set $r disabled=no comment=[:pick $c 8 [:len $c]]
}

:log warning "LBW: router de abajo revertido"
:put "LBW: router de abajo revertido."
