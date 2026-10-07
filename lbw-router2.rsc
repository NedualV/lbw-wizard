# =====================================================================
# Router de ABAJO (colas / PPPoE / clientes) - generado por lbw-wizard.sh v3.2
# LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later - https://github.com/NedualV/lbw-wizard
#
# Aplicar EN EL ROUTER DE ABAJO:  /import file-name=lbw-router2.rsc verbose=yes
# Revertir:                       /import file-name=lbw-router2-remove.rsc verbose=yes
#
# Este router NO debe hacer NAT: el unico NAT del camino es el del balanceador.
# Si enmascara, todas las conexiones llegan arriba con una sola IP de origen
# y el reparto por equipo deja de funcionar.
#
# Enlace: este router = 10.255.255.2/30 en ether1, balanceador = 10.255.255.1
# Si el puerto hacia el balanceador NO es ether1, reemplaza "ether1" en todo este archivo.
# =====================================================================
:log warning "LBW: preparando router de abajo (ruteo puro)"

# 1. Apartar cualquier otra salida a Internet (todo se marca PRE-LBW y el
#    desinstalador lo devuelve): rutas por defecto fijas, y DHCP/PPPoE client
#    que instalen su propia ruta por defecto.
:do {
  :foreach r in=[/ip route find where dst-address="0.0.0.0/0" && static && !disabled && !(comment~"^LBW")] do={
    :local c [:tostr [/ip route get $r comment]]
    /ip route set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: apartar rutas por defecto" }
:do {
  :foreach c in=[/ip dhcp-client find] do={
    :local ifn [:tostr [/ip dhcp-client get $c interface]]
    :local adr [:tostr [/ip dhcp-client get $c add-default-route]]
    :local cm [:tostr [/ip dhcp-client get $c comment]]
    :if ($ifn != "ether1" && $adr != "no" && $adr != "false" && !($cm~"LBW")) do={
      /ip dhcp-client set $c add-default-route=no comment=("PRE-LBW-ADR:" . $cm)
      :log warning ("LBW: DHCP client de " . $ifn . " ya no instala ruta por defecto")
    }
  }
} on-error={ :log error "LBW fallo: apartar otros DHCP client" }
:do {
  :foreach c in=[/interface pppoe-client find where add-default-route=yes] do={
    :local cm [:tostr [/interface pppoe-client get $c comment]]
    /interface pppoe-client set $c add-default-route=no comment=("PRE-LBW-ADR:" . $cm)
  }
} on-error={}

# 2. Salida por el balanceador
:do {
  :local done false
  :foreach c in=[/ip dhcp-client find] do={
    :if ([:tostr [/ip dhcp-client get $c interface]] = "ether1") do={
      :local cm [:tostr [/ip dhcp-client get $c comment]]
      :if (!($cm~"^LBW")) do={ :set cm ("LBW:uplink-prev:" . $cm) }
      /ip dhcp-client set $c add-default-route=yes use-peer-dns=yes disabled=no comment=$cm
      :set done true
    }
  }
  :if (!$done) do={ /ip dhcp-client add interface="ether1" add-default-route=yes use-peer-dns=yes disabled=no comment="LBW:uplink" }
} on-error={ :log error "LBW fallo: dhcp-client hacia el balanceador" }
# El balanceador le entrega 10.255.255.2, la ruta por defecto hacia 10.255.255.1 y el DNS.

# 3. Fuera NAT: el balanceador es quien enmascara
:do {
  :foreach r in=[/ip firewall nat find where action=masquerade && !disabled] do={
    :local c [:tostr [/ip firewall nat get $r comment]]
    /ip firewall nat set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: apartar NAT" }

# 4. FastTrack fuera: se salta las colas y el conteo de trafico
:do {
  :foreach r in=[/ip firewall filter find where action=fasttrack-connection && !disabled] do={
    :local c [:tostr [/ip firewall filter get $r comment]]
    /ip firewall filter set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: fasttrack" }

:log warning "LBW: router de abajo listo. Las colas simples siguen funcionando igual."
:put "Listo. Comprueba: /ip dhcp-client print  /ip route print where dst-address=0.0.0.0/0  /queue simple print stats"
