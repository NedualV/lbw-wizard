# =====================================================================
# Router de ABAJO (colas / PPPoE / clientes) - generado por lbw-wizard.sh v3.0
# LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later - https://github.com/NedualV/lbw-wizard
#
# Aplicar EN EL ROUTER DE ABAJO:  /import file-name=lbw-router2.rsc verbose=yes
#
# Este router NO debe hacer NAT: el unico NAT del camino es el del balanceador.
# Si enmascara, todas las conexiones llegan arriba con una sola IP de origen
# y el reparto por equipo deja de funcionar.
# =====================================================================
:log warning "LBW: preparando router de abajo (ruteo puro)"

# 1. Salida por el balanceador
#    El puerto de ESTE router hacia el balanceador es: ether1
#    Si no es ese, cambialo en las dos lineas de abajo antes de importar.
:do { /ip route remove [find where dst-address="0.0.0.0/0" && static] } on-error={}
:do { /ip dhcp-client add interface="ether1" add-default-route=yes use-peer-dns=yes comment="LBW:uplink" } on-error={
  :do { /ip dhcp-client set [find where interface="ether1"] add-default-route=yes use-peer-dns=yes comment="LBW:uplink" } on-error={ :log error "LBW fallo: dhcp-client uplink" }
}
# El balanceador le entrega 192.168.88.2 y la ruta por defecto hacia 192.168.88.1.
# Si prefieres IP fija, comenta lo de arriba y usa estas dos lineas:
# /ip address add address=192.168.88.2/24 interface="ether1" comment="LBW:uplink"
# /ip route add dst-address=0.0.0.0/0 gateway=192.168.88.1 comment="LBW:uplink"

# 2. Fuera NAT: el balanceador es quien enmascara
:do {
  :foreach r in=[/ip firewall nat find where action=masquerade && !disabled] do={
    :local c [/ip firewall nat get $r comment]
    /ip firewall nat set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: apartar NAT" }

# 3. FastTrack fuera: se salta las colas y el conteo de trafico
:do {
  :foreach r in=[/ip firewall filter find where action=fasttrack-connection && !disabled] do={
    :local c [/ip firewall filter get $r comment]
    /ip firewall filter set $r disabled=yes comment=("PRE-LBW:" . $c)
  }
} on-error={ :log error "LBW fallo: fasttrack" }

:log warning "LBW: router de abajo listo. Las colas simples siguen funcionando igual."
:put "Listo. Comprueba: /ip route print  y  /queue simple print stats"
