# =====================================================================
# LBW Multi-WAN - generado por lbw-wizard.sh v3.1 el 2026-10-06 21:28
# LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later
# https://github.com/NedualV/lbw-wizard
#
# Aplicar:    /import file-name=lbw-1006-2128.rsc verbose=yes
# Revertir:   /import file-name=lbw-remove.rsc
# Modo: lb | WANs: 2 | reparto: both-addresses
# =====================================================================
:log warning "LBW: aplicando configuracion multi-WAN"

# --- 0. Limpieza de una instalacion LBW previa -----------------------
:do { /system scheduler remove [find where comment~"^LBW"] } on-error={}
:do { /system script remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall mangle remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall nat remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall filter remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall address-list remove [find where comment~"^LBW:(local|fijar)"] } on-error={}
:do { /ip route remove [find where comment~"^LBW"] } on-error={}
:do { /routing rule remove [find where comment~"^LBW"] } on-error={}
:do { /routing table remove [find where comment~"^LBW"] } on-error={}

# --- 1. FastTrack fuera (es incompatible con el marcado) -------------
:do {
  :foreach r in=[/ip firewall filter find where action=fasttrack-connection && !disabled] do={
    :local c [/ip firewall filter get $r comment]
    /ip firewall filter set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: fasttrack" }
# Las rutas por defecto y el NAT viejos se apartan AL FINAL (seccion 10),
# para que el router nunca se quede sin salida si algo falla a mitad.

# --- 2. Interfaces: renombrado con sufijo _ISPx y listas -------------
:if ([:len [/interface list find where name="LBW-WAN"]] = 0) do={ /interface list add name=LBW-WAN comment="LBW" }
:if ([:len [/interface list find where name="LBW-LAN"]] = 0) do={ /interface list add name=LBW-LAN comment="LBW" }
/interface list member remove [find where comment~"^LBW"]

# --- WAN1: Claro (ether1 -> ether1_ISP1)
:do {
  :foreach b in=[/interface bridge port find where interface="ether1"] do={
    :local br [/interface bridge port get $b bridge]
    :do { /ip firewall address-list add list=LBW-restore address=127.0.0.1 comment=("LBW:restore:br=" . $br . ":if=ether1") } on-error={}
    /interface bridge port remove $b
    :log warning ("LBW: ether1 sacado del bridge " . $br . " para usarlo como WAN1")
  }
} on-error={ :log error "LBW fallo: sacar ether1 del bridge" }
:do {
  :if ([:len [/interface find where name="ether1_ISP1"]] = 0) do={
    :if ([:len [/interface find where name="ether1"]] > 0) do={
      /interface set [find where name="ether1"] name="ether1_ISP1" comment="LBW:WAN1:was=ether1"
    }
  } else={ /interface set [find where name="ether1_ISP1"] comment="LBW:WAN1:was=ether1" }
} on-error={ :log error "LBW fallo: renombrar ether1" }
:if ([:len [/interface list find where name="LBW-WAN1"]] = 0) do={ /interface list add name=LBW-WAN1 comment="LBW:WAN1" }
# Si existe la lista WAN de la config de fabrica, metemos ahi tambien esta linea
:if ([:len [/interface list find where name="WAN"]] > 0) do={
  :do { /interface list member add list=WAN interface="ether1_ISP1" comment="LBW:compat:WAN1" } on-error={}
}
:do { /interface list member add list=LBW-WAN1 interface="ether1_ISP1" comment="LBW:WAN1" } on-error={}
:do { /interface list member add list=LBW-WAN interface="ether1_ISP1" comment="LBW:WAN1" } on-error={}
:do {
  /ip dhcp-client add interface="ether1_ISP1" add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:NEW:WAN1" script=":if (\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP1_conn\"]"
} on-error={
  :log warning "LBW: ya habia un DHCP client para WAN1; lo reutilizo"
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get $c interface]
    :if ([:tostr $ifn] = "ether1_ISP1") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN1:adr=yes,dns=yes,ntp=yes" script=":if (\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP1_conn\"]" }
    :if ([:tostr $ifn] = "ether1") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN1:adr=yes,dns=yes,ntp=yes" script=":if (\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP1_conn\"]" }
  }
}

# --- WAN2: Altice (ether2 -> ether2_ISP2)
:do {
  :foreach b in=[/interface bridge port find where interface="ether2"] do={
    :local br [/interface bridge port get $b bridge]
    :do { /ip firewall address-list add list=LBW-restore address=127.0.0.2 comment=("LBW:restore:br=" . $br . ":if=ether2") } on-error={}
    /interface bridge port remove $b
    :log warning ("LBW: ether2 sacado del bridge " . $br . " para usarlo como WAN2")
  }
} on-error={ :log error "LBW fallo: sacar ether2 del bridge" }
:do {
  :if ([:len [/interface find where name="ether2_ISP2"]] = 0) do={
    :if ([:len [/interface find where name="ether2"]] > 0) do={
      /interface set [find where name="ether2"] name="ether2_ISP2" comment="LBW:WAN2:was=ether2"
    }
  } else={ /interface set [find where name="ether2_ISP2"] comment="LBW:WAN2:was=ether2" }
} on-error={ :log error "LBW fallo: renombrar ether2" }
:if ([:len [/interface list find where name="LBW-WAN2"]] = 0) do={ /interface list add name=LBW-WAN2 comment="LBW:WAN2" }
# Si existe la lista WAN de la config de fabrica, metemos ahi tambien esta linea
:if ([:len [/interface list find where name="WAN"]] > 0) do={
  :do { /interface list member add list=WAN interface="ether2_ISP2" comment="LBW:compat:WAN2" } on-error={}
}
:do { /interface list member add list=LBW-WAN2 interface="ether2_ISP2" comment="LBW:WAN2" } on-error={}
:do { /interface list member add list=LBW-WAN interface="ether2_ISP2" comment="LBW:WAN2" } on-error={}
:do {
  /ip dhcp-client add interface="ether2_ISP2" add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:NEW:WAN2" script=":if (\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP2_conn\"]"
} on-error={
  :log warning "LBW: ya habia un DHCP client para WAN2; lo reutilizo"
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get $c interface]
    :if ([:tostr $ifn] = "ether2_ISP2") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN2:adr=yes,dns=yes,ntp=yes" script=":if (\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP2_conn\"]" }
    :if ([:tostr $ifn] = "ether2") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN2:adr=yes,dns=yes,ntp=yes" script=":if (\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP2_conn\"]" }
  }
}

