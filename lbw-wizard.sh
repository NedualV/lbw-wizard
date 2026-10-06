#!/usr/bin/env bash
# =====================================================================
#  LBW Wizard - Asistente Multi-WAN para MikroTik RouterOS v7
#  Balanceo PCC + failover recursivo con doble probe por ISP
#
#  Autor:     Nedual Vargas (@NEDUALV)
#  Copyright (C) 2026 Nedual Vargas
#  Repo:      https://github.com/NedualV/lbw-wizard
#
#  Este programa es software libre: puedes redistribuirlo y/o modificarlo
#  bajo los terminos de la GNU General Public License v3 o posterior.
#  Debes conservar este aviso de autoria en toda copia o version modificada.
#  Se distribuye SIN NINGUNA GARANTIA. Ver el archivo LICENSE.
#
#  SPDX-License-Identifier: GPL-3.0-or-later
# =====================================================================
set -o pipefail
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf8*) :;;
  *) if locale -a 2>/dev/null | grep -qi '^C\.utf8$'; then export LC_ALL=C.UTF-8
     elif locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then export LC_ALL=en_US.UTF-8; fi;;
esac
VERSION="3.0"
AUTHOR="Nedual Vargas (@NEDUALV)"
AUTHOR_ASCII="Nedual Vargas (@NEDUALV)"
REPO_URL="https://github.com/NedualV/lbw-wizard"

# ============================ Terminal ===============================
TTY=0; [[ -t 0 && -t 1 ]] && TTY=1
if [[ -t 1 ]]; then
  N=$'\e[0m'; BOLD=$'\e[1m'
  c(){ printf '\e[38;5;%sm' "$1"; }
else
  N=; BOLD=; c(){ :; }
fi
CA=$(c 45); CO=$(c 42); CW=$(c 214); CE=$(c 203); CD=$(c 245); CT=$(c 255); CB=$(c 39)
PAL=(45 171 214 42 203 111)
TOTAL_STEPS=7
STEP_NAMES=("" "Router" "Modo" "Proveedores" "Reparto" "Red local" "Extras" "Resumen")

layout(){
  COLS=${LBW_COLS:-$(tput cols 2>/dev/null || echo 80)}
  [[ $COLS =~ ^[0-9]+$ ]] || COLS=80
  (( COLS < 44 )) && COLS=44
  WIDTH=$(( COLS - 4 )); (( WIDTH > 120 )) && WIDTH=120; (( WIDTH < 40 )) && WIDTH=40
  MARGIN=$(( (COLS - WIDTH) / 2 )); (( MARGIN < 1 )) && MARGIN=1
  printf -v M '%*s' "$MARGIN" ''
  INNER=$(( WIDTH - 4 ))
}
layout
trap 'layout' WINCH

cleanup_term(){ ((TTY)) && printf '\e[?25h'; stty echo 2>/dev/null; }
trap cleanup_term EXIT
trap 'cleanup_term; echo; echo "${M}Cancelado."; exit 130' INT

