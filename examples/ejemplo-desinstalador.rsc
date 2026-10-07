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
:do { /ip firewall address-list remove [find where comment~"^LBW:(local|fijar)"] } on-error={}

# 3. Rutas y reglas antes que las tablas
:do { /ip route remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: rutas" }
:do { /routing rule remove [find where comment~"^LBW"] } on-error={}
:do { /routing table remove [find where comment~"^LBW"] } on-error={ :log error "LBW-remove: tabla en uso" }

# 3b. Enlace con el router de abajo (si lo creo LBW)
:do { /ip dhcp-server remove [find where comment~"^LBW:(link|lan)"] } on-error={}
:do { /ip dhcp-server network remove [find where comment~"^LBW:(link|lan)"] } on-error={}
:do { /ip pool remove [find where comment~"^LBW:(link|lan)"] } on-error={}
:do { /ip address remove [find where comment~"^LBW:(link|lan)"] } on-error={}

# 3c. LAN creada por LBW (bridge-lan): se quita antes de devolver los puertos
:do { /interface bridge port remove [find where comment~"^LBW:lan"] } on-error={}
:do { /interface bridge remove [find where comment~"^LBW:lan"] } on-error={}

# 3d. DHCP clients ajenos a los que LBW subio la distancia de su ruta
:foreach c in=[/ip dhcp-client find where comment~"^PRE-LBW-DIST:"] do={
  :local cm [/ip dhcp-client get $c comment]
  :local p [:find $cm ":" 13]
  :local d [:tostr [:pick $cm 13 $p]]
  :local rest [:tostr [:pick $cm ($p + 1) [:len $cm]]]
  :do { /ip dhcp-client set $c default-route-distance=[:tonum $d] comment=$rest } on-error={ /ip dhcp-client set $c comment=$rest }
}

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
  :local orig [:tostr [:pick $c $p [:len $c]]]
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
  :local ifn [:tostr [:pick $c ($p2 + 4) [:len $c]]]
  :if ([:len [/interface bridge port find where interface=$ifn]] = 0) do={
    :do { /interface bridge port add bridge=$br interface=$ifn; :log warning ("LBW: " . $ifn . " devuelto al bridge " . $br) } on-error={}
  }
}
:do { /ip firewall address-list remove [find where comment~"^LBW:restore"] } on-error={}

# 6. Reactivar lo que se aparto (PRE-LBW:comentario original)
:foreach r in=[/ip route find where comment~"^PRE-LBW:"] do={
  :local c [/ip route get $r comment]
  :do { /ip route set $r disabled=no comment=[:tostr [:pick $c 8 [:len $c]]] } on-error={ :log error "LBW: no pude restaurar una entrada PRE-LBW" }
}
:foreach r in=[/ip firewall filter find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall filter get $r comment]
  :do { /ip firewall filter set $r disabled=no comment=[:tostr [:pick $c 8 [:len $c]]] } on-error={ :log error "LBW: no pude restaurar una entrada PRE-LBW" }
}
:foreach r in=[/ip firewall nat find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall nat get $r comment]
  :do { /ip firewall nat set $r disabled=no comment=[:tostr [:pick $c 8 [:len $c]]] } on-error={ :log error "LBW: no pude restaurar una entrada PRE-LBW" }
}
:foreach r in=[/ip firewall mangle find where comment~"^PRE-LBW:"] do={
  :local c [/ip firewall mangle get $r comment]
  :do { /ip firewall mangle set $r disabled=no comment=[:tostr [:pick $c 8 [:len $c]]] } on-error={ :log error "LBW: no pude restaurar una entrada PRE-LBW" }
}

# 6b. Servicios del router como estaban antes de LBW
#     Solo entradas estaticas: desde RouterOS 7.19 /ip service lista tambien las
#     conexiones abiertas como entradas dinamicas con el mismo nombre (ssh,
#     winbox...), y esas no se pueden editar.
:foreach a in=[/ip firewall address-list find where comment~"^LBW:svc:"] do={
  :local c [/ip firewall address-list get $a comment]
  :local r [:tostr [:pick $c 8 [:len $c]]]
  :local p [:find $r ":"]
  :local nm [:pick $r 0 $p]
  :local v [:tostr [:pick $r ($p + 1) [:len $r]]]
  :if ($nm = "btest") do={ :do { /tool bandwidth-server set enabled=yes } on-error={} }
  :if ($nm = "smb") do={ :do { /ip smb set enabled=$v } on-error={} }
  :if ($nm != "btest" && $nm != "smb") do={
    :foreach s in=[/ip service find] do={
      :local dyn ""
      :do { :set dyn [:tostr [/ip service get $s dynamic]] } on-error={}
      :if ($dyn != "true" && [/ip service get $s name] = $nm) do={
        :if ($v = "off") do={ :do { /ip service set $s disabled=no } on-error={} }
        :if ([:pick $v 0 3] = "af=") do={
          :local af [:tostr [:pick $v 3 [:len $v]]]
          :do { /ip service set $s available-from=$af } on-error={
            :do { :local f [:parse "/ip service set \$sid address=\$val"]; $f sid=$s val=$af } on-error={}
          }
        }
      }
    }
  }
}
:do { /ip firewall address-list remove [find where comment~"^LBW:svc:"] } on-error={}

# 6c. Log en disco de LBW (los archivos lbw-log se conservan como historial)
:do { /system logging remove [find where action="lbwdisk"] } on-error={}
:do { /system logging action remove [find where name="lbwdisk"] } on-error={}

# 7. Variables globales del monitor
:do { /system script environment remove [find where name~"^LBW"] } on-error={}

:log warning "LBW: configuracion multi-WAN eliminada"
:put "LBW: eliminado. Revisa IP > DNS y IP > DHCP Client si los habias personalizado."