# --- 3. Red local ----------------------------------------------------
:if ([:len [/interface list find where name="LAN"]] > 0) do={ :do { /interface list member add list=LAN interface="ether5" comment="LBW:compat:LAN" } on-error={} }
:do { /interface list member add list=LBW-LAN interface="ether5" comment="LBW:LAN" } on-error={}
:do { /ip firewall address-list add list=LBW-local address=10.0.0.0/8 comment="LBW:local" } on-error={ :log error "LBW fallo: address-list 10.0.0.0/8" }
:do { /ip firewall address-list add list=LBW-local address=172.16.0.0/12 comment="LBW:local" } on-error={ :log error "LBW fallo: address-list 172.16.0.0/12" }
:do { /ip firewall address-list add list=LBW-local address=192.168.0.0/16 comment="LBW:local" } on-error={ :log error "LBW fallo: address-list 192.168.0.0/16" }
# Enlace con el router de abajo: ether5 = 10.255.255.1/30 (abajo: 10.255.255.2)
:if ([:len [/ip address find where interface="ether5"]] = 0) do={
:do {   /ip address add address=10.255.255.1/30 interface="ether5" comment="LBW:link" } on-error={ :log error "LBW fallo: IP del enlace" }
} else={ :log info "LBW: ether5 ya tenia IP, la respeto" }
:if ([:len [/ip dhcp-server find where name="LBW-link"]] = 0) do={
  :do { /ip pool add name=LBW-link ranges=10.255.255.2-10.255.255.2 comment="LBW:link" } on-error={ :log error "LBW fallo: pool del enlace" }
  :do { /ip dhcp-server add name=LBW-link interface="ether5" address-pool=LBW-link lease-time=1h disabled=no comment="LBW:link" } on-error={ :log error "LBW fallo: dhcp del enlace" }
}
# Sin esta red el router de abajo recibe IP pero NO gateway ni DNS
:if ([:len [/ip dhcp-server network find where address="10.255.255.0/30"]] = 0) do={
  :do { /ip dhcp-server network add address=10.255.255.0/30 gateway=10.255.255.1 dns-server=1.1.1.1,8.8.8.8 comment="LBW:link" } on-error={ :log error "LBW fallo: red DHCP del enlace" }
} else={
  :log error "LBW: ya existe una red DHCP 10.255.255.0/30 que no es de LBW; el router de abajo puede quedarse sin gateway. Revisa IP > DHCP Server > Networks"
}
# Subredes de clientes que viven detras del router de abajo
:do { /ip route add dst-address=10.0.0.0/8 gateway=10.255.255.2 comment="LBW:downstream" } on-error={ :log error "LBW fallo: ruta a 10.0.0.0/8" }
:do { /ip route add dst-address=172.16.0.0/12 gateway=10.255.255.2 comment="LBW:downstream" } on-error={ :log error "LBW fallo: ruta a 172.16.0.0/12" }
:do { /ip route add dst-address=192.168.0.0/16 gateway=10.255.255.2 comment="LBW:downstream" } on-error={ :log error "LBW fallo: ruta a 192.168.0.0/16" }
:do { /ip firewall address-list add list=LBW-local address=224.0.0.0/4 comment="LBW:local" } on-error={ :log error "LBW fallo: address-list multicast" }
# Modo balanceador: solo los servidores; allow-remote-requests se deja como estaba
:do { /ip dns set servers=1.1.1.1,8.8.8.8 } on-error={ :log error "LBW fallo: DNS" }