strip(){ sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' <<< "$1"; }
vlen(){ local s; s=$(strip "$1"); echo "${#s}"; }
rep(){ local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }
pad(){ local l; l=$(vlen "$1"); printf '%s%*s' "$1" $(( $2 > l ? $2 - l : 0 )) ''; }

# Corta por palabras (nunca a mitad de palabra). wrap "texto" ancho "sangria"
wrap(){
  local text=$1 w=$2 ind=${3:-} line="" word
  (( w < 16 )) && w=16
  for word in $text; do
    if [[ -z $line ]]; then line=$word
    elif (( ${#line} + 1 + ${#word} <= w )); then line+=" $word"
    else printf '%s\n' "$line"; line="${ind}${word}"; fi
  done
  [[ -n $line ]] && printf '%s\n' "$line"
}

ctr(){ local l; l=$(vlen "$1"); local lp=$(( (WIDTH - l) / 2 )); (( lp < 0 )) && lp=0; printf '%s%*s%s\n' "$M" "$lp" '' "$1"; }
rule(){ printf '%s%s%s%s\n' "$M" "${1:-$CD}" "$(rep '─' "$WIDTH")" "$N"; }

say(){ echo "${M}$*"; }
info(){ echo "${M}${CB}i${N} $*"; }
ok(){ echo "${M}${CO}✔${N} $*"; }
warn(){ echo "${M}${CW}⚠${N} $*"; }
err(){ echo "${M}${CE}✖${N} $*"; }
hint(){ local l; while IFS= read -r l; do echo "${M}${CD}${l}${N}"; done < <(wrap "$*" $(( WIDTH - 2 )) "  "); }

box(){ # color "titulo" lineas...
  local col=$1 title=$2; shift 2
  local tl; tl=$(vlen "$title"); local l v sub
  printf '%s%s╭─ %s%s%s%s %s╮%s\n' "$M" "$col" "$BOLD" "$title" "$N" "$col" "$(rep '─' $(( WIDTH - 5 - tl )))" "$N"
  for l in "$@"; do
    v=$(vlen "$l")
    if (( v > INNER )) && [[ $l != *$'\e'* ]]; then
      while IFS= read -r sub; do
        printf '%s%s│%s %s %s│%s\n' "$M" "$col" "$N" "$(pad "$sub" $INNER)" "$col" "$N"
      done < <(wrap "$l" "$INNER" "  ")
    else
      printf '%s%s│%s %s %s│%s\n' "$M" "$col" "$N" "$(pad "$l" $INNER)" "$col" "$N"
    fi
  done
  printf '%s%s╰%s╯%s\n' "$M" "$col" "$(rep '─' $(( WIDTH - 2 )))" "$N"
}

banner(){
  ((TTY)) && printf '\e[2J\e[H'
  echo
  local g=(51 45 39 33 69 105) i=0 l art
  if (( WIDTH >= 76 )); then
    art='██╗     ██████╗ ██╗    ██╗    ██╗    ██╗██╗███████╗ █████╗ ██████╗ ██████╗
██║     ██╔══██╗██║    ██║    ██║    ██║██║╚══███╔╝██╔══██╗██╔══██╗██╔══██╗
██║     ██████╔╝██║ █╗ ██║    ██║ █╗ ██║██║  ███╔╝ ███████║██████╔╝██║  ██║
██║     ██╔══██╗██║███╗██║    ██║███╗██║██║ ███╔╝  ██╔══██║██╔══██╗██║  ██║
███████╗██████╔╝╚███╔███╔╝    ╚███╔███╔╝██║███████╗██║  ██║██║  ██║██████╔╝
╚══════╝╚═════╝  ╚══╝╚══╝      ╚══╝╚══╝ ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝'
  else
    art='██╗     ██████╗ ██╗    ██╗
██║     ██╔══██╗██║    ██║
██║     ██████╔╝██║ █╗ ██║
██║     ██╔══██╗██║███╗██║
███████╗██████╔╝╚███╔███╔╝
╚══════╝╚═════╝  ╚══╝╚══╝'
  fi
  while IFS= read -r l; do ctr "$(c "${g[i]}")${l}${N}"; ((i++)); done <<< "$art"
  echo
  ctr "${BOLD}${CT}Multi-WAN para MikroTik RouterOS v7${N}  ${CD}·  v$VERSION${N}"
  ctr "${CD}© 2026 $AUTHOR · GPL-3.0${N}"
  ctr "${CD}$REPO_URL${N}"
  echo
  rule "$CA"
  echo
}

screen(){ # n
  local n=$1 i bar="" seg=$(( (WIDTH - TOTAL_STEPS + 1) / TOTAL_STEPS ))
  (( seg < 3 )) && seg=3
  ((TTY)) && printf '\e[2J\e[H'
  echo
  ctr "${CA}${BOLD}LBW Wizard${N} ${CD}— Multi-WAN MikroTik RouterOS v7${N}"
  echo
  for ((i=1; i<=TOTAL_STEPS; i++)); do
    if (( i < n )); then bar+="${CO}$(rep '━' $seg)${N}"
    elif (( i == n )); then bar+="${CA}$(rep '━' $seg)${N}"
    else bar+="${CD}$(rep '─' $seg)${N}"; fi
    (( i < TOTAL_STEPS )) && bar+=" "
  done
  echo "${M}$bar"
  ctr "${CD}PASO $n de $TOTAL_STEPS${N} · ${BOLD}${CT}${STEP_NAMES[$n]}${N}"
  echo
}

pause(){
  if ((TTY)); then
    local t="Presiona Enter para continuar…" lp
    lp=$(( MARGIN + (WIDTH - ${#t}) / 2 )); (( lp < 0 )) && lp=0
    read -rsp "$(printf '%*s' "$lp" '')${CD}${t}${N}" _x; echo
  fi
}

# ============================ Controles ==============================
# BACK=1 lo pone cualquier control cuando el usuario pide volver atras
# (Esc o flecha izquierda en terminal; la respuesta "<" sin terminal).
BACK=0
q(){ BACK=0; "$@"; if (( BACK )); then return 10; fi; return 0; }

menu(){ # var "titulo" default "valor|etiqueta|descripcion"...
  local __v=$1 title=$2 def=$3; shift 3
  local -a V L D; local o a b d
  for o in "$@"; do IFS='|' read -r a b d <<< "$o"; V+=("$a"); L+=("$b"); D+=("$d"); done
  local n=${#V[@]} cur=$(( def - 1 )) i k k2 sub
  if ((!TTY)); then
    echo "${M}${BOLD}$title${N}"
    for ((i=0; i<n; i++)); do echo "${M}  $((i+1))) ${L[i]}"; done
    local r
    if ! read -r r; then err "Se acabaron las respuestas antes de terminar: $title"; exit 1; fi
    [[ -z $r ]] && r=$def
    [[ $r =~ ^[0-9]+$ ]] && (( r >= 1 && r <= n )) || r=$def
    printf -v "$__v" '%s' "${V[r-1]}"; return
  fi
  printf '\e[?25l'
  while true; do
    echo "${M}${CA}◆${N} ${BOLD}$title${N}"
    echo "${M}${CD}↑↓ moverte · Enter elegir${N}"
    for ((i=0; i<n; i++)); do
      if (( i == cur )); then echo "${M}${CA}❯ ${BOLD}${L[i]}${N}"
      else echo "${M}  ${CD}${L[i]}${N}"; fi
      if [[ -n ${D[i]} ]]; then
        while IFS= read -r sub; do echo "${M}    ${CD}${sub}${N}"; done < <(wrap "${D[i]}" $(( WIDTH - 6 )) "  ")
      fi
    done
    IFS= read -rsn1 k
    local goback=0
    case $k in
      $'\e') read -rsn2 -t 0.1 k2
             case $k2 in
               '[A') ((cur=(cur-1+n)%n));;
               '[B') ((cur=(cur+1)%n));;
               '[D') goback=1;;
               '') goback=1;;
             esac;;
      '') break;;
      k|K|w) ((cur=(cur-1+n)%n));; j|J|s) ((cur=(cur+1)%n));;
    esac
    if (( goback )); then
      local lb=2; for ((i=0; i<n; i++)); do
        ((lb++)); [[ -n ${D[i]} ]] && lb=$(( lb + $(wrap "${D[i]}" $(( WIDTH - 6 )) "  " | wc -l) ))
      done
      printf '\e[%dA\e[J' "$lb"; printf '\e[?25h'
      BACK=1; return
    fi
    local lines=2; for ((i=0; i<n; i++)); do
      ((lines++)); [[ -n ${D[i]} ]] && lines=$(( lines + $(wrap "${D[i]}" $(( WIDTH - 6 )) "  " | wc -l) ))
    done
    printf '\e[%dA\e[J' "$lines"
  done
  printf '\e[?25h'
  local lines=2; for ((i=0; i<n; i++)); do
    ((lines++)); [[ -n ${D[i]} ]] && lines=$(( lines + $(wrap "${D[i]}" $(( WIDTH - 6 )) "  " | wc -l) ))
  done
  printf '\e[%dA\e[J' "$lines"
  echo "${M}${CO}✔${N} ${CD}$title${N} › ${BOLD}${L[cur]}${N}"
  printf -v "$__v" '%s' "${V[cur]}"
}

is_ip(){ [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_cidr(){ [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; }
is_port(){ [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
is_num(){ [[ $1 =~ ^[0-9]+$ ]] && (( $1 > 0 )); }
is_vlan(){ [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 4094 )); }
is_any(){ [[ -n $1 ]]; }
is_range(){ [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}-([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
ip2int(){ local IFS=. a b c d; read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
int2ip(){ echo "$(( ($1>>24)&255 )).$(( ($1>>16)&255 )).$(( ($1>>8)&255 )).$(( $1&255 ))"; }
cidr_net(){ # 192.168.88.1/24 -> 192.168.88.0/24
  local ip=${1%%/*} len=${1##*/}; [[ $1 == */* ]] || len=32
  local m=$(( len == 0 ? 0 : (0xFFFFFFFF << (32 - len)) & 0xFFFFFFFF ))
  echo "$(int2ip $(( $(ip2int "$ip") & m )))/$len"
}
cidr_pool(){ # rango DHCP por defecto: de .10 (o .2 en redes chicas) al penultimo, sin el gateway
  local ip=${1%%/*} len=${1##*/} n b gw first last
  n=$(ip2int "$(cidr_net "$1" | cut -d/ -f1)"); b=$(( n + (1 << (32 - len)) - 1 )); gw=$(ip2int "$ip")
  if (( (1 << (32 - len)) > 32 )); then first=$(( n + 10 )); else first=$(( n + 2 )); fi
  last=$(( b - 1 ))
  (( gw >= first && gw <= last )) && { (( gw - first > last - gw )) && last=$(( gw - 1 )) || first=$(( gw + 1 )); }
  echo "$(int2ip $first)-$(int2ip $last)"
}

input(){ # var "pregunta" default validador "error" ["pista"]
  local __v=$1 q=$2 def=$3 val=${4:-is_any} emsg=${5:-"Valor no válido."} tip=${6:-}
  local r
  [[ -n $tip ]] && hint "$tip"
  while true; do
    if ((TTY)); then read -rp "${M}${CA}◆${N} ${BOLD}$q${N}${CD}$([[ -n $def ]] && echo " [$def]")${N} › " r
      if [[ $r == "<" ]]; then printf '\e[1A\e[2K'; BACK=1; return; fi
    else
      if ! read -r r; then
        r=$def
        if ! $val "$r"; then err "Falta la respuesta para: $q"; exit 1; fi
      fi
      [[ $r == "<" ]] && { BACK=1; return; }
    fi
    [[ -z $r ]] && r=$def
    if $val "$r"; then
      ((TTY)) && { printf '\e[1A\e[2K'; echo "${M}${CO}✔${N} ${CD}$q${N} › ${BOLD}$r${N}"; }
      printf -v "$__v" '%s' "$r"; return
    fi
    err "$emsg"
  done
}

secret(){ # var "pregunta"
  local __v=$1 q=$2 r
  if ((TTY)); then read -rsp "${M}${CA}◆${N} ${BOLD}$q${N} › " r; echo
    if [[ $r == "<" ]]; then printf '\e[1A\e[2K'; BACK=1; return; fi
    printf '\e[1A\e[2K'; echo "${M}${CO}✔${N} ${CD}$q${N} › ${BOLD}$([[ -n $r ]] && echo "••••••••" || echo "(vacía)")${N}"
  else read -r r || r=""; [[ $r == "<" ]] && { BACK=1; return; }; fi
  printf -v "$__v" '%s' "$r"
}

confirm(){ # var "pregunta" default(s/n)
  local __v=$1 q=$2 def=$3 r
  if [[ $def == s ]]; then menu "$__v" "$q" 1 "s|Sí|" "n|No|"; else menu "$__v" "$q" 2 "s|Sí|" "n|No|"; fi
}

run(){ # "mensaje" comando...
  # El comando corre en ESTE shell (no en un subshell), para que las funciones
  # que llenan variables globales -como detect_router o audit_router- conserven
  # lo que leen. El spinner va aparte, en segundo plano y escribiendo a stderr,
  # para no ensuciar la salida cuando el llamador captura stdout.
  local msg=$1; shift
  if ((!TTY)); then "$@" 2>/dev/null; return $?; fi
  local f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  ( i=0; while :; do printf '\r%s%s%s%s %s' "$M" "$CA" "${f:i++%10:1}" "$N" "$msg" >&2; sleep 0.1; done ) &
  local spid=$!
  "$@" 2>/dev/null
  local rc=$?
  { kill "$spid"; wait "$spid"; } 2>/dev/null
  printf '\r\e[2K' >&2
  return $rc
}

# ============================ SSH ====================================
RHOST=""; RUSER="admin"; RPORT="22"; DETECTED=0
SSHOPT=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR)
rssh(){
  if command -v sshpass >/dev/null 2>&1 && [[ -n ${SSHPASS:-} ]]; then
    sshpass -e ssh "${SSHOPT[@]}" -p "$RPORT" "$RUSER@$RHOST" "$@"
  else
    ssh "${SSHOPT[@]}" -p "$RPORT" "$RUSER@$RHOST" "$@"
  fi
}
rscp(){
  if command -v sshpass >/dev/null 2>&1 && [[ -n ${SSHPASS:-} ]]; then
    sshpass -e scp "${SSHOPT[@]}" -O -P "$RPORT" "$@" "$RUSER@$RHOST:/"
  else
    scp "${SSHOPT[@]}" -O -P "$RPORT" "$@" "$RUSER@$RHOST:/"
  fi
}

rget(){ # baja archivos del router a esta carpeta
  local f
  for f in "$@"; do
    if command -v sshpass >/dev/null 2>&1 && [[ -n ${SSHPASS:-} ]]; then
      sshpass -e scp "${SSHOPT[@]}" -O -P "$RPORT" "$RUSER@$RHOST:$f" . || return 1
    else
      scp "${SSHOPT[@]}" -O -P "$RPORT" "$RUSER@$RHOST:$f" . || return 1
    fi
  done
}

BOARD=""; IDENT=""; ROS_VER=""; FWCOUNT=0; ARCH=""; CPUN=0; LICLEVEL=""; IS_CHR=0; IFLIST=(); IFTYPE=(); IFRUN=(); IFADDR=()
detect_router(){
  local raw
  raw=$(rssh ':put ("BOARD|" . [/system resource get board-name]); :put ("IDENT|" . [/system identity get name]); :put ("VER|" . [/system resource get version]); :put ("FW|" . [:len [/ip firewall filter find]]); :put ("ARCH|" . [/system resource get architecture-name]); :put ("CPUN|" . [/system resource get cpu-count]); :do { :put ("LIC|" . [/system license get level]) } on-error={}; :foreach i in=[/interface find where !disabled] do={ :local n [/interface get $i name]; :local a ""; :foreach x in=[/ip address find where interface=$n] do={ :set a ([/ip address get $x address]) }; :put ("IF|" . $n . "|" . [/interface get $i type] . "|" . [/interface get $i running] . "|" . $a) }' 2>/dev/null | tr -d '\r')
  [[ -z $raw ]] && return 1
  IFLIST=(); IFTYPE=(); IFRUN=(); IFADDR=()
  local l f1 f2 f3 f4 f5
  while IFS= read -r l; do
    IFS='|' read -r f1 f2 f3 f4 f5 <<< "$l"
    case $f1 in
      BOARD) BOARD=$f2;; IDENT) IDENT=$f2;; VER) ROS_VER=$f2;; FW) FWCOUNT=$f2;;
      ARCH) ARCH=$f2;; CPUN) CPUN=$f2;; LIC) LICLEVEL=$f2;;
      IF) IFLIST+=("$f2"); IFTYPE+=("$f3"); IFRUN+=("$f4"); IFADDR+=("$f5");;
    esac
  done <<< "$raw"
  [[ -n $BOARD ]] || return 1
  # CHR = RouterOS virtual (Proxmox, VMware, nube). No trae config de fabrica.
  IS_CHR=0; [[ $BOARD == CHR* || $BOARD == *"CHR"* ]] && IS_CHR=1
  return 0
}

# Interfaz por la que entra la sesion SSH actual (la que tiene la IP de RHOST)
mgmt_if(){ local i; for i in "${!IFLIST[@]}"; do [[ ${IFADDR[i]%%/*} == "$RHOST" ]] && { echo "${IFLIST[i]}"; return; }; done; }

ifidx(){ local i; for i in "${!IFLIST[@]}"; do [[ ${IFLIST[i]} == "$1" ]] && { echo "$i"; return; }; done; echo -1; }
ifdesc(){
  local i; i=$(ifidx "$1"); (( i < 0 )) && { echo ""; return; }
  local d="${IFTYPE[i]}"
  [[ ${IFRUN[i]} == true ]] && d+=" · con enlace" || d+=" · sin enlace"
  [[ -n ${IFADDR[i]} ]] && d+=" · ${IFADDR[i]}"
  echo "$d"
}
is_wan_candidate(){
  local i; i=$(ifidx "$1"); (( i < 0 )) && return 1
  case ${IFTYPE[i]} in ether|lte|wlan|vlan|pppoe-out) return 0;; *) return 1;; esac
}

LINKHASADDR=0; LINKHASDHCP=0
probe_link(){ # mira si el puerto del enlace ya tiene IP y servidor DHCP
  local raw
  raw=$(rssh ":put (\"A|\" . [:len [/ip address find where interface=\"$1\"]]); :put (\"D|\" . [:len [/ip dhcp-server find where interface=\"$1\"]])" 2>/dev/null | tr -d '\r')
  [[ -z $raw ]] && return 1
  LINKHASADDR=$(grep '^A|' <<< "$raw" | cut -d'|' -f2)
  LINKHASDHCP=$(grep '^D|' <<< "$raw" | cut -d'|' -f2)
  return 0
}

AUDIT_FT=0; AUDIT_DEFROUTE=0; AUDIT_MANGLE=0; AUDIT_TABLES=""; AUDIT_NAT=0
AUDIT_HOTSPOT=0; AUDIT_PPPSRV=0; AUDIT_QUEUE=0; AUDIT_ROLLBACK=0; AUDIT_LBW=0
AUDIT_DHCPSRV=0; AUDIT_FWIN=0; AUDIT_FWFWD=0; AUDIT_DHCPDR=0
audit_router(){
  local raw
  raw=$(rssh ':put ("FT|" . [:len [/ip firewall filter find where action=fasttrack-connection && !disabled]]); :put ("DR|" . [:len [/ip route find where dst-address="0.0.0.0/0" && static]]); :put ("MR|" . [:len [/ip firewall mangle find where action=mark-routing && !(comment~"^LBW")]]); :put ("TB|" . [:len [/routing table find where !(name="main")]]); :put ("NT|" . [:len [/ip firewall nat find where action=masquerade && out-interface-list=""]]); :put ("HS|" . [:len [/ip hotspot find]]); :put ("PS|" . [:len [/interface pppoe-server server find]]); :put ("QS|" . [:len [/queue simple find]]); :put ("RB|" . [:len [/system scheduler find where comment~"ROLLBACK-LBW"]]); :put ("LB|" . [:len [/ip firewall mangle find where comment~"^LBW"]]); :put ("DS|" . [:len [/ip dhcp-server find where !disabled]]); :put ("FI|" . [:len [/ip firewall filter find where chain=input && !dynamic && !disabled]]); :put ("FF|" . [:len [/ip firewall filter find where chain=forward && !dynamic && !disabled]]); :do { :local dd 0; :foreach c in=[/ip dhcp-client find where !disabled] do={ :local v [:tostr [/ip dhcp-client get $c add-default-route]]; :if ($v != "no" && $v != "false") do={ :set dd ($dd + 1) } }; :put ("DD|" . $dd) } on-error={}' 2>/dev/null | tr -d '\r')
  [[ -z $raw ]] && return 1
  local l a b
  while IFS= read -r l; do
    IFS='|' read -r a b <<< "$l"
    case $a in
      FT) AUDIT_FT=${b:-0};; DR) AUDIT_DEFROUTE=${b:-0};; MR) AUDIT_MANGLE=${b:-0};;
      TB) AUDIT_TABLES=${b:-0};; NT) AUDIT_NAT=${b:-0};; HS) AUDIT_HOTSPOT=${b:-0};;
      PS) AUDIT_PPPSRV=${b:-0};; QS) AUDIT_QUEUE=${b:-0};; RB) AUDIT_ROLLBACK=${b:-0};; LB) AUDIT_LBW=${b:-0};;
      DS) AUDIT_DHCPSRV=${b:-0};; FI) AUDIT_FWIN=${b:-0};; FF) AUDIT_FWFWD=${b:-0};; DD) AUDIT_DHCPDR=${b:-0};;
    esac
  done <<< "$raw"
  return 0
}

# ====================== Datos de la configuracion ====================
declare -a WNAME WIF WIFBASE WFINAL WTYPE WADDR WGW WUSER WPASS WVLAN WSPEED WROLE WP1 WP2
PROBE_POOL=(
 "9.9.9.9|208.67.222.222"
 "149.112.112.112|208.67.220.220"
 "64.6.64.6|4.2.2.2"
 "64.6.65.6|4.2.2.1"
 "76.76.2.0|94.140.14.14"
 "76.76.10.0|94.140.15.15"
)
MODE="lb"; NWAN=2; CLASSIFIER="both-addresses"; LANIFS=""; LANNETS=""
DNS="1.1.1.1,8.8.8.8"; DNSREMOTE="s"; MSSCLAMP="s"; PROTECTWAN="s"
ROLE="router"; DOWNGW=""; BALIP=""; CLIENTNETS=""; LINKMODE="auto"; LINKNET=""; UPIF="ether1"; LINKDHCP="si"
TGENABLE="n"; TGTOKEN=""; TGCHAT=""; ROLLBACK_MIN=10; STARTMODE="keep"
LANMODE="existing"; LANCREATE="n"; LANPORTS=""; LANGW=""; LANPOOL=""
OUTNAME="lbw-config.rsc"

gcd(){ local a=$1 b=$2 t; while (( b )); do t=$b; b=$(( a % b )); a=$t; done; echo "$a"; }

calc_weights(){ # llena WEIGHT[i] y TOTBUCKETS
  declare -ga WEIGHT; local i g=0 min=999999 sum=0
  for ((i=1; i<=NWAN; i++)); do (( ${WSPEED[$i]} < min )) && min=${WSPEED[$i]}; done
  for ((i=1; i<=NWAN; i++)); do WEIGHT[$i]=$(( (${WSPEED[$i]} + min/2) / min )); (( ${WEIGHT[$i]} < 1 )) && WEIGHT[$i]=1; done
  g=${WEIGHT[1]}; for ((i=2; i<=NWAN; i++)); do g=$(gcd "$g" "${WEIGHT[i]}"); done
  (( g < 1 )) && g=1
  for ((i=1; i<=NWAN; i++)); do WEIGHT[$i]=$(( ${WEIGHT[$i]} / g )); done
  sum=0; for ((i=1; i<=NWAN; i++)); do sum=$(( sum + ${WEIGHT[$i]} )); done
  while (( sum > 10 )); do
    for ((i=1; i<=NWAN; i++)); do (( ${WEIGHT[$i]} > 1 )) && WEIGHT[$i]=$(( ${WEIGHT[$i]} - 1 )); done
    sum=0; for ((i=1; i<=NWAN; i++)); do sum=$(( sum + ${WEIGHT[$i]} )); done
  done
  TOTBUCKETS=$sum
}

draw_bars(){
  calc_weights
  local i w barw=$(( WIDTH - 28 )) full pct
  (( barw < 10 )) && barw=10
  say "${BOLD}Así se repartirán las conexiones nuevas${N}"
  echo
  for ((i=1; i<=NWAN; i++)); do
    pct=$(( ${WEIGHT[$i]} * 100 / TOTBUCKETS ))
    full=$(( ${WEIGHT[$i]} * barw / TOTBUCKETS ))
    printf '%s%s%s %s%s%s%s %3s%%  %s Mbps%s\n' "$M" "$(c "${PAL[(i-1)%6]}")" "$(pad "${WNAME[$i]}" 10)" \
      "$(rep '█' $full)" "${CD}" "$(rep '░' $(( barw - full )))" "$N" "$pct" "${WSPEED[$i]}" "$N"
  done
  echo
  hint "Se reparten CONEXIONES, no megas. Una sola descarga usa una sola línea; la suma se nota con varios equipos o descargas en paralelo."
}

draw_topology(){
  local i line
  say "${CD}Internet${N}"
  for ((i=1; i<=NWAN; i++)); do
    line="${M}   ${CD}│${N}  $(c "${PAL[(i-1)%6]}")▇${N} $(pad "${WNAME[$i]}" 12) ${CD}$(pad "${WFINAL[$i]:-${WIF[$i]}}" 18)"
    [[ $MODE == lb ]] && line+="${WSPEED[$i]} Mbps" || line+="$([[ ${WROLE[$i]} == main ]] && echo "principal" || echo "respaldo")"
    echo "${line}${N}"
  done
  say "${CD}   ▼${N}"
  say "${BOLD}   MikroTik${N} ${CD}${BOARD:-RouterOS v7}${N}"
  say "${CD}   ▼  LAN: ${LANNETS:-por definir}${N}"
}

# ========================= Pasos del asistente =======================
# Cada paso es una funcion: 0 = seguir, 10 = volver al paso anterior.
# Los controles devuelven 10 cuando el usuario pulsa Esc o <-.

connect_loop(){ # reintenta la conexion SSH hasta lograrla o rendirse
  while true; do
    q input RHOST "IP del router" "${RHOST:-192.168.88.1}" is_ip "Escribe una IP válida." "Usa la IP de la LAN, no la de un ISP" || return 10
    q input RUSER "Usuario" "${RUSER:-admin}" is_any || return 10
    q input RPORT "Puerto SSH" "${RPORT:-22}" is_port "Puerto entre 1 y 65535." "Si cambiaste el puerto en IP → Services, ponlo aquí" || return 10
    if command -v sshpass >/dev/null 2>&1; then
      q secret SSHPASS "Contraseña del router (vacía si no tiene)" || return 10
      export SSHPASS
    else
      hint "Consejo: instala sshpass (sudo dnf install sshpass) para escribir la contraseña una sola vez."
    fi
    run "Leyendo la configuración del router…" detect_router && return 0
    err "No pude conectarme a $RUSER@$RHOST:$RPORT."
    hint "Causas típicas: SSH apagado o en otro puerto (IP → Services), usuario o contraseña incorrectos, o el router no responde en esa IP."
    local r
    q menu r "¿Qué hacemos?" 1 "retry|Intentar de nuevo|Se conservan los datos que ya escribiste" "manual|Seguir en modo manual|Sin conexión: escribes tú los nombres" || return 10
    [[ $r == manual ]] && return 1
  done
}

do_reset(){ # resetea y vuelve a conectar, para que el asistente vea el router limpio
  local kind=$1
  box "$CW" "Esto va a resetear el router" \
    "Se borra TODA la configuración: IPs, firewall, DHCP, usuarios y archivos." \
    "El router se reinicia y pierdes la conexión actual." \
    "$([[ $kind == bare ]] && echo "Quedará SIN IP y SIN DHCP: solo lo recuperas por cable con MAC-Winbox." || echo "Volverá con la configuración de fábrica en 192.168.88.1, usuario admin y la contraseña de la etiqueta (vacía en equipos antiguos).")" \
    "Tu PC tendrá que renovar la IP para volver a entrar."
  local c
  q confirm c "¿Seguro que quieres resetear?" n || return 10
  [[ $c != s ]] && return 1
  run "Guardando copia de seguridad…" rssh '/system backup save name="pre-lbw"; /export file="pre-lbw"' >/dev/null
  sleep 2
  if run "Descargando la copia a esta carpeta…" rget "pre-lbw.backup" "pre-lbw.rsc"; then
    ok "Copia guardada aquí: pre-lbw.backup y pre-lbw.rsc"
  else
    warn "No pude descargar la copia. Se queda en el router, pero el reset la borra."
    q confirm c "¿Sigo de todos modos?" n || return 10
    [[ $c != s ]] && return 1
  fi
  info "Reseteando…"
  if [[ $kind == bare ]]; then
    rssh '/system reset-configuration no-defaults=yes skip-backup=yes' >/dev/null 2>&1
  else
    rssh '/system reset-configuration skip-backup=yes' >/dev/null 2>&1
  fi
  echo
  box "$CA" "El router se está reiniciando" \
    "Renueva la IP en tu PC (desconecta y conecta el cable, o pide IP otra vez)." \
    "$([[ $kind == bare ]] && echo "Sin configuración no hay DHCP ni IP: entra por MAC-Winbox, ponle una IP y vuelve aquí." || echo "Cuando vuelva: 192.168.88.1, usuario admin, contraseña de la etiqueta (o vacía en equipos antiguos).")" \
    "Si al entrar te obliga a cambiar la contraseña, hazlo una vez por Winbox y vuelve aquí."
  echo
  if [[ $kind == bare ]]; then
    RHOST=""; RUSER="admin"; RPORT="22"; SSHPASS=""
  else
    RHOST="192.168.88.1"; RUSER="admin"; RPORT="22"; SSHPASS=""
    if command -v sshpass >/dev/null 2>&1; then
      secret SSHPASS "Contraseña tras el reset (la de la etiqueta; Enter si no trae)"
    fi
    export SSHPASS
    info "Esperando a que el router vuelva (hasta 2 minutos)…"
    local s2
    for s2 in $(seq 1 60); do
      sleep 2
      if run "Probando $RUSER@$RHOST…" detect_router; then ok "Router de vuelta en $RHOST."; return 0; fi
    done
    warn "No respondió en $RHOST. Dime cómo llegar a él."
  fi
  connect_loop
}

step_router(){
  screen 1
  local START
  q menu START "¿Cómo quieres empezar?" 1 \
    "ssh|Conectarme al router y detectar sus puertos|Recomendado: lee interfaces, IPs y versión por SSH. No cambia nada." \
    "manual|Modo manual, sin conexión|Escribes tú los nombres de interfaz; útil para preparar un .rsc por adelantado" || return 10
  [[ $START == manual ]] && { DETECTED=0; return 0; }

  connect_loop; local rc=$?
  (( rc == 10 )) && return 10
  (( rc == 1 )) && { DETECTED=0; return 0; }
  DETECTED=1

  local major=${ROS_VER%%.*}
  if [[ $major =~ ^[0-9]+$ ]] && (( major < 7 )); then
    box "$CE" "RouterOS no compatible" "Este router tiene RouterOS $ROS_VER." "LBW Wizard necesita RouterOS v7 (System → Packages → Check for updates)."
    exit 1
  elif [[ ! $major =~ ^[0-9]+$ ]]; then
    warn "No pude leer la versión de RouterOS (respondió: '${ROS_VER:-nada}')."
    local vok; q confirm vok "¿Sigo de todos modos? (hace falta RouterOS v7)" s || return 10
    [[ $vok != s ]] && exit 1
  fi

  local nif=0 x
  for x in "${IFLIST[@]}"; do is_wan_candidate "$x" && ((nif++)); done
  box "$CO" "Router detectado" \
    "Modelo:     $BOARD" \
    "Nombre:     $IDENT" \
    "RouterOS:   $ROS_VER" \
    "Plataforma: $( ((IS_CHR)) && echo "CHR (virtual) · licencia ${LICLEVEL:-?}" || echo "RouterBOARD físico · ${ARCH:-?} · ${CPUN:-?} núcleo(s)")" \
    "Interfaces: $nif utilizables como WAN" \
    "Firewall:   $FWCOUNT reglas"
  echo
  if run "Revisando qué puede chocar con el balanceo…" audit_router; then
    local alerts=()
    (( AUDIT_ROLLBACK > 0 )) && alerts+=("⚠ Hay una red de seguridad (ROLLBACK-LBW) armada de un intento anterior: te borrará esta configuración si no la desarmas.")
    (( AUDIT_LBW > 0 )) && alerts+=("⚠ Ya hay reglas LBW en el router. Se reemplazan al aplicar.")
    if (( AUDIT_FT > 0 )); then
      if (( IS_CHR )); then alerts+=("• FastTrack activo ($AUDIT_FT reglas): se desactiva, es incompatible con el balanceo. En CHR el costo de CPU es bajo.")
      else alerts+=("• FastTrack activo ($AUDIT_FT reglas): se desactiva, es incompatible con el balanceo. En equipos ${ARCH:-ARM/MIPS} de pocos núcleos baja el máximo de Mbps: revisa la tabla 'Test results' de tu modelo en mikrotik.com."); fi
    fi
    (( IS_CHR )) && [[ ${LICLEVEL,,} == free ]] && alerts+=("• CHR con licencia free: cada interfaz queda limitada a 1 Mbps de subida. Sirve para probar el failover y el reparto, NO para medir velocidad (usa la prueba p1 de 60 días).")
    (( AUDIT_DHCPDR > 0 )) && alerts+=("• $AUDIT_DHCPDR DHCP client(s) instalan su propia ruta por defecto. Los que no sean WAN de LBW pasan a distancia 200 (quedan de último recurso); el desinstalador les devuelve su valor.")
    if (( AUDIT_FWIN == 0 || AUDIT_FWFWD == 0 )); then alerts+=("• Firewall incompleto (input: $AUDIT_FWIN reglas, forward: $AUDIT_FWFWD). Contesta Sí a 'Bloquear el acceso desde Internet' en Extras: pone las reglas básicas del defconf.")
    fi
    (( AUDIT_DHCPSRV == 0 )) && alerts+=("• No hay servidor DHCP activo: en modo todo en uno el asistente te ofrecerá crear la LAN (bridge, IP y DHCP).")
    (( AUDIT_DEFROUTE > 0 )) && alerts+=("• $AUDIT_DEFROUTE ruta(s) por defecto estáticas: se apartan y el desinstalador las devuelve.")
    (( AUDIT_MANGLE > 0 )) && alerts+=("• $AUDIT_MANGLE regla(s) mangle con mark-routing ajenas: pueden pelear con el balanceo. Revísalas a mano.")
    (( AUDIT_TABLES > 0 )) && alerts+=("• $AUDIT_TABLES tabla(s) de ruteo ya creadas: si se llaman to_WANx habrá conflicto.")
    (( AUDIT_NAT > 0 )) && alerts+=("• $AUDIT_NAT regla(s) masquerade sin lista de salida: se apartan y se pone una con out-interface-list.")
    (( AUDIT_HOTSPOT > 0 )) && alerts+=("• Hotspot configurado: mete su propio NAT y marcado. No probado con LBW.")
    (( AUDIT_PPPSRV > 0 )) && alerts+=("• Servidor PPPoE activo: revisa que sus clientes no entren al balanceo.")
    (( AUDIT_QUEUE > 0 )) && alerts+=("• $AUDIT_QUEUE cola(s) simples: si están atadas a una interfaz, el renombrado las deja sin efecto.")
    if (( ${#alerts[@]} )); then box "$CW" "Qué encontré en este router" "${alerts[@]}"
    else box "$CO" "Qué encontré en este router" "Nada que choque con el balanceo. Router limpio."; fi
    echo
  fi
  if (( IS_CHR )); then
    # El CHR no tiene configuracion de fabrica (sin 192.168.88.1, sin bridge,
    # sin firewall): "resetear a fabrica" no aporta nada y deja la VM a ciegas.
    q menu STARTMODE "¿Cómo quieres partir?" 1 \
      "keep|Trabajar sobre la configuración actual  ★ recomendado|Aparta solo lo que choca y lo marca como PRE-LBW para que el desinstalador lo devuelva." \
      "bare|Reset total sin configuración (avanzado)|El CHR queda sin IP: solo lo recuperas por la consola de la VM (Proxmox, VMware…)." || return 10
  else
    q menu STARTMODE "¿Cómo quieres partir?" 1 \
      "keep|Trabajar sobre la configuración actual  ★ recomendado|Aparta solo lo que choca y lo marca como PRE-LBW para que el desinstalador lo devuelva. No pierdes port forwards, VPN ni DHCP estáticos." \
      "reset|Resetear a configuración de fábrica primero|Router nuevo o de caja. Se hace AHORA, antes de seguir, para que el asistente vea los nombres reales de después." \
      "bare|Reset total sin configuración (avanzado)|El router queda sin IP y sin DHCP: solo recuperable por cable con MAC-Winbox." || return 10
  fi
  if [[ $STARTMODE != keep ]]; then
    do_reset "$STARTMODE"; rc=$?
    (( rc == 10 )) && return 10
    if (( rc == 1 )); then STARTMODE="keep"
    else
      # comprobar que de verdad quedo limpio antes de seguir
      if run "Comprobando que quedó limpio…" audit_router; then
        local resto=0
        resto=$(( ${AUDIT_LBW:-0} + ${AUDIT_ROLLBACK:-0} + ${AUDIT_MANGLE:-0} + ${AUDIT_TABLES:-0} ))
        if (( resto == 0 )); then
          box "$CO" "Router de fábrica, sin residuos" \
            "Sin reglas LBW, sin tablas de ruteo propias, sin mangle ajeno y sin rollback pendiente." \
            "Firewall de fábrica: $FWCOUNT reglas (se conservan; LBW suma las suyas sin duplicar el orden)." \
            "FastTrack activo: $AUDIT_FT regla(s), se desactiva al aplicar."
        else
          box "$CW" "Quedó algo del estado anterior" \
            "LBW: ${AUDIT_LBW:-0} reglas · tablas: ${AUDIT_TABLES:-0} · mangle ajeno: ${AUDIT_MANGLE:-0} · rollback: ${AUDIT_ROLLBACK:-0}" \
            "El asistente lo reemplaza al aplicar, pero si prefieres partir de cero, resetea otra vez."
        fi
        echo
      fi
      STARTMODE="keep"
    fi
  fi
  pause
  return 0
}

step_mode(){
  screen 2
  q menu MODE "¿Qué quieres lograr?" 1 \
    "lb|Sumar velocidad + respaldo automático|Balanceo: usa todas las líneas a la vez y, si una cae, las demás la cubren" \
    "fo|Solo respaldo automático|Failover: usa una línea principal; las otras entran solo si la principal cae" || return 10
  return 0
}

step_wans(){
  screen 3
  q menu NWAN "¿Cuántos proveedores de Internet vas a conectar?" 1 \
    "2|2 proveedores|Lo más común: dos ISP, o un ISP + LTE" "3|3 proveedores|" "4|4 proveedores|" "5|5 proveedores|" "6|6 proveedores|" || return 10

  local i=1 t v pick opts x p1 p2 base
  while (( i <= NWAN )); do
    USED_IFS=" "
    local j; for ((j=1; j<i; j++)); do USED_IFS+="${WIFBASE[$j]} "; done
    screen 3
    say "${CA}${BOLD}Proveedor $i de $NWAN${N}   ${CD}(Esc o ← para volver)${N}"; echo
    q input WNAME[$i] "Nombre de esta línea (como la llamas tú)" "${WNAME[$i]:-ISP$i}" is_any "Escribe algo." "Ej.: Claro, Altice, Starlink, LTE" || { (( i == 1 )) && return 10; ((i--)); continue; }
    if (( DETECTED )); then
      opts=()
      for x in "${IFLIST[@]}"; do
        is_wan_candidate "$x" || continue
        [[ $USED_IFS == *" ${x%_ISP[0-9]} "* ]] && continue
        opts+=("$x|$x|$(ifdesc "$x")")
      done
      opts+=("__other|Escribir otra interfaz|Por ejemplo una interfaz que aún no existe")
      q menu pick "¿En qué puerto está conectado ${WNAME[$i]}?" 1 "${opts[@]}" || { (( i == 1 )) && return 10; ((i--)); continue; }
      if [[ $pick == __other ]]; then
        q input WIFBASE[$i] "Nombre de la interfaz" "ether$i" is_any || { ((i--)); continue; }
      else WIFBASE[$i]=$pick; fi
    else
      q input WIFBASE[$i] "¿En qué puerto está conectado ${WNAME[$i]}?" "${WIFBASE[$i]:-ether$i}" is_any "Escribe el nombre." "Tal como aparece en Winbox: ether1, sfp1, lte1…" || { (( i == 1 )) && return 10; ((i--)); continue; }
    fi
    # si la interfaz ya trae el sufijo de una instalacion anterior, no lo duplicamos
    WIFBASE[$i]=${WIFBASE[$i]%_ISP[0-9]}
    base=${WIFBASE[$i]}

    q menu t "¿Cómo recibe la IP esta línea?" 1 \
      "dhcp|Automática (DHCP)|Lo normal con un módem o router del ISP" \
      "pppoe|PPPoE con usuario y contraseña|Fibra o DSL conectada directo al MikroTik" \
      "static|IP fija|El ISP te dio IP, máscara y gateway" \
      "ptp|Interfaz que ya trae su salida (LTE, túnel, otro router)|El gateway es la propia interfaz" || { ((i--)); (( i < 1 )) && return 10; continue; }
    WTYPE[$i]=$t

    q menu v "¿El ISP te entrega el servicio en una VLAN?" 2 "si|Sí|Hay que crear una interfaz VLAN sobre el puerto" "no|No|Lo más común" || continue
    if [[ $v == si ]]; then
      q input WVLAN[$i] "ID de VLAN" "${WVLAN[$i]:-100}" is_vlan "Entre 1 y 4094." || continue
    else WVLAN[$i]=0; fi

    case ${WTYPE[$i]} in
      static)
        q input WADDR[$i] "IP y máscara que te dio el ISP" "${WADDR[$i]}" is_cidr "Formato: 192.168.1.2/24" || continue
        q input WGW[$i] "Gateway del ISP" "${WGW[$i]}" is_ip "Escribe una IP válida." || continue
        ;;
      pppoe)
        q input WUSER[$i] "Usuario PPPoE" "${WUSER[$i]}" is_any || continue
        q secret WPASS[$i] "Contraseña PPPoE" || continue
        ;;
    esac

    if [[ $MODE == lb ]]; then
      q input WSPEED[$i] "¿De cuántos megas es el contrato de ${WNAME[$i]}? (Mbps)" "${WSPEED[$i]:-100}" is_num "Escribe un número mayor que 0." "Solo la bajada. Sirve para repartir las conexiones en proporción." || continue
      WROLE[$i]="main"
    else
      WSPEED[$i]=100
      if (( i == 1 )); then WROLE[$i]="main"; say "  ${CD}Esta será la línea principal.${N}"
      else WROLE[$i]="backup"; say "  ${CD}Esta entra como respaldo #$((i-1)).${N}"; fi
    fi
    IFS='|' read -r p1 p2 <<< "${PROBE_POOL[$((i-1))]}"
    WP1[$i]=$p1; WP2[$i]=$p2
    if [[ ${WTYPE[$i]} == pppoe ]]; then WFINAL[$i]="pppoe_ISP$i"
    elif (( ${WVLAN[$i]:-0} > 0 )); then WFINAL[$i]="vlan${WVLAN[$i]}_ISP$i"
    else WFINAL[$i]="${base}_ISP$i"; fi
    WIF[$i]=$base
    echo
    ok "${WNAME[$i]} › ${base} → ${BOLD}${WFINAL[$i]}${N}  (probes: $p1 y $p2)"
    sleep 0.4
    ((i++))
  done
  return 0
}

step_split(){
  screen 4
  if [[ $MODE == lb ]]; then
    draw_bars; echo
    calc_weights
    if (( TOTBUCKETS > 2 )); then
      warn "El reparto queda en $TOTBUCKETS partes. Con más de 2, las videollamadas y los juegos (WebRTC) pueden perder paquetes de subida, porque una misma app sale por dos IP públicas distintas."
      local RATIO
      q menu RATIO "¿Cómo reparto entonces?" 2 \
        "exact|Exacto, según la velocidad contratada|Aprovecha mejor la línea más rápida, pero puede afectar Zoom, Teams, Discord y juegos" \
        "even|Partes iguales para todas  ★ recomendado|Más estable para tiempo real. Igual sumas velocidad con varias descargas a la vez." || return 10
      if [[ $RATIO == even ]]; then
        local i; for ((i=1; i<=NWAN; i++)); do WSPEED[$i]=100; done
        calc_weights; echo; draw_bars; echo
      fi
    fi
    q menu CLASSIFIER "¿Qué tan fino repartir?" 2 \
      "src-address|Por equipo|Cada PC o celular usa siempre la misma línea. Máxima compatibilidad con bancos, videollamadas y juegos." \
      "both-addresses|Por equipo y sitio web  ★ recomendado|Cada sitio ve siempre tu misma IP, pero sitios distintos usan líneas distintas. Buen equilibrio." \
      "both-addresses-and-ports|Por conexión|Máximo reparto, pero bancos y juegos pueden cerrarte la sesión al cambiar de IP." || return 10
  else
    say "En modo solo respaldo no hay reparto: ${BOLD}${WNAME[1]}${N} lleva todo el tráfico."
    say "Las demás líneas entran por orden si la principal cae."
    CLASSIFIER="both-addresses"
    echo; pause
  fi
  return 0
}

step_lan(){
  screen 5
  local lopts=() x k defnet lpick
  q menu ROLE "¿Qué papel hace este MikroTik?" 1 \
    "router|Balanceador y router de la LAN  (todo en uno)|Él hace NAT, firewall y DNS, y los equipos de la LAN cuelgan de él. Lo normal en oficina o casa." \
    "balancer|Solo balanceador, delante de otro router|Este reparte las líneas; el de abajo lleva las colas, el PPPoE y los clientes. Pensado para WISP." || return 10

  if (( DETECTED )); then
    USED_IFS=" "; local j; for ((j=1; j<=NWAN; j++)); do USED_IFS+="${WIFBASE[$j]} ${WFINAL[$j]} "; done
    for x in "${IFLIST[@]}"; do
      [[ $USED_IFS == *" $x "* ]] && continue
      k=$(ifidx "$x")
      [[ ${IFTYPE[k]} == bridge || -n ${IFADDR[k]} ]] && lopts+=("$x|$x|$(ifdesc "$x")")
    done
    lopts+=("__other|Escribir el nombre a mano|")
  fi

  if [[ $ROLE == balancer ]]; then
    box "$CA" "Cómo queda el montaje" \
      "   Internet ─ (las líneas) ─▶ ESTE MikroTik ─▶ router de abajo ─▶ clientes" \
      "" \
      "Este equipo: reparte las líneas y hace el único NAT del camino." \
      "El de abajo: colas simples, PPPoE y clientes. Tiene que ir en RUTEO PURO." \
      "" \
      "Al final te genero un segundo archivo con lo que hay que aplicarle a ese router."
    echo
    if (( DETECTED )); then
      q menu lpick "¿Por qué puerto se conecta el router de abajo?" 1 "${lopts[@]}" || return 10
      if [[ $lpick == __other ]]; then
        q input LANIFS "Interfaz del enlace hacia el router de abajo" "${LANIFS:-ether5}" is_any || return 10
      else LANIFS=$lpick; fi
      k=$(ifidx "$LANIFS"); defnet=${IFADDR[k]}
    else
      q input LANIFS "Interfaz del enlace hacia el router de abajo" "${LANIFS:-ether5}" is_any || return 10
      defnet=""
    fi
    # IP del enlace: la que ya tenga el puerto, o una por defecto
    if [[ -n $defnet ]]; then
      BALIP=${defnet%%/*}
      LINKNET=$(awk -F'[./]' '{printf "%s.%s.%s.0/%s", $1,$2,$3,$5}' <<< "$defnet")
      DOWNGW=$(awk -F. '{printf "%s.%s.%s.2", $1,$2,$3}' <<< "$BALIP")
    else
      BALIP="192.168.88.1"; LINKNET="192.168.88.0/24"; DOWNGW="192.168.88.2"
    fi

    q menu LINKMODE "¿Cómo configuro el enlace con ese router?" 1 \
      "auto|Automático  ★ recomendado|Yo pongo las IP del enlace, el DHCP que le da la IP al router de abajo, la ruta de vuelta hacia los clientes y su archivo listo para importar. No tienes que escribir nada más." \
      "manual|Lo configuro yo|Si ya tienes IP fijas y quieres enrutar solo tus subredes exactas" || return 10

    if [[ $LINKMODE == auto ]]; then
      # Rangos privados completos: cubre cualquier pool de clientes, hoy y mañana
      CLIENTNETS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
      LANNETS="$CLIENTNETS"
      LINKHASADDR=0; LINKHASDHCP=0
      (( DETECTED )) && run "Mirando cómo está ese puerto…" probe_link "$LANIFS"
      if [[ ${LINKHASDHCP:-0} -gt 0 ]]; then
        LINKDHCP="no"
        hint "Ese puerto ya tiene un servidor DHCP propio, así que no le monto otro: al router de abajo le pongo la IP fija $DOWNGW en su archivo."
      else
        LINKDHCP="si"
      fi
      box "$CO" "El enlace queda así (no hay que tocar nada)" \
        "Puerto:            $LANIFS" \
        "Este MikroTik:     $BALIP$([[ ${LINKHASADDR:-0} -gt 0 ]] && echo "  (la que ya tenía)")" \
        "Router de abajo:   $DOWNGW  ($([[ $LINKDHCP == si ]] && echo "se la doy por DHCP" || echo "IP fija en su archivo"))" \
        "Vuelta a clientes: todo lo privado (10.x, 172.16-31.x, 192.168.x) va hacia abajo" \
        "" \
        "Si tus clientes usan IP públicas, elige «Lo configuro yo» y dime las subredes."
      q input UPIF "¿Por qué puerto conecta el router de abajo hacia aquí?" "${UPIF:-ether1}" is_any "Escribe el nombre." "Es el puerto DEL OTRO router. Si no estás seguro deja ether1 y lo cambias en el archivo." || return 10
    else
      q input BALIP "IP de ESTE MikroTik en ese enlace" "${BALIP}" is_ip "Escribe una IP válida." "Es la que el router de abajo usará como gateway" || return 10
      q input DOWNGW "IP del router de abajo en ese enlace" "${DOWNGW}" is_ip "Escribe una IP válida." "Por ahí entran las subredes de clientes" || return 10
      q input CLIENTNETS "Subredes de clientes que hay detrás (separadas por coma)" "${CLIENTNETS:-10.50.0.0/22}" is_any "Formato: 10.50.0.0/22" "Incluye los pools de PPPoE si los usas" || return 10
      LANNETS="$LINKNET,$CLIENTNETS"
      q input UPIF "¿Por qué puerto conecta el router de abajo hacia aquí?" "${UPIF:-ether1}" is_any || return 10
    fi
    DNSREMOTE="n"
    warn "El router de abajo NO debe hacer NAT: si enmascara, el balanceo por equipo deja de funcionar. Su archivo ya se lo quita."
  else
    # --- Modo todo en uno: la LAN la arma LBW o se usa una que ya existe ---
    local nexist=0 defm=1
    (( DETECTED )) && nexist=$(( ${#lopts[@]} - 1 ))
    # Sin LAN con IP o sin servidor DHCP (CHR, reset sin config): crear es lo normal
    if (( DETECTED )) && (( nexist == 0 || AUDIT_DHCPSRV == 0 )); then defm=1
    elif (( DETECTED )); then defm=2
    else defm=2; fi
    q menu LANMODE "¿Cómo queda la red local (LAN)?" "$defm" \
      "create|Crear la LAN: bridge, IP y servidor DHCP|Para CHR, routers sin configuración o si quieres una LAN nueva. Todo lo creado lleva la marca LBW:lan y el desinstalador lo quita." \
      "existing|Usar una LAN que ya existe|Router de fábrica (bridge 192.168.88.1 con su DHCP) o una LAN que ya armaste tú." || return 10

    if [[ $LANMODE == create ]]; then
      LANCREATE="s"
      local mg free=""
      mg=$(mgmt_if)
      if (( DETECTED )); then
        for x in "${IFLIST[@]}"; do
          k=$(ifidx "$x")
          [[ ${IFTYPE[k]} == ether ]] || continue
          [[ $USED_IFS == *" $x "* || $USED_IFS == *" ${x%_ISP[0-9]} "* ]] && continue
          [[ -n ${IFADDR[k]} || $x == "$mg" ]] && continue
          free+="${free:+,}$x"
        done
      fi
      [[ -z $free ]] && free="ether3"
      while true; do
        q input LANPORTS "Puertos que forman la LAN (separados por coma)" "${LANPORTS:-$free}" is_any "Escribe al menos un puerto." "Se meten en un bridge nuevo llamado bridge-lan. Si alguno estaba en otro bridge, se mueve y el desinstalador lo devuelve." || return 10
        LANPORTS=$(tr -d ' ' <<< "$LANPORTS")
        if [[ -n $mg && ",$LANPORTS," == *",$mg,"* ]]; then
          box "$CE" "Ojo: por $mg entras tú ahora mismo" \
            "Ese puerto tiene la IP $RHOST. Al meterlo en bridge-lan esa IP deja de funcionar" \
            "y perderás esta conexión a mitad del import (la red de seguridad revertirá todo)." \
            "Lo normal es dejar fuera el puerto de gestión."
          local gok; q confirm gok "¿Lo meto de todos modos?" n || return 10
          [[ $gok != s ]] && { LANPORTS=$free; continue; }
        fi
        break
      done
      local defgw="192.168.88.1/24" used_nets=" " cand
      for k in "${!IFADDR[@]}"; do [[ -n ${IFADDR[k]} ]] && used_nets+="$(cidr_net "${IFADDR[k]}") "; done
      for cand in 192.168.88.1/24 192.168.50.1/24 10.10.10.1/24 172.20.0.1/24; do
        [[ $used_nets != *" $(cidr_net "$cand") "* ]] && { defgw=$cand; break; }
      done
      while true; do
        q input LANGW "IP del router en la LAN (con máscara)" "${LANGW:-$defgw}" is_cidr "Formato: 192.168.88.1/24" "Será el gateway y el DNS de los equipos de la LAN" || return 10
        if [[ $used_nets == *" $(cidr_net "$LANGW") "* ]]; then
          err "La red $(cidr_net "$LANGW") ya está en uso en otra interfaz del router. Elige otra."
          continue
        fi
        (( ${LANGW##*/} < 16 || ${LANGW##*/} > 29 )) && { err "Usa una máscara entre /16 y /29."; continue; }
        break
      done
      LANNETS=$(cidr_net "$LANGW")
      q input LANPOOL "Rango que reparte el DHCP" "${LANPOOL:-$(cidr_pool "$LANGW")}" is_range "Formato: 192.168.88.10-192.168.88.254" || return 10
      LANIFS="bridge-lan"
    else
      LANCREATE="n"
      if (( DETECTED )); then
        q menu lpick "¿Cuál es tu red local (LAN)?" 1 "${lopts[@]}" || return 10
        if [[ $lpick == __other ]]; then
          q input LANIFS "Interfaz o interfaces de la LAN (separadas por coma)" "${LANIFS:-bridge}" is_any || return 10
        else LANIFS=$lpick; fi
        k=$(ifidx "$LANIFS"); defnet=${IFADDR[k]:-192.168.88.1/24}
        defnet=$(cidr_net "$defnet")
      else
        q input LANIFS "Interfaz o interfaces de la LAN (separadas por coma)" "${LANIFS:-bridge}" is_any || return 10
        defnet="192.168.88.0/24"
      fi
      q input LANNETS "Subred o subredes de la LAN (separadas por coma)" "${LANNETS:-$defnet}" is_any "Formato: 192.168.88.0/24" "Si tienes VLANs internas, ponlas todas: 192.168.10.0/24,192.168.20.0/24" || return 10
    fi
  fi

  while true; do
    q input DNS "Servidores DNS para el router" "${DNS:-1.1.1.1,8.8.8.8}" is_any || return 10
    local clash="" _d i
    IFS=',' read -ra _d <<< "$DNS"
    for x in "${_d[@]}"; do
      for ((i=1; i<=NWAN; i++)); do [[ $x == "${WP1[$i]}" || $x == "${WP2[$i]}" ]] && clash+="$x "; done
    done
    [[ -z $clash ]] && break
    err "No uses un probe como DNS ($clash): si ese proveedor cae te quedas sin DNS."
  done
  if [[ $ROLE == router ]]; then
    q confirm DNSREMOTE "¿Los equipos de la LAN usan el router como DNS?" s || return 10
  fi
  return 0
}

step_extras(){
  screen 6
  local i
  HAS_PPPOE=n; for ((i=1; i<=NWAN; i++)); do [[ ${WTYPE[$i]} == pppoe ]] && HAS_PPPOE=y; done
  if [[ $HAS_PPPOE == y ]]; then MSSCLAMP=s
  else q confirm MSSCLAMP "¿Ajustar el MSS de TCP (clamp)?" s || return 10; fi
  q confirm PROTECTWAN "¿Bloquear el acceso al router desde Internet?" s || return 10
  hint "Agrega reglas de firewall que descartan lo que llega por las WAN y no es respuesta a algo que tú pediste."
  q confirm TGENABLE "¿Quieres avisos por Telegram cuando una línea caiga?" n || return 10
  if [[ $TGENABLE == s ]]; then
    q input TGTOKEN "Token del bot" "$TGTOKEN" is_any "No puede ir vacío." "Lo obtienes de @BotFather" || return 10
    q input TGCHAT "Chat ID" "$TGCHAT" is_any "No puede ir vacío." "Lo obtienes de @userinfobot" || return 10
  fi
  q input ROLLBACK_MIN "Minutos de la red de seguridad antes de revertir sola" "${ROLLBACK_MIN:-10}" is_num "Escribe un número de minutos." "Si no confirmas en ese tiempo, el router deshace todo solo. Ponle más minutos si vas a probar con calma." || return 10
  return 0
}

step_summary(){
  local i td modetxt tl GO
  while true; do
    screen 7
    draw_topology; echo
    [[ $MODE == lb ]] && { draw_bars; echo; }
    tl=()
    for ((i=1; i<=NWAN; i++)); do
      case ${WTYPE[$i]} in
        dhcp) td="DHCP";; static) td="IP fija ${WADDR[$i]}";; pppoe) td="PPPoE (${WUSER[$i]})";; ptp) td="gateway por interfaz";;
      esac
      (( ${WVLAN[$i]:-0} > 0 )) && td+=" · VLAN ${WVLAN[$i]}"
      tl+=("$(pad "${WNAME[$i]}" 12)$(pad "${WIF[$i]} → ${WFINAL[$i]}" 30)$td")
    done
    modetxt=$([[ $MODE == lb ]] && echo "Balanceo + respaldo · reparto por $CLASSIFIER" || echo "Solo respaldo, por orden de prioridad")
    box "$CA" "Tu configuración" "Modo: $modetxt" \
      "Papel: $([[ $ROLE == router ]] && echo "balanceador y router de la LAN" || echo "solo balanceador, delante de otro router")" "" "${tl[@]}" "" \
      "$([[ $ROLE == router ]] && { [[ $LANCREATE == s ]] && echo "LAN nueva: bridge-lan ($LANPORTS) · $LANGW · DHCP $LANPOOL" || echo "LAN: $LANIFS → $LANNETS"; } || echo "Enlace: $LANIFS · este $BALIP · abajo $DOWNGW · clientes $CLIENTNETS")" \
      "DNS: $DNS" \
      "Red de seguridad: $ROLLBACK_MIN minutos"
    [[ $MODE == lb ]] && warn "Se desactiva FastTrack (incompatible con el balanceo): sube el uso de CPU."
    [[ $PROTECTWAN == s ]] && hint "Firewall: arriba se ponen las reglas que aceptan (established, LAN) y abajo las que descartan desde la WAN, para no tapar tus reglas de VPN o port forwards."
    if [[ $ROLE == balancer ]]; then
      warn "El router de abajo debe quedar en ruteo puro: sin NAT y sin FastTrack. Te genero su archivo aparte."
      hint "Las colas simples de ese router no se tocan: clasifican por IP de cliente, no por marcas de ruteo. Sí revisa los queue tree con packet-marks en prerouting."
    fi
    echo
    q menu GO "¿Todo correcto?" 1 \
      "gen|Generar la configuración|Crea el .rsc y el desinstalador" \
      "back|Volver y corregir algo|Te lleva al paso anterior" \
      "quit|Salir sin generar|" || return 10
    case $GO in
      gen) return 0;;
      back) return 10;;
      quit) info "Cancelado."; exit 0;;
    esac
  done
}

