# =====================================================================
# LBW Multi-WAN - generado por lbw-wizard.sh v3.0 el 2026-10-06 08:50
# LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later
# https://github.com/NedualV/lbw-wizard
#
# Aplicar:    /import file-name=lbw-1006-0850.rsc verbose=yes
# Revertir:   /import file-name=lbw-remove.rsc
# Modo: lb | WANs: 2 | reparto: both-addresses
# =====================================================================
:log warning "LBW: aplicando configuracion multi-WAN"

# --- 0. Limpieza de una instalacion LBW previa -----------------------
:do { /system scheduler remove [find where comment~"LBW"] } on-error={}
:do { /system script remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall mangle remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall nat remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall filter remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall address-list remove [find where comment~"^LBW:local"] } on-error={}
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

# --- WAN1: ISP1 (ether1 -> ether1_ISP1)
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
  /ip dhcp-client add interface="ether1_ISP1" add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:NEW:WAN1" script=":if ([:tobool \$bound]) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP1_conn\"]"
} on-error={
  :log warning "LBW: ya habia un DHCP client para WAN1; lo reutilizo"
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get $c interface]
    :if ([:tostr $ifn] = "ether1_ISP1") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN1:adr=yes,dns=yes,ntp=yes" script=":if ([:tobool \$bound]) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP1_conn\"]" }
    :if ([:tostr $ifn] = "ether1") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN1:adr=yes,dns=yes,ntp=yes" script=":if ([:tobool \$bound]) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN1:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP1_conn\"]" }
  }
}

# --- WAN2: ISP2 (ether2 -> ether2_ISP2)
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
  /ip dhcp-client add interface="ether2_ISP2" add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:NEW:WAN2" script=":if ([:tobool \$bound]) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP2_conn\"]"
} on-error={
  :log warning "LBW: ya habia un DHCP client para WAN2; lo reutilizo"
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get $c interface]
    :if ([:tostr $ifn] = "ether2_ISP2") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN2:adr=yes,dns=yes,ntp=yes" script=":if ([:tobool \$bound]) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP2_conn\"]" }
    :if ([:tostr $ifn] = "ether2") do={ /ip dhcp-client set $c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN2:adr=yes,dns=yes,ntp=yes" script=":if ([:tobool \$bound]) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] gateway=\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN2:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP2_conn\"]" }
  }
}

# --- 3. Red local ----------------------------------------------------
:do { /interface list member add list=LBW-LAN interface="bridge" comment="LBW:LAN" } on-error={}
:do { /ip firewall address-list add list=LBW-local address=192.168.88.0/24 comment="LBW:local" } on-error={ :log error "LBW fallo: address-list 192.168.88.0/24" }
:do { /ip firewall address-list add list=LBW-local address=224.0.0.0/4 comment="LBW:local" } on-error={ :log error "LBW fallo: address-list multicast" }
:do { /ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes } on-error={ :log error "LBW fallo: DNS" }

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