# --- 4. Tablas de ruteo ----------------------------------------------
:do { /routing table add fib name=to_WAN1 comment="LBW:WAN1:table" } on-error={ :log error "LBW fallo: tabla to_WAN1" }
:do { /routing table add fib name=to_WAN2 comment="LBW:WAN2:table" } on-error={ :log error "LBW fallo: tabla to_WAN2" }

# --- 5. Rutas: probes por interfaz y rutas recursivas ----------------
:do { /ip route add dst-address=9.9.9.9/32 gateway=ether1_ISP1 scope=10 target-scope=10 comment="LBW:WAN1:PROBE" disabled=yes } on-error={ :log error "LBW fallo: probe1 WAN1" }
:do { /ip route add dst-address=208.67.222.222/32 gateway=ether1_ISP1 scope=10 target-scope=10 comment="LBW:WAN1:PROBE" disabled=yes } on-error={ :log error "LBW fallo: probe2 WAN1" }
:do { /ip route add dst-address=149.112.112.112/32 gateway=ether2_ISP2 scope=10 target-scope=10 comment="LBW:WAN2:PROBE" disabled=yes } on-error={ :log error "LBW fallo: probe1 WAN2" }
:do { /ip route add dst-address=208.67.220.220/32 gateway=ether2_ISP2 scope=10 target-scope=10 comment="LBW:WAN2:PROBE" disabled=yes } on-error={ :log error "LBW fallo: probe2 WAN2" }

# Tabla main (trafico del propio router)
:do { /ip route add dst-address=0.0.0.0/0 gateway=9.9.9.9 check-gateway=ping distance=1 scope=10 target-scope=11 comment="LBW:WAN1:MAIN" } on-error={ :log error "LBW fallo: default main WAN1" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.222.222 check-gateway=ping distance=2 scope=10 target-scope=11 comment="LBW:WAN1:MAIN" } on-error={ :log error "LBW fallo: default main WAN1 b" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=149.112.112.112 check-gateway=ping distance=11 scope=10 target-scope=11 comment="LBW:WAN2:MAIN" } on-error={ :log error "LBW fallo: default main WAN2" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.220.220 check-gateway=ping distance=12 scope=10 target-scope=11 comment="LBW:WAN2:MAIN" } on-error={ :log error "LBW fallo: default main WAN2 b" }

# Tabla to_WAN1: primero Claro, luego las demas por orden
:do { /ip route add dst-address=0.0.0.0/0 gateway=9.9.9.9 check-gateway=ping distance=1 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN1" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.222.222 check-gateway=ping distance=2 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN1 b" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=149.112.112.112 check-gateway=ping distance=11 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:BK2" } on-error={ :log error "LBW fallo: respaldo 2 de WAN1" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.220.220 check-gateway=ping distance=12 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:BK2" } on-error={ :log error "LBW fallo: respaldo 2 de WAN1 b" }