banner
pause
STEP=1
while (( STEP <= 7 )); do
  case $STEP in
    1) step_router;; 2) step_mode;; 3) step_wans;; 4) step_split;;
    5) step_lan;;    6) step_extras;; 7) step_summary;;
  esac
  rc=$?
  if (( rc == 10 )); then (( STEP > 1 )) && ((STEP--)); continue; fi
  (( rc != 0 )) && exit $rc
  ((STEP++))
done

# ======================= Generador del .rsc ==========================
urlenc(){ local s=$1; s=${s//%/%25}; s=${s// /%20}; s=${s//:/%3A}; s=${s//&/%26}; printf '%s' "$s"; }

# El monitor se escribe como bloque {...} (igual que el ejemplo oficial de
# /system script add source={...}), sin escapar comillas a mano.
# - 60 s de gracia tras el arranque: las rutas aun no estan activas y daria
#   falsas CAIDAS (y alertas por Telegram) en cada reinicio.
# - Primera pasada: solo registra el estado, no borra conexiones ni avisa.
# - Mantiene en LBW-local las redes conectadas de cada WAN (DHCP, PPPoE o
#   fija), para que el PCC no mande por otra linea el trafico al modem del ISP.
build_monitor(){
  local i tgu tgd
  echo ':if ([/system resource get uptime] >= 60s) do={'
  for ((i=1; i<=NWAN; i++)); do
    cat << MON
  :foreach a in=[/ip address find where interface="${WFINAL[$i]}" && !disabled] do={
    :local ad [/ip address get \$a address]
    :local pf [:pick \$ad ([:find \$ad "/"] + 1) [:len \$ad]]
    :local nw [:tostr [/ip address get \$a network]]
    :if (\$pf != "32") do={ :set nw (\$nw . "/" . \$pf) }
    :if ([:len [/ip firewall address-list find where list="LBW-local" && address=\$nw]] = 0) do={
      :do { /ip firewall address-list add list=LBW-local address=\$nw comment="LBW:local:wan$i" } on-error={}
    }
  }
MON
  done
  for ((i=1; i<=NWAN; i++)); do
    tgu=""; tgd=""
    if [[ $TGENABLE == s ]]; then
      tgu=":do { /tool fetch keep-result=no url=\"https://api.telegram.org/bot$TGTOKEN/sendMessage\\?chat_id=$TGCHAT&text=$(urlenc "LBW: ${WNAME[$i]} EN LINEA")\" } on-error={}"
      tgd=":do { /tool fetch keep-result=no url=\"https://api.telegram.org/bot$TGTOKEN/sendMessage\\?chat_id=$TGCHAT&text=$(urlenc "LBW: ${WNAME[$i]} CAIDA")\" } on-error={}"
    fi
    cat << MON
  :global LBWs$i
  :local u$i ([:len [/ip route find where comment="LBW:WAN$i:OWN" && active]] > 0)
  :if ([:typeof \$LBWs$i] = "nothing") do={
    :set LBWs$i \$u$i
    :if (\$u$i) do={ :log info "LBW: ${WNAME[$i]} (WAN$i) en linea al iniciar el monitor" } else={ :log warning "LBW: ${WNAME[$i]} (WAN$i) sin salida al iniciar el monitor" }
  } else={
    :if (\$u$i != \$LBWs$i) do={
      :set LBWs$i \$u$i
      :if (\$u$i) do={
        :log warning "LBW: ${WNAME[$i]} (WAN$i) EN LINEA"
        $tgu
      } else={
        :log error "LBW: ${WNAME[$i]} (WAN$i) CAIDA"
        /ip firewall connection remove [find where connection-mark="ISP${i}_conn"]
        $tgd
      }
    }
  }
MON
  done
  echo '}'
}

# Reglas del firewall: las que ACEPTAN y descartan invalidos van ARRIBA de
# todo (antes de un "drop all" que ya hubiera); los DROP desde la WAN van al
# FINAL, para no tapar reglas que el usuario ya tenga (VPN, port forwards).
fw_top(){ echo "  :if (\$hasA) do={ /ip firewall filter add $1 place-before=\$anchor } else={ /ip firewall filter add $1 }"; }
gen_firewall(){
  [[ $PROTECTWAN != s && $DNSREMOTE != s ]] && return 0
  echo
  echo "# --- 8. Firewall basico (equivalente al defconf de MikroTik) ---------"
  if [[ $PROTECTWAN == s ]]; then
    echo ':do {'
    echo '  :local hasA false'
    echo '  :local anchor'
    echo '  :local cand [/ip firewall filter find where !dynamic && !(comment~"^LBW")]'
    echo '  :if ([:len $cand] > 0) do={ :set anchor [:pick $cand 0]; :set hasA true }'
    fw_top 'chain=input action=accept connection-state=established,related,untracked comment="LBW:FW:in-est"'
    fw_top 'chain=input action=drop connection-state=invalid comment="LBW:FW:in-invalid"'
    fw_top 'chain=input action=accept protocol=icmp limit=10,20:packet comment="LBW:FW:icmp"'
    fw_top 'chain=input action=accept in-interface-list=LBW-LAN comment="LBW:FW:lan"'
    fw_top 'chain=forward action=accept connection-state=established,related,untracked comment="LBW:FW:fwd-est"'
    fw_top 'chain=forward action=drop connection-state=invalid comment="LBW:FW:fwd-invalid"'
    echo '} on-error={ :log error "LBW fallo: firewall (reglas de arriba)" }'
    W '/ip firewall filter add chain=input action=drop in-interface-list=LBW-WAN comment="LBW:FW:drop-wan"' "fw drop wan"
    W '/ip firewall filter add chain=forward action=drop connection-state=new connection-nat-state=!dstnat in-interface-list=LBW-WAN comment="LBW:FW:fwd-wan"' "fw forward wan"
  else
    echo "# Sin proteccion general, pero el DNS del router no se deja abierto a Internet"
    W '/ip firewall filter add chain=input action=drop protocol=udp dst-port=53 in-interface-list=LBW-WAN comment="LBW:FW:dns-wan-udp"' "fw dns udp"
    W '/ip firewall filter add chain=input action=drop protocol=tcp dst-port=53 in-interface-list=LBW-WAN comment="LBW:FW:dns-wan-tcp"' "fw dns tcp"
  fi
}

# W: envuelve un comando para que un fallo NO aborte el import completo
W(){ printf ':do { %s } on-error={ :log error "LBW fallo: %s" }\n' "$1" "${2:-paso}"; }

gen_rsc(){
  local i j k d b
  cat << RSC
# =====================================================================
# LBW Multi-WAN - generado por lbw-wizard.sh v$VERSION el $(date '+%Y-%m-%d %H:%M')
# LBW Wizard (c) 2026 $AUTHOR_ASCII - GPL-3.0-or-later
# $REPO_URL
#
# Aplicar:    /import file-name=$OUTNAME verbose=yes
# Revertir:   /import file-name=lbw-remove.rsc
# Modo: $MODE | WANs: $NWAN | reparto: $CLASSIFIER
# =====================================================================
:log warning "LBW: aplicando configuracion multi-WAN"

# --- 0. Limpieza de una instalacion LBW previa -----------------------
:do { /system scheduler remove [find where comment~"^LBW"] } on-error={}
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
    :local c [/ip firewall filter get \$r comment]
    /ip firewall filter set \$r disabled=yes comment=("PRE-LBW:" . \$c)
  }
} on-error={ :log error "LBW fallo: fasttrack" }
# Las rutas por defecto y el NAT viejos se apartan AL FINAL (seccion 10),
# para que el router nunca se quede sin salida si algo falla a mitad.

# --- 2. Interfaces: renombrado con sufijo _ISPx y listas -------------
:if ([:len [/interface list find where name="LBW-WAN"]] = 0) do={ /interface list add name=LBW-WAN comment="LBW" }
:if ([:len [/interface list find where name="LBW-LAN"]] = 0) do={ /interface list add name=LBW-LAN comment="LBW" }
/interface list member remove [find where comment~"^LBW"]
RSC

  for ((i=1; i<=NWAN; i++)); do
    local base=${WIF[$i]} fin=${WFINAL[$i]}
    echo
    echo "# --- WAN$i: ${WNAME[$i]} ($base -> $fin)"
    cat << RSC
:do {
  :foreach b in=[/interface bridge port find where interface="$base"] do={
    :local br [/interface bridge port get \$b bridge]
    :do { /ip firewall address-list add list=LBW-restore address=127.0.0.$i comment=("LBW:restore:br=" . \$br . ":if=$base") } on-error={}
    /interface bridge port remove \$b
    :log warning ("LBW: $base sacado del bridge " . \$br . " para usarlo como WAN$i")
  }
} on-error={ :log error "LBW fallo: sacar $base del bridge" }
RSC
    local parent=$base
    if (( ${WVLAN[$i]:-0} > 0 )); then
      parent="vlan${WVLAN[$i]}_ISP$i"
      cat << RSC
:if ([:len [/interface vlan find where name="$parent"]] = 0) do={
  /interface vlan add name="$parent" vlan-id=${WVLAN[$i]} interface="$base" comment="LBW:WAN$i:vlan"
} else={ /interface vlan set [find where name="$parent"] vlan-id=${WVLAN[$i]} interface="$base" comment="LBW:WAN$i:vlan" }
RSC
    fi
    if [[ ${WTYPE[$i]} == pppoe ]]; then
      cat << RSC
:if ([:len [/interface pppoe-client find where name="$fin"]] = 0) do={
  /interface pppoe-client add name="$fin" interface="$parent" user="${WUSER[$i]}" password="${WPASS[$i]}" \\
    add-default-route=no use-peer-dns=no disabled=no comment="LBW:WAN$i:pppoe"
} else={ /interface pppoe-client set [find where name="$fin"] interface="$parent" user="${WUSER[$i]}" password="${WPASS[$i]}" add-default-route=no use-peer-dns=no disabled=no comment="LBW:WAN$i:pppoe" }
RSC
    elif (( ${WVLAN[$i]:-0} == 0 )); then
      cat << RSC
:do {
  :if ([:len [/interface find where name="$fin"]] = 0) do={
    :if ([:len [/interface find where name="$base"]] > 0) do={
      /interface set [find where name="$base"] name="$fin" comment="LBW:WAN$i:was=$base"
    }
  } else={ /interface set [find where name="$fin"] comment="LBW:WAN$i:was=$base" }
} on-error={ :log error "LBW fallo: renombrar $base" }
RSC
    fi
    cat << RSC
:if ([:len [/interface list find where name="LBW-WAN$i"]] = 0) do={ /interface list add name=LBW-WAN$i comment="LBW:WAN$i" }
# Si existe la lista WAN de la config de fabrica, metemos ahi tambien esta linea
:if ([:len [/interface list find where name="WAN"]] > 0) do={
  :do { /interface list member add list=WAN interface="$fin" comment="LBW:compat:WAN$i" } on-error={}
}
:do { /interface list member add list=LBW-WAN$i interface="$fin" comment="LBW:WAN$i" } on-error={}
:do { /interface list member add list=LBW-WAN interface="$fin" comment="LBW:WAN$i" } on-error={}
RSC
    case ${WTYPE[$i]} in
      static)
        cat << RSC