# Tabla to_WAN1: primero ISP1, luego las demas por orden
:do { /ip route add dst-address=0.0.0.0/0 gateway=9.9.9.9 check-gateway=ping distance=1 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN1" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.222.222 check-gateway=ping distance=2 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN1 b" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=149.112.112.112 check-gateway=ping distance=11 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:BK2" } on-error={ :log error "LBW fallo: respaldo 2 de WAN1" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.220.220 check-gateway=ping distance=12 scope=10 target-scope=11 routing-table=to_WAN1 comment="LBW:WAN1:BK2" } on-error={ :log error "LBW fallo: respaldo 2 de WAN1 b" }

# Tabla to_WAN2: primero ISP2, luego las demas por orden
:do { /ip route add dst-address=0.0.0.0/0 gateway=149.112.112.112 check-gateway=ping distance=1 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN2" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.220.220 check-gateway=ping distance=2 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:OWN" } on-error={ :log error "LBW fallo: ruta propia WAN2 b" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=9.9.9.9 check-gateway=ping distance=11 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:BK1" } on-error={ :log error "LBW fallo: respaldo 1 de WAN2" }
:do { /ip route add dst-address=0.0.0.0/0 gateway=208.67.222.222 check-gateway=ping distance=12 scope=10 target-scope=11 routing-table=to_WAN2 comment="LBW:WAN2:BK1" } on-error={ :log error "LBW fallo: respaldo 1 de WAN2 b" }

# --- 6. Marcado de trafico -------------------------------------------
:do { /ip firewall mangle add chain=prerouting action=accept in-interface-list=LBW-LAN dst-address-list=LBW-local comment="LBW:local:skip" } on-error={ :log error "LBW fallo: skip local" }
:do { /ip firewall mangle add chain=input action=mark-connection in-interface-list=LBW-WAN1 connection-mark=no-mark new-connection-mark=ISP1_conn passthrough=yes comment="LBW:WAN1:IN" } on-error={ :log error "LBW fallo: mangle input WAN1" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-WAN1 connection-mark=no-mark new-connection-mark=ISP1_conn passthrough=yes comment="LBW:WAN1:FWD" } on-error={ :log error "LBW fallo: mangle fwd WAN1" }
:do { /ip firewall mangle add chain=input action=mark-connection in-interface-list=LBW-WAN2 connection-mark=no-mark new-connection-mark=ISP2_conn passthrough=yes comment="LBW:WAN2:IN" } on-error={ :log error "LBW fallo: mangle input WAN2" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-WAN2 connection-mark=no-mark new-connection-mark=ISP2_conn passthrough=yes comment="LBW:WAN2:FWD" } on-error={ :log error "LBW fallo: mangle fwd WAN2" }
# PCC: 2 partes repartidas segun la velocidad de cada linea
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN dst-address-list=!LBW-local connection-mark=no-mark new-connection-mark=ISP1_conn passthrough=yes per-connection-classifier=both-addresses:2/0 comment="LBW:PCC:WAN1:0" } on-error={ :log error "LBW fallo: PCC 0" }
:do { /ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN dst-address-list=!LBW-local connection-mark=no-mark new-connection-mark=ISP2_conn passthrough=yes per-connection-classifier=both-addresses:2/1 comment="LBW:PCC:WAN2:1" } on-error={ :log error "LBW fallo: PCC 1" }
:do { /ip firewall mangle add chain=prerouting action=mark-routing in-interface-list=LBW-LAN connection-mark=ISP1_conn new-routing-mark=to_WAN1 passthrough=no comment="LBW:WAN1:RT" } on-error={ :log error "LBW fallo: mark-routing WAN1" }
:do { /ip firewall mangle add chain=prerouting action=mark-routing in-interface-list=LBW-LAN connection-mark=ISP2_conn new-routing-mark=to_WAN2 passthrough=no comment="LBW:WAN2:RT" } on-error={ :log error "LBW fallo: mark-routing WAN2" }
:do { /ip firewall mangle add chain=output action=mark-routing connection-mark=ISP1_conn dst-address-list=!LBW-local new-routing-mark=to_WAN1 passthrough=no comment="LBW:WAN1:OUT" } on-error={ :log error "LBW fallo: mangle output WAN1" }
:do { /ip firewall mangle add chain=output action=mark-routing connection-mark=ISP2_conn dst-address-list=!LBW-local new-routing-mark=to_WAN2 passthrough=no comment="LBW:WAN2:OUT" } on-error={ :log error "LBW fallo: mangle output WAN2" }
:do { /ip firewall mangle add chain=forward action=change-mss new-mss=clamp-to-pmtu tcp-flags=syn protocol=tcp out-interface-list=LBW-WAN comment="LBW:MSS" } on-error={ :log error "LBW fallo: MSS clamp" }

# --- 7. NAT (se agrega ANTES de apartar el viejo) --------------------
:do { /ip firewall nat add chain=srcnat action=masquerade out-interface-list=LBW-WAN ipsec-policy=out,none comment="LBW:NAT" } on-error={ :log error "LBW fallo: NAT" }

# --- 8. Proteccion basica del router ---------------------------------

:do { /ip firewall filter add chain=input action=accept connection-state=established,related comment="LBW:FW:established" } on-error={ :log error "LBW fallo: fw established" }
:do { /ip firewall filter add chain=input action=accept protocol=icmp limit=10,20:packet comment="LBW:FW:icmp" } on-error={ :log error "LBW fallo: fw icmp" }
:do { /ip firewall filter add chain=input action=drop connection-state=invalid comment="LBW:FW:invalid" } on-error={ :log error "LBW fallo: fw invalid" }
:do { /ip firewall filter add chain=input action=accept in-interface-list=LBW-LAN comment="LBW:FW:lan" } on-error={ :log error "LBW fallo: fw lan" }
:do { /ip firewall filter add chain=input action=drop in-interface-list=LBW-WAN comment="LBW:FW:drop-wan" } on-error={ :log error "LBW fallo: fw drop wan" }

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

:do { /system script add name=lbw-monitor comment="LBW: monitor de WANs - LBW Wizard por Nedual Vargas (@NEDUALV)" source=":global LBWs1;:local u1 ([:len [/ip route find where comment=\"LBW:WAN1:OWN\" && active]] > 0);:if (\$u1 != \$LBWs1) do={:set LBWs1 \$u1;:if (\$u1) do={:log warning \"LBW: ISP1 (WAN1) EN LINEA\";} else={:log error \"LBW: ISP1 (WAN1) CAIDA\";/ip firewall connection remove [find where connection-mark=\"ISP1_conn\"];};};:global LBWs2;:local u2 ([:len [/ip route find where comment=\"LBW:WAN2:OWN\" && active]] > 0);:if (\$u2 != \$LBWs2) do={:set LBWs2 \$u2;:if (\$u2) do={:log warning \"LBW: ISP2 (WAN2) EN LINEA\";} else={:log error \"LBW: ISP2 (WAN2) CAIDA\";/ip firewall connection remove [find where connection-mark=\"ISP2_conn\"];};};" } on-error={ :log error "LBW fallo: script monitor" }
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
      /ip firewall nat set $r disabled=no comment=[:pick $c 8 [:len $c]]
    }
  }
} on-error={ :log error "LBW fallo: resumen" }
:put "LBW: listo. Si usaste la red de seguridad, confirma en el asistente o ejecuta:"
:put "  /system scheduler remove [find where comment=\"ROLLBACK-LBW\"]"