# Tabla to_WAN2: primero Altice, luego las demas por orden
:do { /ip route add dst-address=0.0.0.0/0 gateway=149.112.112.112 check-gateway=ping distance=1 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN2" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.220.220 check-gateway=ping distance=2 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN2 b" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=9.9.9.9 check-gateway=ping distance=11 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:BK1" } on-error={ :log error "LBW fallo: respaldo 1 de WAN2" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.222.222 check-gateway=ping distance=12 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:BK1" } on-error={ :log error "LBW fallo: respaldo 1 de WAN2 b" }

# --- 6. Marcado de trafico -------------------------------------------
:do { /ip firewall mangle add chain=prerouting action=accept in-interface-list=LBW-LAN dst-address-list=LBW-local comment="LBW:local:skip" } on-error={ :log error "LBW fallo: skip local" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-WAN1 connection-mark=no-mark new-connection-mark=ISP1_conn passthrough=yes comment="LBW:WAN1:FWD" } on-error={ :log error "LBW fallo: mangle fwd WAN1" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-WAN2 connection-mark=no-mark new-connection-mark=ISP2_conn passthrough=yes comment="LBW:WAN2:FWD" } on-error={ :log error "LBW fallo: mangle fwd WAN2" }
# Fijados: equipos (origen) o sitios (destino) que siempre van por una linea.
# Las listas pueden estar vacias; agrega con /ip firewall address-list add list=LBW-fijar-WANx address=...
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN connection-mark=no-mark src-address-list=LBW-fijar-WAN1 dst-address-list=!LBW-local dst-address-type=!local new-connection-mark=ISP1_conn passthrough=yes comment="LBW:FIJAR:WAN1:equipo" } on-error={ :log error "LBW fallo: fijar equipos WAN1" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN connection-mark=no-mark dst-address-list=LBW-fijar-WAN1 dst-address-type=!local new-connection-mark=ISP1_conn passthrough=yes comment="LBW:FIJAR:WAN1:sitio" } on-error={ :log error "LBW fallo: fijar sitios WAN1" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN connection-mark=no-mark src-address-list=LBW-fijar-WAN2 dst-address-list=!LBW-local dst-address-type=!local new-connection-mark=ISP2_conn passthrough=yes comment="LBW:FIJAR:WAN2:equipo" } on-error={ :log error "LBW fallo: fijar equipos WAN2" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN connection-mark=no-mark dst-address-list=LBW-fijar-WAN2 dst-address-type=!local new-connection-mark=ISP2_conn passthrough=yes comment="LBW:FIJAR:WAN2:sitio" } on-error={ :log error "LBW fallo: fijar sitios WAN2" }
# PCC: 2 partes repartidas segun la velocidad de cada linea
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN dst-address-list=!LBW-local dst-address-type=!local connection-mark=no-mark new-connection-mark=ISP1_conn passthrough=yes per-connection-classifier=both-addresses:2/0 comment="LBW:PCC:WAN1:0" } on-error={ :log error "LBW fallo: PCC 0" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN dst-address-list=!LBW-local dst-address-type=!local connection-mark=no-mark new-connection-mark=ISP2_conn passthrough=yes per-connection-classifier=both-addresses:2/1 comment="LBW:PCC:WAN2:1" } on-error={ :log error "LBW fallo: PCC 1" }
:do { /ip firewall mangle add chain=prerouting action=mark-routing in-interface-list=LBW-LAN connection-mark=ISP1_conn new-routing-mark=to_WAN1 passthrough=no comment="LBW:WAN1:RT" } on-error={ :log error "LBW fallo: mark-routing WAN1" }
:do { /ip firewall mangle add chain=prerouting action=mark-routing in-interface-list=LBW-LAN connection-mark=ISP2_conn new-routing-mark=to_WAN2 passthrough=no comment="LBW:WAN2:RT" } on-error={ :log error "LBW fallo: mark-routing WAN2" }
:do { /ip firewall mangle add chain=output action=mark-routing connection-mark=ISP1_conn dst-address-list=!LBW-local new-routing-mark=to_WAN1 passthrough=no comment="LBW:WAN1:OUT" } on-error={ :log error "LBW fallo: mangle output WAN1" }
:do { /ip firewall mangle add chain=output action=mark-routing connection-mark=ISP2_conn dst-address-list=!LBW-local new-routing-mark=to_WAN2 passthrough=no comment="LBW:WAN2:OUT" } on-error={ :log error "LBW fallo: mangle output WAN2" }
:do { /ip firewall mangle add chain=forward action=change-mss new-mss=clamp-to-pmtu tcp-flags=syn protocol=tcp out-interface-list=LBW-WAN comment="LBW:MSS" } on-error={ :log error "LBW fallo: MSS clamp" }