:if ([:len [/ip address find where address="${WADDR[$i]}" && interface="$fin"]] = 0) do={
  /ip address add address=${WADDR[$i]} interface="$fin" comment="LBW:WAN$i"
}
RSC
        ;;
      dhcp)
        cat << RSC
:do {
  /ip dhcp-client add interface="$fin" add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:NEW:WAN$i" script=":if (\\\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN$i:PROBE\"] gateway=\\\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN$i:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP${i}_conn\"]"
} on-error={
  :log warning "LBW: ya habia un DHCP client para WAN$i; lo reutilizo"
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get \$c interface]
    :if ([:tostr \$ifn] = "$fin") do={ /ip dhcp-client set \$c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN$i:adr=yes,dns=yes,ntp=yes" script=":if (\\\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN$i:PROBE\"] gateway=\\\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN$i:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP${i}_conn\"]" }
    :if ([:tostr \$ifn] = "$base") do={ /ip dhcp-client set \$c add-default-route=no use-peer-dns=no use-peer-ntp=no comment="LBW:WAN$i:adr=yes,dns=yes,ntp=yes" script=":if (\\\$bound=1) do={/ip/route/set [/ip/route/find where comment=\"LBW:WAN$i:PROBE\"] gateway=\\\$\"gateway-address\" disabled=no} else={/ip/route/set [/ip/route/find where comment=\"LBW:WAN$i:PROBE\"] disabled=yes}; /ip/firewall/connection/remove [/ip/firewall/connection/find where connection-mark=\"ISP${i}_conn\"]" }
  }
}
RSC
        ;;
    esac
  done

  cat << RSC

