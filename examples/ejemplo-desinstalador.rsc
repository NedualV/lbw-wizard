# LBW - desinstalador
# LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later - https://github.com/NedualV/lbw-wizard
# Uso: /import file-name=lbw-remove.rsc verbose=yes
:log warning "LBW: iniciando desinstalacion"

# 1. Red de seguridad, monitor y tareas
:do { /system scheduler remove [find where comment~"LBW"] } on-error={ :log error "LBW-remove: scheduler" }
:do { /system script remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: script" }
:do { /tool netwatch remove [find where comment~"^LBW"] } on-error={}

# 2. Firewall
:do { /ip firewall mangle remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: mangle" }
:do { /ip firewall raw remove [find where comment~"^LBW"] } on-error={}
:do { /ip firewall nat remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: nat" }
:do { /ip firewall filter remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: filter" }
:do { /ip firewall address-list remove [find where comment~"^LBW:local"] } on-error={}

# 3. Rutas y reglas antes que las tablas
:do { /ip route remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: rutas" }
:do { /routing rule remove [find where comment~"^LBW"] } on-error={}
:do { /routing table remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: tabla en uso" }

# 3b. Enlace con el router de abajo (si lo creo LBW)
:do { /ip dhcp-server remove [find where comment~"^LBW:link"] } on-error={}
:do { /ip dhcp-server network remove [find where comment~"^LBW:link"] } on-error={}
:do { /ip pool remove [find where comment~"^LBW:link"] } on-error={}
:do { /ip address remove [find where comment~"^LBW:link"] } on-error={}

# 4. DHCP clients: borrar los creados por LBW, restaurar los que ya existian
:foreach d in=[/ip dhcp-client find where comment~"^LBW"] do={
  :local c [/ip dhcp-client get $d comment]
  :if ($c~"^LBW:NEW") do={
    /ip dhcp-client remove $d
  } else={
    :local adr "yes"
    :if ($c~"adr=no") do={ :set adr "no" }
    :if ($c~"adr=false") do={ :set adr "no" }
    :if ($c~"adr=special-classless") do={ :set adr "special-classless" }
    /ip dhcp-client set $d add-default-route=$adr script="" comment=""
    :if ($c~"dns=no") do={ /ip dhcp-client set $d use-peer-dns=no } else={ /ip dhcp-client set $d use-peer-dns=yes }
    :if ($c~"ntp=no") do={ /ip dhcp-client set $d use-peer-ntp=no } else={ /ip dhcp-client set $d use-peer-ntp=yes }
  }
}

# 5. Interfaces: devolver el nombre original y borrar las creadas por LBW
:do { /interface pppoe-client remove [find where comment~"^LBW"] } on-error={}
:do { /interface vlan remove [find where comment~"^LBW"] } on-error={}
:foreach f in=[/interface find where comment~"^LBW:WAN.*:was="] do={
  :local c [/interface get $f comment]
  :local p ([:find $c "was="] + 4)
  :local orig [:pick $c $p [:len $c]]
  :if ([:len [/interface find where name=$orig]] = 0) do={
    /interface set $f name=$orig comment=""
  } else={ /interface set $f comment="" }
}
:do { /interface list member remove [find where comment~"^LBW"] } on-error={}
:do { /interface list remove [find where comment~"^LBW"] } on-error={}

# 5b. Devolver al bridge los puertos que LBW saco para usarlos como WAN
:foreach a in=[/ip firewall address-list find where comment~"^LBW:restore:br="] do={
  :local c [/ip firewall address-list get $a comment]
  :local p1 ([:find $c "br="] + 3)
  :local p2 [:find $c ":if="]
  :local br [:pick $c $p1 $p2]
  :local ifn [:pick $c ($p2 + 4) [:len $c]]
  :if ([:len [/interface bridge port find where interface=$ifn]] = 0) do={
    :do { /interface bridge port add bridge=$br interface=$ifn; :log warning ("LBW: " . $ifn . " devuelto al bridge " . $br) } on-error={}
  }
}
:do { /ip firewall address-list remove [find where comment~"^LBW:restore"] } on-error={}

# 6. Reactivar lo que se aparto (PRE-LBW:comentario original)
:foreach r in=[/ip route find where comment~"^PRE-LBW:"] do={
  :local c [/ip route get $r comment]
  /ip route set $r disabled=no comment=[:pick $c 8 [:len $c]]
}
:foreach r in=[/ip firewall filter find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall filter get $r comment]
  /ip firewall filter set $r disabled=no comment=[:pick $c 8 [:len $c]]
}
:foreach r in=[/ip firewall nat find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall nat get $r comment]
  /ip firewall nat set $r disabled=no comment=[:pick $c 8 [:len $c]]
}
:foreach r in=[/ip firewall mangle find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall mangle get $r comment]
  /ip firewall mangle set $r disabled=no comment=[:pick $c 8 [:len $c]]
}

# 7. Variables globales del monitor
:do { /system script environment remove [find where name~"^LBW"] } on-error={}

:log warning "LBW: configuracion multi-WAN eliminada"
:put "LBW: eliminado. Revisa IP > DNS y IP > DHCP Client si los habias personalizado."