# --- 7. NAT (se agrega ANTES de apartar el viejo) --------------------
:do { /ip firewall nat add chain=srcnat action=masquerade out-interface-list=LBW-WAN ipsec-policy=out,none comment="LBW:NAT" } on-error={ :log error "LBW fallo: NAT" }

# --- 8. Firewall basico (equivalente al defconf de MikroTik) ---------
:do {
  :local hasA false
  :local anchor
  :local cand [/ip firewall filter find where !dynamic && !(comment~"^LBW")]
  :if ([:len $cand] > 0) do={ :set anchor [:pick $cand 0]; :set hasA true }
  :if ($hasA) do={ /ip firewall filter add chain=input action=accept connection-state=established,related,untracked comment="LBW:FW:in-est" place-before=$anchor } else={ /ip firewall filter add chain=input action=accept connection-state=established,related,untracked comment="LBW:FW:in-est" }
  :if ($hasA) do={ /ip firewall filter add chain=input action=drop connection-state=invalid comment="LBW:FW:in-invalid" place-before=$anchor } else={ /ip firewall filter add chain=input action=drop connection-state=invalid comment="LBW:FW:in-invalid" }
  :if ($hasA) do={ /ip firewall filter add chain=input action=accept protocol=icmp limit=10,20:packet comment="LBW:FW:icmp" place-before=$anchor } else={ /ip firewall filter add chain=input action=accept protocol=icmp limit=10,20:packet comment="LBW:FW:icmp" }
  :if ($hasA) do={ /ip firewall filter add chain=input action=accept in-interface-list=LBW-LAN comment="LBW:FW:lan" place-before=$anchor } else={ /ip firewall filter add chain=input action=accept in-interface-list=LBW-LAN comment="LBW:FW:lan" }
  :if ($hasA) do={ /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked comment="LBW:FW:fwd-est" place-before=$anchor } else={ /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked comment="LBW:FW:fwd-est" }
  :if ($hasA) do={ /ip firewall filter add chain=forward action=drop connection-state=invalid comment="LBW:FW:fwd-invalid" place-before=$anchor } else={ /ip firewall filter add chain=forward action=drop connection-state=invalid comment="LBW:FW:fwd-invalid" }
} on-error={ :log error "LBW fallo: firewall (reglas de arriba)" }
:do { /ip firewall filter add chain=input action=drop in-interface-list=LBW-WAN comment="LBW:FW:drop-wan" } on-error={ :log error "LBW fallo: fw drop wan" }
:do { /ip firewall filter add chain=forward action=drop connection-state=new connection-nat-state=!dstnat in-interface-list=LBW-WAN comment="LBW:FW:fwd-wan" } on-error={ :log error "LBW fallo: fw forward wan" }