# --- 3. Red local ----------------------------------------------------
RSC
  if [[ $ROLE == router && $LANCREATE == s ]]; then
    local lgw=${LANGW%%/*} ldns n=0 p
    [[ $DNSREMOTE == s ]] && ldns=$lgw || ldns=$DNS
    echo "# LAN nueva: bridge-lan con $LANPORTS · $LANGW · DHCP $LANPOOL"
    echo ":if ([:len [/interface bridge find where name=\"bridge-lan\"]] = 0) do={"
    W "  /interface bridge add name=bridge-lan comment=\"LBW:lan\"" "crear bridge-lan"
    echo "}"
    IFS=',' read -ra _lp <<< "$LANPORTS"
    for p in "${_lp[@]}"; do
      ((n++))
      cat << RSC
:do {
  :foreach b in=[/interface bridge port find where interface="$p"] do={
    :local br [:tostr [/interface bridge port get \$b bridge]]
    :if (\$br != "bridge-lan") do={
      :do { /ip firewall address-list add list=LBW-restore address=127.0.1.$n comment=("LBW:restore:br=" . \$br . ":if=$p") } on-error={}
      /interface bridge port remove \$b
      :log warning ("LBW: $p sacado del bridge " . \$br . " para la LAN nueva")
    }
  }
  :if ([:len [/interface bridge port find where interface="$p"]] = 0) do={
    /interface bridge port add bridge=bridge-lan interface="$p" comment="LBW:lan"
  }
} on-error={ :log error "LBW fallo: $p a bridge-lan" }
RSC
    done
    echo ":if ([:len [/ip address find where address=\"$LANGW\"]] = 0) do={"
    W "  /ip address add address=$LANGW interface=bridge-lan comment=\"LBW:lan\"" "IP de la LAN"
    echo "}"
    echo ":if ([:len [/ip pool find where name=\"LBW-lan\"]] = 0) do={"
    W "  /ip pool add name=LBW-lan ranges=$LANPOOL comment=\"LBW:lan\"" "pool de la LAN"
    echo "} else={ /ip pool set [find where name=\"LBW-lan\"] ranges=$LANPOOL }"
    echo ":if ([:len [/ip dhcp-server network find where address=\"$LANNETS\"]] = 0) do={"
    W "  /ip dhcp-server network add address=$LANNETS gateway=$lgw dns-server=$ldns comment=\"LBW:lan\"" "red DHCP de la LAN"
    echo "}"
    echo ":if ([:len [/ip dhcp-server find where name=\"LBW-lan\"]] = 0) do={"
    W "  /ip dhcp-server add name=LBW-lan interface=bridge-lan address-pool=LBW-lan lease-time=1h disabled=no comment=\"LBW:lan\"" "servidor DHCP de la LAN"
    echo "}"
  fi
  # Si existe la lista LAN del defconf, la LAN de LBW entra ahi tambien: si no,
  # la regla de fabrica "drop all not coming from LAN" bloquearia a sus equipos.
  IFS=',' read -ra _lifs <<< "$LANIFS"
  for x in "${_lifs[@]}"; do
    x=$(tr -d ' ' <<< "$x")
    echo ":if ([:len [/interface list find where name=\"LAN\"]] > 0) do={ :do { /interface list member add list=LAN interface=\"$x\" comment=\"LBW:compat:LAN\" } on-error={} }"
  done
  IFS=',' read -ra _lifs <<< "$LANIFS"
  for x in "${_lifs[@]}"; do
    x=$(tr -d ' ' <<< "$x")
    echo ":do { /interface list member add list=LBW-LAN interface=\"$x\" comment=\"LBW:LAN\" } on-error={}"
  done
  IFS=',' read -ra _lnets <<< "$LANNETS"
  for x in "${_lnets[@]}"; do
    x=$(tr -d ' ' <<< "$x")
    W "/ip firewall address-list add list=LBW-local address=$x comment=\"LBW:local\"" "address-list $x"
  done
  if [[ $ROLE == balancer ]]; then
    if [[ $LINKMODE == auto ]]; then
      echo "# Enlace con el router de abajo"
      echo ":if ([:len [/ip address find where interface=\"$LANIFS\"]] = 0) do={"
      W "  /ip address add address=$BALIP/${LINKNET##*/} interface=\"$LANIFS\" comment=\"LBW:link\"" "IP del enlace"
      echo "} else={ :log info \"LBW: $LANIFS ya tenia IP, la respeto\" }"
      if [[ $LINKDHCP == si ]]; then
        echo ":if ([:len [/ip dhcp-server find where interface=\"$LANIFS\"]] = 0) do={"
        W "  /ip pool add name=LBW-link ranges=$DOWNGW-$DOWNGW comment=\"LBW:link\"" "pool del enlace"
        W "  /ip dhcp-server add name=LBW-link interface=\"$LANIFS\" address-pool=LBW-link disabled=no comment=\"LBW:link\"" "dhcp del enlace"
        W "  /ip dhcp-server network add address=$LINKNET gateway=$BALIP dns-server=$DNS comment=\"LBW:link\"" "red del enlace"
        echo "} else={ :log warning \"LBW: $LANIFS ya tenia servidor DHCP; dale IP fija $DOWNGW al router de abajo\" }"
      else
        echo "# Ese puerto ya tenia servidor DHCP: el router de abajo lleva IP fija $DOWNGW en su archivo."
      fi
    fi
    echo "# Subredes de clientes que viven detras del router de abajo"
    IFS=',' read -ra _cnets <<< "$CLIENTNETS"
    for x in "${_cnets[@]}"; do
      x=$(tr -d ' ' <<< "$x")
      W "/ip route add dst-address=$x gateway=$DOWNGW comment=\"LBW:downstream\"" "ruta a $x"
    done
  fi
  cat << RSC
