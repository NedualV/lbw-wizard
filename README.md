# LBW Wizard — Multi-WAN para MikroTik RouterOS v7

## Así se ve

![LBW Wizard](docs/01-banner.png)

El asistente va paso a paso, en español, explicando cada decisión en lugar de pedir datos técnicos sueltos.

| | |
|---|---|
| ![Paso 1](docs/02-paso1-router.png) | ![Paso 2](docs/03-paso2-modo.png) |
| ![Paso 3](docs/04-paso3-proveedores.png) | ![Paso 4](docs/05-paso4-reparto.png) |
| ![Paso 5](docs/06-paso5-papel.png) | ![Paso 7](docs/07-paso7-resumen.png) |

Asistente interactivo que genera la configuración de **balanceo de carga (PCC) + failover recursivo** para routers MikroTik con 2 a 6 proveedores de Internet. Pregunta todo paso a paso y genera un `.rsc` listo para importar, más su desinstalador.

> Creado por **Nedual Vargas** ([@NEDUALV](https://youtube.com/@NEDUALV))

## Dos formas de montarlo

El asistente pregunta qué papel hace el equipo:

**Balanceador y router de la LAN (todo en uno).** Él reparte las líneas, hace NAT, firewall y DNS, y los equipos cuelgan de él. Es lo normal en casa o en una oficina.

**Solo balanceador, delante de otro router.** Pensado para WISP: este equipo reparte las líneas y hace el único NAT del camino; el router de abajo lleva las colas simples, el PPPoE y los clientes.

En modo automático solo eliges dos puertos (el de cada router) y el asistente hace el resto: pone la IP del enlace, levanta un DHCP que le entrega una IP fija al router de abajo, enruta de vuelta todo el espacio privado (10.x, 172.16-31.x, 192.168.x) para cubrir cualquier pool de clientes presente o futuro, y genera `lbw-router2.rsc`, que deja ese router en ruteo puro: cliente DHCP con ruta por defecto, sin NAT y sin FastTrack. Si usas IP públicas para clientes, el modo manual te deja indicar las subredes exactas.

> El router de abajo **no debe hacer NAT**. Si enmascara, todas las conexiones llegan al balanceador con una sola IP de origen y el reparto por equipo deja de funcionar.

Las colas simples no se ven afectadas: clasifican por IP de cliente, no por marcas de ruteo. Si usas queue tree con packet-marks en `prerouting`, revisa que tus reglas de marcado queden antes de las de LBW, porque las de `mark-routing` llevan `passthrough=no`.

## Qué hace

- Balanceo PCC con reparto según la velocidad contratada de cada línea, y 3 clasificadores explicados en español (por equipo, por equipo+sitio, por conexión)
- Modo solo failover con orden de prioridad
- Failover recursivo con **doble probe por ISP**: la línea solo se da por caída si fallan los dos
- Probes separados de los DNS, para que una caída de probe no deje sin resolución
- Renombra las interfaces conservando el nombre original y agregando `_ISP1`, `_ISP2`… Todas las reglas usan **interface lists**, así que puedes renombrar después sin romper la salida
- Soporta DHCP, IP fija, PPPoE (incluso sobre VLAN del ISP) e interfaces que ya traen su salida (LTE, túneles)
- Saca del bridge el puerto que vayas a usar como WAN, y el desinstalador lo devuelve
- Auditoría previa del router: FastTrack, rutas por defecto, mangle ajeno, tablas de ruteo, NAT sin lista, hotspot, PPP server, colas y rollbacks pendientes
- Tres formas de arrancar: sobre la configuración actual, con reset de fábrica o con reset total
- Monitor cada 10 s que limpia las conexiones de la línea caída y avisa por log y, opcionalmente, por Telegram
- Red de seguridad configurable: si no confirmas a tiempo, el router se revierte solo
- Desinstalador que devuelve nombres de interfaz, puertos del bridge, FastTrack, rutas y NAT a como estaban

## Validación automática

Cada `.rsc` que genera el asistente pasa por un validador estático antes de subirse al router: comprueba balance de comillas, paréntesis y llaves, constructores que RouterOS v7 rechaza, y referencias cruzadas (que cada `routing-table` exista, que cada `interface-list` y `address-list` esté creada, y que los restos del PCC cubran todas las partes). Si no pasa, el asistente no sube nada.

El validador va embebido en el propio `lbw-wizard.sh`: no hay archivos extra que descargar. Si falta `python3`, el asistente lo avisa y sigue sin validar.

No sustituye una prueba en un router real, pero atrapa lo que el import rechazaría.

## Requisitos

- MikroTik con **RouterOS v7**
- Linux o macOS con bash 4+
- Opcional: `sshpass` para no escribir la contraseña en cada conexión (`sudo dnf install sshpass`)

## Uso

Un solo archivo, sin dependencias más allá de bash y ssh:

```bash
chmod +x lbw-wizard.sh && ./lbw-wizard.sh
```

En cualquier pregunta puedes pulsar **Esc** o **←** para volver a la anterior y corregir.

Luego, si no lo aplicaste desde el asistente, en el router (Winbox → New Terminal, con Safe Mode, Ctrl+X):

```
/import file-name=lbw-XXXX.rsc verbose=yes
```

Para revertir:

```
/import file-name=lbw-remove.rsc
```

## La red de seguridad

Al aplicar con la opción recomendada, el asistente arma en el router un scheduler `lbw-rollback`. Si no confirmas **en la terminal del asistente** dentro del plazo que elegiste, el router importa `lbw-remove.rsc` solo y deshace todo.

Si cierras el asistente, se te cae el SSH o importas a mano, desármala tú:

```
/system scheduler remove [find where comment="ROLLBACK-LBW"]
```

## Comprobaciones

```
/ip route print where comment~"LBW"
/ip firewall mangle print stats where comment~"PCC"
/log print where message~"LBW"
```

Desde un equipo de la LAN, para ver las dos IP públicas en uso:

```bash
for i in $(seq 1 30); do curl -4 -s --max-time 10 https://ifconfig.me; echo; done | sort | uniq -c
```

## Avisos

- En modo balanceo se desactiva FastTrack: es incompatible con el policy routing y sube el uso de CPU en equipos modestos.
- Más de 2 partes de reparto pueden causar pérdida de paquetes de subida en WebRTC (Zoom, Teams, Discord, juegos), porque una misma aplicación puede salir por dos IP públicas distintas. El asistente lo avisa y ofrece partes iguales.
- Pruébalo primero en laboratorio (CHR) antes de llevarlo a un cliente.

## Licencia y autoría

Copyright © 2026 Nedual Vargas.
Licenciado bajo **GNU GPL v3 o posterior** — ver [LICENSE](LICENSE) y [NOTICE](NOTICE).
Puedes usarlo, modificarlo y compartirlo **conservando la autoría original** y publicando tus cambios bajo la misma licencia.