# --- 8c. Servicios del router (solo SSH y Winbox, desde 10.255.255.0/30) -------
# Solo entradas estaticas: desde RouterOS 7.19 /ip service lista tambien las
# conexiones abiertas como entradas dinamicas (incluida esta sesion SSH), y esas
# no se pueden editar. En 7.24 "address" paso a llamarse "available-from";
# "address" queda de respaldo para v7 anteriores, dentro de :parse para que
# 7.24+ no avise de sintaxis vieja. Cada servicio va protegido por separado.
:do {
  :local n 0
  :foreach s in=[/ip service find] do={
    :local dyn ""
    :do { :set dyn [:tostr [/ip service get $s dynamic]] } on-error={}
    :local nm [/ip service get $s name]
    :if ($dyn != "true") do={
      :if ($nm = "telnet" || $nm = "ftp" || $nm = "www" || $nm = "api" || $nm = "api-ssl" || $nm = "reverse-proxy") do={
        :do {
          :if (![/ip service get $s disabled]) do={
            :set n ($n + 1)
            :do { /ip firewall address-list add list=LBW-restore address=("127.0.2." . $n) comment=("LBW:svc:" . $nm . ":off") } on-error={}
            /ip service set $s disabled=yes
          }
        } on-error={ :log error ("LBW fallo: apagar servicio " . $nm) }
      }
      :if ($nm = "ssh" || $nm = "winbox") do={
        :do {
          :local cur ""
          :do { :set cur [/ip service get $s available-from] } on-error={
            :do { :local g [:parse ":return [/ip service get \$sid address]"]; :set cur [$g sid=$s] } on-error={}
          }
          :local af ""
          :foreach x in=$cur do={ :if ([:len $af] > 0) do={ :set af ($af . ",") }; :set af ($af . $x) }
          :set n ($n + 1)
          :do { /ip firewall address-list add list=LBW-restore address=("127.0.2." . $n) comment=("LBW:svc:" . $nm . ":af=" . $af) } on-error={}
          :do { /ip service set $s available-from=10.255.255.0/30 } on-error={
            :local f [:parse "/ip service set \$sid address=10.255.255.0/30"]
            $f sid=$s
          }
        } on-error={ :log error ("LBW fallo: limitar servicio " . $nm) }
      }
    }
  }
  :do {
    :if ([/tool bandwidth-server get enabled]) do={
      :do { /ip firewall address-list add list=LBW-restore address=127.0.2.200 comment="LBW:svc:btest:on" } on-error={}
      /tool bandwidth-server set enabled=no
    }
  } on-error={ :log error "LBW fallo: apagar bandwidth-server" }
  :do {
    :local sm [:tostr [/ip smb get enabled]]
    :if ($sm != "no" && $sm != "false") do={
      :do { /ip firewall address-list add list=LBW-restore address=127.0.2.201 comment=("LBW:svc:smb:" . $sm) } on-error={}
      /ip smb set enabled=no
    }
  } on-error={ :log error "LBW fallo: apagar SMB" }
  :log warning "LBW: servicios del router endurecidos (solo SSH y Winbox desde 10.255.255.0/30)"
} on-error={ :log error "LBW fallo: endurecer servicios" }

# --- 8d. Log de LBW en disco (sobrevive a los reinicios) -------------
:do {
  :if ([:len [/system logging action find where name="lbwdisk"]] = 0) do={
    :local f "lbw-log"
    :do { :local d [/system logging action get [find where name="disk"] disk-file-name]; :if ([:pick $d 0 6] = "flash/") do={ :set f "flash/lbw-log" } } on-error={}
    /system logging action add name=lbwdisk target=disk disk-file-name=$f disk-lines-per-file=2000 disk-file-count=2
  }
  :if ([:len [/system logging find where action="lbwdisk"]] = 0) do={
    :do { /system logging add topics=script action=lbwdisk regex="LBW" } on-error={ /system logging add topics=script action=lbwdisk }
  }
} on-error={ :log error "LBW fallo: log en disco" }

# --- 8e. Hora por NTP y zona horaria (America/Santo_Domingo) -----------------------
:do { /system ntp client set enabled=yes servers=time.cloudflare.com,pool.ntp.org } on-error={ :log error "LBW fallo: NTP" }
:do { /system clock set time-zone-autodetect=no time-zone-name=America/Santo_Domingo } on-error={ :log error "LBW fallo: zona horaria America/Santo_Domingo" }

# --- 8b. Arranque: usar el gateway del lease que ya esta activo
:delay 8s
:do {
  :local gw ""
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get $c interface]
    :if ([:tostr $ifn] = "ether1_ISP1") do={ :set gw [/ip dhcp-client get $c gateway] }
  }
  :if ([:len $gw] > 0) do={
    /ip route set [/ip route find where comment="LBW:WAN1:PROBE"] gateway=$gw disabled=no
    :log warning ("LBW: WAN1 gateway " . $gw)
  } else={ :log warning "LBW: WAN1 aun sin lease DHCP; las rutas se activan cuando llegue" }
} on-error={ :log error "LBW fallo: arranque WAN1" }
:do {
  :local gw ""
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get $c interface]
    :if ([:tostr $ifn] = "ether2_ISP2") do={ :set gw [/ip dhcp-client get $c gateway] }
  }
  :if ([:len $gw] > 0) do={
    /ip route set [/ip route find where comment="LBW:WAN2:PROBE"] gateway=$gw disabled=no
    :log warning ("LBW: WAN2 gateway " . $gw)
  } else={ :log warning "LBW: WAN2 aun sin lease DHCP; las rutas se activan cuando llegue" }
} on-error={ :log error "LBW fallo: arranque WAN2" }