RSC
  W "/ip firewall address-list add list=LBW-local address=224.0.0.0/4 comment=\"LBW:local\"" "address-list multicast"
  cat << RSC
:do { /ip dns set servers=$DNS allow-remote-requests=$([[ $DNSREMOTE == s ]] && echo yes || echo no) } on-error={ :log error "LBW fallo: DNS" }

# --- 4. Tablas de ruteo ----------------------------------------------
RSC
  for ((i=1; i<=NWAN; i++)); do
    W "/routing table add fib name=to_WAN$i comment=\"LBW:WAN$i:table\"" "tabla to_WAN$i"
  done

  cat << RSC

# --- 5. Rutas: probes por interfaz y rutas recursivas ----------------
RSC
  for ((i=1; i<=NWAN; i++)); do
    local gw dis=""
    case ${WTYPE[$i]} in
      static) gw=${WGW[$i]};;
      dhcp)   gw=${WIF[$i]}; dis=" disabled=yes";;   # el script del DHCP pone el gateway real
      *)      gw=${WFINAL[$i]};;
    esac
    [[ ${WTYPE[$i]} == dhcp ]] && gw=${WFINAL[$i]}
    W "/ip route add dst-address=${WP1[$i]}/32 gateway=$gw scope=10 target-scope=10 comment=\"LBW:WAN$i:PROBE\"$dis" "probe1 WAN$i"
    W "/ip route add dst-address=${WP2[$i]}/32 gateway=$gw scope=10 target-scope=10 comment=\"LBW:WAN$i:PROBE\"$dis" "probe2 WAN$i"
  done
  echo
  echo "# Tabla main (trafico del propio router)"
  for ((i=1; i<=NWAN; i++)); do
    d=$(( (i-1)*10 + 1 ))
    W "/ip route add dst-address=0.0.0.0/0 gateway=${WP1[$i]} check-gateway=ping distance=$d scope=10 target-scope=11 comment=\"LBW:WAN$i:MAIN\"" "default main WAN$i"
    W "/ip route add dst-address=0.0.0.0/0 gateway=${WP2[$i]} check-gateway=ping distance=$((d+1)) scope=10 target-scope=11 comment=\"LBW:WAN$i:MAIN\"" "default main WAN$i b"
  done
  if true; then
    for ((i=1; i<=NWAN; i++)); do
      echo
      echo "# Tabla to_WAN$i: primero ${WNAME[$i]}, luego las demas por orden"
      W "/ip route add dst-address=0.0.0.0/0 gateway=${WP1[$i]} check-gateway=ping distance=1 scope=10 target-scope=11 routing-table=to_WAN$i comment=\"LBW:WAN$i:OWN\"" "ruta propia WAN$i"
      W "/ip route add dst-address=0.0.0.0/0 gateway=${WP2[$i]} check-gateway=ping distance=2 scope=10 target-scope=11 routing-table=to_WAN$i comment=\"LBW:WAN$i:OWN\"" "ruta propia WAN$i b"
      k=1
      for ((j=1; j<=NWAN; j++)); do
        (( j == i )) && continue
        d=$(( k*10 + 1 ))
        W "/ip route add dst-address=0.0.0.0/0 gateway=${WP1[$j]} check-gateway=ping distance=$d scope=10 target-scope=11 routing-table=to_WAN$i comment=\"LBW:WAN$i:BK$j\"" "respaldo $j de WAN$i"
        W "/ip route add dst-address=0.0.0.0/0 gateway=${WP2[$j]} check-gateway=ping distance=$((d+1)) scope=10 target-scope=11 routing-table=to_WAN$i comment=\"LBW:WAN$i:BK$j\"" "respaldo $j de WAN$i b"
        ((k++))
      done
    done
  fi

  cat << RSC

