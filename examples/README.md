# Ejemplos

Archivos generados por el asistente (v3.1), solo para ver la salida. **No los importes tal cual**: las interfaces, IP y subredes son de ejemplo.

- `ejemplo-2wan-balanceo.rsc` — todo en uno: dos líneas DHCP (Claro y Altice) con balanceo PCC, failover recursivo, un equipo fijado a Claro y un banco fijado a Altice, servicios endurecidos, log en disco y NTP
- `ejemplo-desinstalador.rsc` — revierte todo lo que pone LBW en ese router
- `ejemplo-solo-balanceador.rsc` — modo WISP: este equipo solo reparte, delante de otro router; enlace en 10.255.255.0/30
- `ejemplo-router-de-abajo.rsc` — lo que se aplica al router de abajo en ese montaje
- `ejemplo-router-de-abajo-desinstalador.rsc` — devuelve el router de abajo a como estaba

Genera los tuyos con `./lbw-wizard.sh`.