# --- 9. Monitor de lineas --------------------------------------------

:do {
  /system script add name=lbw-monitor comment="LBW: monitor de WANs - LBW Wizard por Nedual Vargas (@NEDUALV)" source={
:if ([/system resource get uptime] >= 60s) do={
  :foreach a in=[/ip address find where interface="ether1_ISP1" && !disabled] do={
    :local ad [/ip address get $a address]
    :local pf [:tostr [:pick $ad ([:find $ad "/"] + 1) [:len $ad]]]
    :local nw [:tostr [/ip address get $a network]]
    :if ($pf != "32") do={ :set nw ($nw . "/" . $pf) }
    :if ([:len [/ip firewall address-list find where list="LBW-local" && address=$nw]] = 0) do={
      :do { /ip firewall address-list add list=LBW-local address=$nw comment="LBW:local:wan1" } on-error={}
    }
  }
  :foreach a in=[/ip address find where interface="ether2_ISP2" && !disabled] do={
    :local ad [/ip address get $a address]
    :local pf [:tostr [:pick $ad ([:find $ad "/"] + 1) [:len $ad]]]
    :local nw [:tostr [/ip address get $a network]]
    :if ($pf != "32") do={ :set nw ($nw . "/" . $pf) }
    :if ([:len [/ip firewall address-list find where list="LBW-local" && address=$nw]] = 0) do={
      :do { /ip firewall address-list add list=LBW-local address=$nw comment="LBW:local:wan2" } on-error={}
    }
  }
  :global LBWs1
  :local u1 ([:len [/ip route find where comment="LBW:WAN1:OWN" && active]] > 0)
  :if ([:typeof $LBWs1] = "nothing") do={
    :set LBWs1 $u1
    :if ($u1) do={ :log info "LBW: Claro (WAN1) en linea al iniciar el monitor" } else={ :log warning "LBW: Claro (WAN1) sin salida al iniciar el monitor" }
  } else={
    :if ($u1 != $LBWs1) do={
      :set LBWs1 $u1
      :if ($u1) do={
        :log warning "LBW: Claro (WAN1) EN LINEA"
        
      } else={
        :log error "LBW: Claro (WAN1) CAIDA"
        /ip firewall connection remove [find where connection-mark="ISP1_conn"]
        
      }
    }
  }
  :global LBWs2
  :local u2 ([:len [/ip route find where comment="LBW:WAN2:OWN" && active]] > 0)
  :if ([:typeof $LBWs2] = "nothing") do={
    :set LBWs2 $u2
    :if ($u2) do={ :log info "LBW: Altice (WAN2) en linea al iniciar el monitor" } else={ :log warning "LBW: Altice (WAN2) sin salida al iniciar el monitor" }
  } else={
    :if ($u2 != $LBWs2) do={
      :set LBWs2 $u2
      :if ($u2) do={
        :log warning "LBW: Altice (WAN2) EN LINEA"
        
      } else={
        :log error "LBW: Altice (WAN2) CAIDA"
        /ip firewall connection remove [find where connection-mark="ISP2_conn"]
        
      }
    }
  }
}
  }
} on-error={ :log error "LBW fallo: script monitor" }
:do {
  /system script add name=lbw-status comment="LBW: estado - /system script run lbw-status" source={
:put "LBW - estado de las lineas"
:put "--------------------------------------------------------------"
:local st1 "CAIDA   "
:if ([:len [/ip route find where comment="LBW:WAN1:OWN" && active]] > 0) do={ :set st1 "EN LINEA" }
:local gw1 "-"
:do { :set gw1 [:tostr [/ip route get [:pick [/ip route find where comment="LBW:WAN1:PROBE"] 0] gateway]] } on-error={}
:local nc1 [:len [/ip firewall connection find where connection-mark="ISP1_conn"]]
:local fj1 [:len [/ip firewall address-list find where list="LBW-fijar-WAN1"]]
:put ("WAN1  Claro  ether1_ISP1  " . $st1 . "  gw " . $gw1 . "  conexiones " . $nc1 . "  fijados " . $fj1)
:local st2 "CAIDA   "
:if ([:len [/ip route find where comment="LBW:WAN2:OWN" && active]] > 0) do={ :set st2 "EN LINEA" }
:local gw2 "-"
:do { :set gw2 [:tostr [/ip route get [:pick [/ip route find where comment="LBW:WAN2:PROBE"] 0] gateway]] } on-error={}
:local nc2 [:len [/ip firewall connection find where connection-mark="ISP2_conn"]]
:local fj2 [:len [/ip firewall address-list find where list="LBW-fijar-WAN2"]]
:put ("WAN2  Altice  ether2_ISP2  " . $st2 . "  gw " . $gw2 . "  conexiones " . $nc2 . "  fijados " . $fj2)
:put "--------------------------------------------------------------"
:put ("Ruta por defecto del router: " . [:len [/ip route find where dst-address="0.0.0.0/0" && active && routing-table="main"]] . " activa(s)")
  }
} on-error={ :log error "LBW fallo: script de estado" }
:do { /system scheduler add name=lbw-monitor interval=10s comment="LBW: monitor" on-event="/system script run lbw-monitor" } on-error={ :log error "LBW fallo: scheduler monitor" }