# --- 6. Marcado de trafico -------------------------------------------
:do { /ip firewall mangle add chain=prerouting action=accept in-interface-list=LBW-LAN dst-address-list=LBW-local comment="LBW:local:skip" } on-error={ :log error "LBW fallo: skip local" }
RSC
  for ((i=1; i<=NWAN; i++)); do
    W "/ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-WAN$i connection-mark=no-mark new-connection-mark=ISP${i}_conn passthrough=yes comment=\"LBW:WAN$i:FWD\"" "mangle fwd WAN$i"
  done
  if [[ $MODE == lb ]]; then
    calc_weights
    b=0
    echo "# PCC: $TOTBUCKETS partes repartidas segun la velocidad de cada linea"
    for ((i=1; i<=NWAN; i++)); do
      for ((k=0; k<${WEIGHT[$i]}; k++)); do
        W "/ip firewall mangle add chain=prerouting action=mark-connection in-interface-list=LBW-LAN dst-address-list=!LBW-local dst-address-type=!local connection-mark=no-mark new-connection-mark=ISP${i}_conn passthrough=yes per-connection-classifier=$CLASSIFIER:$TOTBUCKETS/$b comment=\"LBW:PCC:WAN$i:$b\"" "PCC $b"
        ((b++))
      done
    done
    for ((i=1; i<=NWAN; i++)); do
      W "/ip firewall mangle add chain=prerouting action=mark-routing in-interface-list=LBW-LAN connection-mark=ISP${i}_conn new-routing-mark=to_WAN$i passthrough=no comment=\"LBW:WAN$i:RT\"" "mark-routing WAN$i"
    done
  fi
  for ((i=1; i<=NWAN; i++)); do
    W "/ip firewall mangle add chain=output action=mark-routing connection-mark=ISP${i}_conn dst-address-list=!LBW-local new-routing-mark=to_WAN$i passthrough=no comment=\"LBW:WAN$i:OUT\"" "mangle output WAN$i"
  done
  [[ $MSSCLAMP == s ]] && W "/ip firewall mangle add chain=forward action=change-mss new-mss=clamp-to-pmtu tcp-flags=syn protocol=tcp out-interface-list=LBW-WAN comment=\"LBW:MSS\"" "MSS clamp"

  cat << RSC

# --- 7. NAT (se agrega ANTES de apartar el viejo) --------------------
:do { /ip firewall nat add chain=srcnat action=masquerade out-interface-list=LBW-WAN ipsec-policy=out,none comment="LBW:NAT" } on-error={ :log error "LBW fallo: NAT" }
RSC
  gen_firewall

  local hasdhcp=n
  for ((i=1; i<=NWAN; i++)); do [[ ${WTYPE[$i]} == dhcp ]] && hasdhcp=y; done
  if [[ $hasdhcp == y ]]; then
    echo
    echo "# --- 8b. Arranque: usar el gateway del lease que ya esta activo"
    echo ":delay 8s"
    for ((i=1; i<=NWAN; i++)); do
      [[ ${WTYPE[$i]} == dhcp ]] || continue
      cat << RSC
:do {
  :local gw ""
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [/ip dhcp-client get \$c interface]
    :if ([:tostr \$ifn] = "${WFINAL[$i]}") do={ :set gw [/ip dhcp-client get \$c gateway] }
  }
  :if ([:len \$gw] > 0) do={
    /ip route set [/ip route find where comment="LBW:WAN$i:PROBE"] gateway=\$gw disabled=no
    :log warning ("LBW: WAN$i gateway " . \$gw)
  } else={ :log warning "LBW: WAN$i aun sin lease DHCP; las rutas se activan cuando llegue" }
} on-error={ :log error "LBW fallo: arranque WAN$i" }
RSC
    done
  fi

  cat << RSC

# --- 9. Monitor de lineas --------------------------------------------

:do {
  /system script add name=lbw-monitor comment="LBW: monitor de WANs - LBW Wizard por $AUTHOR_ASCII" source={
$(build_monitor)
  }
} on-error={ :log error "LBW fallo: script monitor" }
:do { /system scheduler add name=lbw-monitor interval=10s comment="LBW: monitor" on-event="/system script run lbw-monitor" } on-error={ :log error "LBW fallo: scheduler monitor" }

# --- 10. Ahora si: apartar lo viejo que estorba ----------------------
:do {
  :foreach r in=[/ip route find where dst-address="0.0.0.0/0" && static && !disabled && !(comment~"^LBW")] do={
    :local c [/ip route get \$r comment]
    /ip route set \$r disabled=yes comment=("PRE-LBW:" . \$c)
  }
} on-error={ :log error "LBW fallo: apartar rutas viejas" }
:do {
  :foreach r in=[/ip firewall nat find where action=masquerade && !disabled && !(comment~"^LBW")] do={
    :local c [/ip firewall nat get \$r comment]
    /ip firewall nat set \$r disabled=yes comment=("PRE-LBW:" . \$c)
  }
} on-error={ :log error "LBW fallo: apartar NAT viejo" }
# DHCP clients que NO son WAN de LBW (p. ej. la gestion de un CHR) pero
# instalan ruta por defecto: quedan de ultimo recurso con distancia 200.
:do {
  :foreach c in=[/ip dhcp-client find where !disabled] do={
    :local ifn [:tostr [/ip dhcp-client get \$c interface]]
    :local adr [:tostr [/ip dhcp-client get \$c add-default-route]]
    :local cm [:tostr [/ip dhcp-client get \$c comment]]
    :if (\$adr != "no" && \$adr != "false" && !(\$cm~"^LBW") && !(\$cm~"^PRE-LBW-DIST:")) do={
      :if ([:len [/interface list member find where list="LBW-WAN" && interface=\$ifn]] = 0) do={
        :local d [:tostr [/ip dhcp-client get \$c default-route-distance]]
        :if ([:len \$d] = 0) do={ :set d "1" }
        /ip dhcp-client set \$c default-route-distance=200 comment=("PRE-LBW-DIST:" . \$d . ":" . \$cm)
        :log warning ("LBW: ruta por defecto del DHCP de " . \$ifn . " pasa a distancia 200 (era " . \$d . ")")
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
  :log warning ("LBW: instalado -> rutas=" . \$nrt . " mangle=" . \$nmg . " nat=" . \$nnt . " tablas=" . \$ntb)
  :put ("LBW-SUMMARY|" . \$nrt . "|" . \$nmg . "|" . \$nnt . "|" . \$ntb)
  :if (\$nnt = 0) do={
    :log error "LBW: no se creo el NAT. Reactivando el NAT anterior para no dejar la red sin salida."
    :foreach r in=[/ip firewall nat find where comment~"^PRE-LBW:"] do={
      :local c [/ip firewall nat get \$r comment]
      /ip firewall nat set \$r disabled=no comment=[:pick \$c 8 [:len \$c]]
    }
  }
} on-error={ :log error "LBW fallo: resumen" }
:put "LBW: listo. Si usaste la red de seguridad, confirma en el asistente o ejecuta:"
:put "  /system scheduler remove [find where comment=\\"ROLLBACK-LBW\\"]"
RSC
}

gen_router2(){
  cat << RSC
# =====================================================================
# Router de ABAJO (colas / PPPoE / clientes) - generado por lbw-wizard.sh v$VERSION
# LBW Wizard (c) 2026 $AUTHOR_ASCII - GPL-3.0-or-later - $REPO_URL
#
# Aplicar EN EL ROUTER DE ABAJO:  /import file-name=lbw-router2.rsc verbose=yes
#
# Este router NO debe hacer NAT: el unico NAT del camino es el del balanceador.
# Si enmascara, todas las conexiones llegan arriba con una sola IP de origen
# y el reparto por equipo deja de funcionar.
# =====================================================================
:log warning "LBW: preparando router de abajo (ruteo puro)"

# 1. Salida por el balanceador
#    El puerto de ESTE router hacia el balanceador es: $UPIF
#    Si no es ese, cambialo en las dos lineas de abajo antes de importar.
:do { /ip route remove [find where dst-address="0.0.0.0/0" && static] } on-error={}
$(if [[ $LINKMODE == auto && $LINKDHCP == si ]]; then cat << AUTO
:do { /ip dhcp-client add interface="$UPIF" add-default-route=yes use-peer-dns=yes comment="LBW:uplink" } on-error={
  :do { /ip dhcp-client set [find where interface="$UPIF"] add-default-route=yes use-peer-dns=yes comment="LBW:uplink" } on-error={ :log error "LBW fallo: dhcp-client uplink" }
}
# El balanceador le entrega $DOWNGW y la ruta por defecto hacia $BALIP.
# Si prefieres IP fija, comenta lo de arriba y usa estas dos lineas:
# /ip address add address=$DOWNGW/${LINKNET##*/} interface="$UPIF" comment="LBW:uplink"
# /ip route add dst-address=0.0.0.0/0 gateway=$BALIP comment="LBW:uplink"
AUTO
else cat << MANU
# Comprueba que $DOWNGW no caiga dentro de un pool DHCP del balanceador.
:do { /ip address add address=$DOWNGW/${LINKNET##*/} interface="$UPIF" comment="LBW:uplink" } on-error={}
:do { /ip route add dst-address=0.0.0.0/0 gateway=$BALIP comment="LBW:uplink al balanceador" } on-error={ :log error "LBW fallo: ruta por defecto" }
MANU
fi)

# 2. Fuera NAT: el balanceador es quien enmascara
:do {
  :foreach r in=[/ip firewall nat find where action=masquerade && !disabled] do={
    :local c [/ip firewall nat get \$r comment]
    /ip firewall nat set \$r disabled=yes comment=("PRE-LBW:" . \$c)
  }
} on-error={ :log error "LBW fallo: apartar NAT" }

# 3. FastTrack fuera: se salta las colas y el conteo de trafico
:do {
  :foreach r in=[/ip firewall filter find where action=fasttrack-connection && !disabled] do={
    :local c [/ip firewall filter get \$r comment]
    /ip firewall filter set \$r disabled=yes comment=("PRE-LBW:" . \$c)
  }
} on-error={ :log error "LBW fallo: fasttrack" }

:log warning "LBW: router de abajo listo. Las colas simples siguen funcionando igual."
:put "Listo. Comprueba: /ip route print  y  /queue simple print stats"
RSC
}

gen_remove(){
  cat << 'RSCHEAD'
# LBW - desinstalador
RSCHEAD
  echo "# LBW Wizard (c) 2026 $AUTHOR_ASCII - GPL-3.0-or-later - $REPO_URL"
  cat << 'RSC'
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
  :local d [:pick $cm 13 $p]
  :local rest [:pick $cm ($p + 1) [:len $cm]]
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
RSC
}


# ===================== Validacion del .rsc ===========================
# El validador va embebido: comprueba la sintaxis y las referencias cruzadas
# del .rsc generado antes de subirlo al router. No sustituye una prueba real,
# pero atrapa lo que RouterOS rechazaria al importar.
validate_rsc(){
  command -v python3 >/dev/null 2>&1 || { warn "Sin python3: me salto la validación del .rsc."; return 0; }
  local chk; chk=$(mktemp /tmp/lbw-check-XXXXXX.py)
  cat > "$chk" << 'LBWCHECKER'
#!/usr/bin/env python3
"""
check-rsc.py — validador estatico de scripts RouterOS (.rsc) generados por LBW Wizard.
No reemplaza una prueba en un router real, pero atrapa los errores de sintaxis y los
constructores que RouterOS v7 rechaza, antes de subir nada.

Uso:  python3 check-rsc.py archivo.rsc [...]
Sale con 0 si todo esta bien, 1 si hay errores.

LBW Wizard (c) 2026 Nedual Vargas (@NEDUALV) - GPL-3.0-or-later
"""
import sys, re

OPEN = {'(': ')', '[': ']', '{': '}'}
CLOSE = {v: k for k, v in OPEN.items()}

# Construcciones que RouterOS v7 rechaza o que dan problemas conocidos
BANNED = [
    (re.compile(r'\)\s+or\s+\('), "usa || en vez de 'or' dentro de :if"),
    (re.compile(r'\)\s+and\s+\('), "usa && en vez de 'and' dentro de :if"),
    (re.compile(r'/ip\s+dhcp-client\s+find\s+where\s+interface='),
     "find where interface= no casa en /ip dhcp-client (es una referencia, no texto): recorre [find where !disabled] y compara con :tostr"),
    (re.compile(r'/ip\s+route\s+add[^\n]*[^-]routing-mark='), "en v7 la ruta usa routing-table=, no routing-mark="),
    (re.compile(r'/ip\s+route\s+add[^\n]*gateway=[^\s]+[^\n]*check-gateway=ping[^\n]*scope=\d+[^\n]*target-scope=(\d+)')
     , None),  # informativo, se valida aparte
]

def scan(path):
    src = open(path, encoding='utf-8').read()
    errs, warns = [], []
    stack = []            # (char, line, col)
    in_str = False
    esc = False
    in_comment = False
    line, col = 1, 0
    for ch in src:
        col += 1
        if ch == '\n':
            line += 1; col = 0; in_comment = False
            if in_str:
                errs.append((line-1, col, 'comilla sin cerrar al final de la linea'))
                in_str = False; esc = False
            continue
        if in_comment:
            continue
        if in_str:
            if esc:            esc = False
            elif ch == '\\':   esc = True
            elif ch == '"':    in_str = False
            continue
        if ch == '#' and col == 1:
            in_comment = True; continue
        if ch == '"':
            in_str = True; continue
        if ch in OPEN:
            stack.append((ch, line, col))
        elif ch in CLOSE:
            if not stack:
                errs.append((line, col, f"'{ch}' sobra, no hay '{CLOSE[ch]}' abierto"))
            elif stack[-1][0] != CLOSE[ch]:
                o, ol, oc = stack[-1]
                errs.append((line, col, f"'{ch}' cierra un '{o}' abierto en linea {ol} col {oc}"))
                stack.pop()
            else:
                stack.pop()
    for o, ol, oc in stack:
        errs.append((ol, oc, f"'{o}' nunca se cierra"))

    # reglas de contenido, ignorando el interior de las cadenas
    code_lines = []
    for n, raw in enumerate(src.splitlines(), 1):
        if raw.lstrip().startswith('#'):
            code_lines.append((n, '')); continue
        out, instr, e = [], False, False
        for ch in raw:
            if instr:
                if e: e = False
                elif ch == '\\': e = True
                elif ch == '"': instr = False
                continue
            if ch == '"': instr = True; continue
            out.append(ch)
        code_lines.append((n, ''.join(out)))

    for n, code in code_lines:
        for rx, msg in BANNED:
            if msg and rx.search(code):
                errs.append((n, 1, msg))
        s = code.strip()
        if not s:
            continue
        if not (s.startswith('/') or s.startswith(':') or s.startswith('}')
                or s.startswith(')') or s.startswith(']') or s.startswith('{')
                or s.startswith('comment=') or s.startswith('on-error=')
                or code_lines[n-2][1].rstrip().endswith('\\')):
            warns.append((n, 1, f"la linea no empieza por / ni por : — ¿continuacion perdida?  >>> {s[:60]}"))
        if ':do {' in s and 'on-error=' not in s and not s.endswith('{'):
            warns.append((n, 1, ":do sin on-error= en la misma linea"))

    # dentro de las cadenas tambien: el script del DHCP client va entre comillas
    for n, raw in enumerate(src.splitlines(), 1):
        if re.search(r':tobool\s+\\*\$bound', raw):
            errs.append((n, 1, "[:tobool $bound] devuelve nil (bound llega como texto): usa ($bound=1) como el ejemplo oficial del DHCP client"))

    # coherencia de rutas recursivas: target-scope debe superar el scope del probe
    probes = {}
    for n, code in code_lines:
        m = re.search(r'/ip route add dst-address=([\d.]+)/32.*scope=(\d+).*target-scope=(\d+)', code)
        if m:
            probes[m.group(1)] = int(m.group(2))
    for n, code in code_lines:
        m = re.search(r'/ip route add dst-address=0\.0\.0\.0/0 gateway=([\d.]+).*target-scope=(\d+)', code)
        if m:
            gw, ts = m.group(1), int(m.group(2))
            if gw not in probes:
                errs.append((n, 1, f"ruta recursiva hacia {gw} sin ruta /32 que la resuelva"))
            elif ts < probes[gw]:
                errs.append((n, 1, f"target-scope={ts} no alcanza el scope={probes[gw]} del probe {gw}"))
    # regla documentada: un :local declarado en el nivel superior NO existe
    # en la siguiente linea de comando (manual de scripting de MikroTik)
    depth = 0
    declared = {}
    for n, code in code_lines:
        stripped = code.strip()
        m = re.match(r':local\s+(\w+)', stripped)
        if depth == 0 and m:
            declared[m.group(1)] = n
        elif depth == 0 and stripped:
            for var, dl in list(declared.items()):
                if re.search(r'\$' + var + r'\b', code) and n != dl:
                    errs.append((n, 1, f"$\u007b{var}\u007d se declaro con :local en la linea {dl}: un :local no sobrevive a la siguiente linea de comando. Mete todo en un solo bloque :do {{...}} o usa :global"))
                    del declared[var]
        depth += code.count('{') - code.count('}')
        if depth < 0: depth = 0

    # referencias cruzadas: tablas, listas de interfaz y address-lists
    tables = set(re.findall(r'/routing table add[^\n]*name=([\w-]+)', src))
    for n, code in code_lines:
        for m in re.finditer(r'new-routing-mark=([\w-]+)', code):
            if m.group(1) not in tables:
                errs.append((n, 1, f"new-routing-mark={m.group(1)} sin /routing table add que la cree"))
        for m in re.finditer(r'routing-table=([\w-]+)', code):
            if m.group(1) not in tables and m.group(1) != 'main':
                errs.append((n, 1, f"routing-table={m.group(1)} sin /routing table add que la cree"))
    ilists = set(re.findall(r'/interface list add[^\n]*name=([\w-]+)', src))
    ilists |= set(re.findall(r'/interface list add name=([\w-]+)', src))
    for n, code in code_lines:
        for m in re.finditer(r'(?:in|out)-interface-list=!?([\w-]+)', code):
            if m.group(1) not in ilists:
                errs.append((n, 1, f"interface-list {m.group(1)} usada sin crearse"))
    alists = set(re.findall(r'/ip firewall address-list add list=([\w-]+)', src))
    for n, code in code_lines:
        for m in re.finditer(r'address-list=!?([\w-]+)', code):
            if m.group(1) not in alists and not code.lstrip().startswith('/ip firewall address-list'):
                errs.append((n, 1, f"address-list {m.group(1)} usada sin crearse"))
    # PCC: todos los restos cubiertos una sola vez
    buckets = {}
    for n, code in code_lines:
        m = re.search(r'per-connection-classifier=[\w-]+:(\d+)/(\d+)', code)
        if m:
            tot, rem = int(m.group(1)), int(m.group(2))
            buckets.setdefault(tot, []).append((rem, n))
    for tot, items in buckets.items():
        rems = sorted(r for r, _ in items)
        if rems != list(range(tot)):
            errs.append((items[0][1], 1, f"PCC con {tot} partes: los restos son {rems}, deberian ser 0..{tot-1}"))
    return errs, warns

def main():
    rc = 0
    for path in sys.argv[1:]:
        errs, warns = scan(path)
        for l, c, m in sorted(warns):
            print(f"{path}:{l}:{c}: aviso: {m}")
        for l, c, m in sorted(errs):
            print(f"{path}:{l}:{c}: ERROR: {m}")
        if errs:
            rc = 1
            print(f"{path}: {len(errs)} error(es), {len(warns)} aviso(s)")
        else:
            print(f"{path}: sintaxis correcta ({len(warns)} aviso(s))")
    return rc

if __name__ == '__main__':
    sys.exit(main())
LBWCHECKER
  local out rc
  out=$(python3 "$chk" "$@" 2>&1); rc=$?
  rm -f "$chk"
  if (( rc == 0 )); then
    ok "Validación del .rsc: sintaxis y referencias correctas."
    [[ $out == *aviso* ]] && grep -q ': aviso:' <<< "$out" && { while IFS= read -r l; do [[ $l == *': aviso:'* ]] && hint "$l"; done <<< "$out"; }
    return 0
  fi
  box "$CE" "El .rsc generado no pasó la validación" "$(grep ': ERROR:' <<< "$out" | head -8)"
  return 1
}

OUTNAME="lbw-$(date '+%m%d-%H%M').rsc"
gen_rsc > "$OUTNAME"
gen_remove > lbw-remove.rsc
[[ $ROLE == balancer ]] && gen_router2 > lbw-router2.rsc
echo
ok "Generado ${BOLD}$OUTNAME${N} ($(wc -l < "$OUTNAME") líneas) y ${BOLD}lbw-remove.rsc${N}"
[[ $ROLE == balancer ]] && ok "Generado también ${BOLD}lbw-router2.rsc${N} para el router de abajo"
if ! validate_rsc "$OUTNAME" lbw-remove.rsc $([[ $ROLE == balancer ]] && echo lbw-router2.rsc); then
  err "No subo nada al router con esto así. Repórtalo en $REPO_URL/issues con el .rsc adjunto."
  exit 1
fi

# ========================= Despliegue ================================
if (( ! DETECTED )); then
  confirm r "¿Quieres enviarlo al router ahora por SSH?" n
  if [[ $r == s ]]; then
    input RHOST "IP del router" "192.168.88.1" is_ip
    input RUSER "Usuario" "admin" is_any
    input RPORT "Puerto SSH" "22" is_port
    if command -v sshpass >/dev/null 2>&1; then secret SSHPASS "Contraseña del router"; export SSHPASS; fi
    DETECTED=1
  fi
fi

if (( DETECTED )); then
  echo
  box "$CW" "Antes de aplicar, lee esto" \
    "La red de seguridad arma un scheduler en el router llamado lbw-rollback." \
    "Si no confirmas en $ROLLBACK_MIN minutos EN ESTA MISMA TERMINAL, el router deshace todo solo." \
    "Si cierras el asistente o se cae el SSH, desármala tú desde Winbox → New Terminal con:" \
    "   /system scheduler remove [find where comment=\"ROLLBACK-LBW\"]"
  echo
  menu DEPLOY "¿Cómo lo aplicamos?" 1 \
    "safe|Subir y aplicar con red de seguridad  ★ recomendado|Si pierdes acceso, el router se revierte solo a los $ROLLBACK_MIN minutos" \
    "upload|Solo subir los archivos|Luego lo importas tú desde Winbox → Terminal. No se arma ninguna red de seguridad." \
    "none|No subir nada|Ya tienes los archivos en esta carpeta"

  if [[ $DEPLOY != none ]]; then
    run "Guardando backup del router…" rssh '/system backup save name="pre-lbw"; /export file="pre-lbw"' >/dev/null && ok "Backup pre-lbw.backup y pre-lbw.rsc guardados en el router."
    if ! run "Subiendo archivos al router…" rscp "$OUTNAME" lbw-remove.rsc; then
      err "No pude subir los archivos. Arrástralos en Winbox → Files."; DEPLOY=none
    else ok "Archivos subidos al router."; fi
  fi

  if [[ $DEPLOY == safe ]]; then
    rb='/system scheduler remove [find where comment="ROLLBACK-LBW"]; /system scheduler add name=lbw-rollback interval='"$ROLLBACK_MIN"'m comment="ROLLBACK-LBW" on-event="/system scheduler remove [find where comment=\"ROLLBACK-LBW\"]; :log error \"LBW: sin confirmacion, aplicando rollback\"; /import file-name=lbw-remove.rsc"'
    if run "Activando la red de seguridad…" rssh "$rb" >/dev/null; then
      ok "Red de seguridad activa: revierte en $ROLLBACK_MIN min si no confirmas."
      run "Aplicando configuración (tarda ~20 s)…" rssh ":execute script=\"/import file-name=$OUTNAME verbose=yes\" file=lbw-import" >/dev/null
      if ((TTY)); then for s in $(seq 25 -1 1); do printf '\r%s%s⏳%s Esperando a que el router se estabilice… %s%2ds%s' "$M" "$CA" "$N" "$BOLD" "$s" "$N"; sleep 1; done; printf '\r\e[2K'; else sleep 25; fi
      stq=":foreach w in={"
      for ((i=1; i<=NWAN; i++)); do stq+="\"WAN$i\";"; done
      stq="${stq%;}} do={ :put (\"ST|\" . \$w . \"|\" . [:len [/ip route find where comment~(\"LBW:\" . \$w . \":(OWN|MAIN)\") && active]]) }; :put (\"SUM|\" . [:len [/ip route find where comment~\"^LBW\"]] . \"|\" . [:len [/ip firewall mangle find where comment~\"^LBW\"]] . \"|\" . [:len [/ip firewall nat find where comment~\"^LBW\"]] . \"|\" . [:len [/routing table find where comment~\"^LBW\"]])"
      st=$(run "Consultando estado…" rssh "$stq" 2>/dev/null | tr -d '\r')
      if [[ -z $st ]]; then
        box "$CE" "Perdí la conexión con el router" \
          "Si tampoco tienes acceso tú, espera $ROLLBACK_MIN minutos: el router aplicará lbw-remove.rsc solo." \
          "Si sí tienes acceso y todo funciona, desarma la red de seguridad con:" \
          "   /system scheduler remove [find where comment=\"ROLLBACK-LBW\"]"
        exit 1
      fi
      sumline=$(grep "^SUM|" <<< "$st")
      nrt=$(cut -d'|' -f2 <<< "$sumline"); nmg=$(cut -d'|' -f3 <<< "$sumline")
      nnt=$(cut -d'|' -f4 <<< "$sumline"); ntb=$(cut -d'|' -f5 <<< "$sumline")
      if [[ ${nmg:-0} -eq 0 || ${nnt:-0} -eq 0 ]]; then
        box "$CE" "La configuración quedó incompleta" \
          "El router solo tiene: rutas=${nrt:-0}, mangle=${nmg:-0}, NAT=${nnt:-0}, tablas=${ntb:-0}." \
          "El import se detuvo antes de terminar. Mira qué falló con:" \
          "   /log print where message~\"LBW fallo\"" \
          "Lo más sano es revertir y volver a intentarlo:" \
          "   /import file-name=lbw-remove.rsc"
        echo
        menu bad "¿Qué hacemos?" 1 \
          "revert|Revertir ahora|Deja el router como estaba antes" \
          "keep|Dejarlo así y revisar yo|Desarma la red de seguridad y te quedas con lo que haya"
        if [[ $bad == revert ]]; then
          run "Revirtiendo…" rssh '"'"'/system scheduler remove [find where comment="ROLLBACK-LBW"]; /import file-name=lbw-remove.rsc'"'"' >/dev/null
          err "Revertido. Revisa el log del router y vuelve a correr el asistente."
          exit 1
        fi
        run "Desarmando la red de seguridad…" rssh '"'"'/system scheduler remove [find where comment="ROLLBACK-LBW"]'"'"' >/dev/null
        exit 1
      fi
      lines=()
      for ((i=1; i<=NWAN; i++)); do
        cnt=$(grep "^ST|WAN$i|" <<< "$st" | cut -d'|' -f3)
        if [[ ${cnt:-0} -gt 0 ]]; then lines+=("EN LINEA  $(pad "${WNAME[$i]}" 14) ${WFINAL[$i]}")
        else lines+=("SIN RED   $(pad "${WNAME[$i]}" 14) ${WFINAL[$i]} · revisa cable, credenciales o lease"); fi
      done
      box "$CA" "Estado de tus proveedores" "${lines[@]}"
      echo
      warn "Tienes $ROLLBACK_MIN minutos para responder. Prueba navegar desde un equipo de la LAN."
      menu OKC "¿Todo funciona?" 1 \
        "keep|Sí, mantener la configuración|Desarma la red de seguridad" \
        "revert|No, revertir ahora|Aplica lbw-remove.rsc de inmediato"
      if [[ $OKC == keep ]]; then
        run "Confirmando…" rssh '/system scheduler remove [find where comment="ROLLBACK-LBW"]' >/dev/null && ok "¡Listo! Configuración confirmada y red de seguridad desarmada."
      else
        run "Revirtiendo…" rssh '/system scheduler remove [find where comment="ROLLBACK-LBW"]; /import file-name=lbw-remove.rsc' >/dev/null && ok "Revertido."
      fi
    else
      err "No pude activar la red de seguridad; no apliqué nada. Impórtalo a mano."
    fi
  elif [[ $DEPLOY == upload ]]; then
    info "Archivos en el router. Impórtalos tú con Safe Mode (Ctrl+X):"
    say "   ${CA}/import file-name=$OUTNAME verbose=yes${N}"
  fi
fi

echo
box "$CB" "Comandos útiles" \
  "Aplicar a mano (Winbox → New Terminal, con Safe Mode: Ctrl+X):" \
  "   /import file-name=$OUTNAME verbose=yes" \
  "Desarmar la red de seguridad:" \
  "   /system scheduler remove [find where comment=\"ROLLBACK-LBW\"]" \
  "Ver rutas:    /ip route print where comment~\"LBW\"" \
  "Ver eventos:  /log print where message~\"LBW\"" \
  "Ver reparto:  /ip firewall mangle print stats where comment~\"PCC\"" \
  "Simular caída de ${WNAME[1]}:" \
  "   /ip route disable [find where comment=\"LBW:WAN1:PROBE\"]" \
  "Desinstalar:  /import file-name=lbw-remove.rsc"
if [[ $ROLE == balancer ]]; then
  echo
  box "$CW" "Falta el router de abajo" \
    "Sube lbw-router2.rsc a ESE router y aplícalo:" \
    "   /import file-name=lbw-router2.rsc verbose=yes" \
    "Le pone la ruta por defecto hacia $BALIP, le quita el NAT y el FastTrack." \
    "Sus colas simples siguen igual: clasifican por IP de cliente." \
    "Si usas queue tree con packet-marks en prerouting, revisa que tus reglas" \
    "de marcado queden ANTES de las de LBW (las de mark-routing van con passthrough=no)."
fi
echo "${M}${CD}LBW Wizard v$VERSION · $AUTHOR · $REPO_URL${N}"
echo