# --- 10. Ahora si: apartar lo viejo que estorba ----------------------
:do {
  :foreach r in=[/ip route find where dst-address="0.0.0.0/0" && static && !disabled && !(comment~"^LBW")] do={
    :local c [/ip route get $r comment]
    /ip route set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: apartar rutas viejas" }
:do {
  :foreach r in=[/ip firewall nat find where action=masquerade && !disabled && !(comment~"^LBW")] do={
    :local c [/ip firewall nat get $r comment]
    /ip firewall nat set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: apartar NAT viejo" }
# DHCP clients que NO son WAN de LBW (p. ej. la gestion de un CHR) pero
# instalan ruta por defecto: quedan de ultimo recurso con distancia 200.
:do {
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [:tostr [/ip dhcp-client get $c interface]]
    :local adr [:tostr [/ip dhcp-client get $c add-default-route]]
    :local cm [:tostr [/ip dhcp-client get $c comment]]
    :if ($adr != "no" && $adr != "false" && !($cm~"^LBW") && !($cm~"^PRE-LBW-DIST:")) do={
      :if ([:len [/interface list member find where list="LBW-WAN" && interface=$ifn]] = 0) do={
        :local d [:tostr [/ip dhcp-client get $c default-route-distance]]
        :if ([:len $d] = 0) do={ :set d "1" }
        /ip dhcp-client set $c default-route-distance=200 comment=("PRE-LBW-DIST:" . $d . ":" . $cm)
        :log warning ("LBW: ruta por defecto del DHCP de " . $ifn . " pasa a distancia 200 (era " . $d . ")")
      }
    }
  }
} on-error={ :log error "LBW fallo: distancia de otros DHCP client" }

# --- 11. Resumen de lo que quedo instalado ---------------------------
:do {
  :local nrt [:len [/ip route find where comment~"^LBW"]]
  :local nmg [:len [/ip firewall mangle find where comment~"^LBW"]]
  :local nnt [:len [/ip firewall nat find where comment~"^LBW"]]
  :local ntb [:len [/routing table find where comment~"^LBW"]]
  :log warning ("LBW: instalado -> rutas=" . $nrt . " mangle=" . $nmg . " nat=" . $nnt . " tablas=" . $ntb)
  :put ("LBW-SUMMARY|" . $nrt . "|" . $nmg . "|" . $nnt . "|" . $ntb)
  :if ($nnt = 0) do={
    :log error "LBW: no se creo el NAT. Reactivando el NAT anterior para no dejar la red sin salida."
    :foreach r in=[/ip firewall nat find where comment~"^PRE-LBW:"] do={
      :local c [/ip firewall nat get $r comment]
      :do { /ip firewall nat set $r disabled=no comment=[:tostr [:pick $c 8 [:len $c]]] } on-error={ :log error "LBW: no pude restaurar una entrada PRE-LBW" }
    }
  }
} on-error={ :log error "LBW fallo: resumen" }
:put "LBW: listo. Si usaste la red de seguridad, confirma en el asistente o ejecuta:"
:put "  /system scheduler remove [find where comment=\"ROLLBACK-LBW\"]"
