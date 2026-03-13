# bugs.md

## om-ssh-victim: `exec /start.sh: no such file or directory`

**Sintoma**

- Al ejecutar `docker compose up -d --build`, el contenedor `om-ssh-victim` no arranca y en logs aparece:
  - `exec /start.sh: no such file or directory`

**Causa**

- El script `ssh-victim/start.sh` estaba con finales de linea Windows (CRLF). En contenedores Linux esto puede romper el *shebang* (`#!/bin/sh`) y provocar el error anterior aunque el fichero exista.

**Solucion**

- Se normalizaron los finales de linea a LF y se hizo el build mas robusto:
  - `ssh-victim/Dockerfile`: se anadio `sed -i 's/\r$//' /start.sh` antes de ejecutar el script.
  - `.gitattributes`: se fuerza `*.sh` a `eol=lf` para evitar que Git vuelva a convertir a CRLF en Windows.

**Comandos**

```powershell
docker compose up -d --build --force-recreate ssh-victim
docker compose ps
```

## Kibana: `localhost:5601` no responde (timeout) aunque el contenedor esta OK

**Sintoma**

- No se puede acceder a Kibana en `http://localhost:5601` desde Windows (navegador / `curl.exe` / `Test-NetConnection`).
- La conexion se queda colgada hasta hacer timeout.

**Evidencia**

- El contenedor `om-kibana` esta levantado y publica el puerto:
  - `docker ps` mostraba `0.0.0.0:5601->5601/tcp`.
- Desde dentro de la red de Docker, Kibana si responde (por ejemplo desde `om-tools`):
  - `curl -I http://kibana:5601/` devuelve `HTTP/1.1 302 Found` y redirige a `/spaces/enter`.
- En Windows el puerto parecia estar en escucha (port-forward de Docker Desktop), pero el cliente no llegaba a establecer sesion HTTP:
  - `netstat -ano | findstr :5601` mostraba `LISTENING` y conexiones en `SYN_SENT/SYN_RECEIVED`.
  - `curl.exe -I http://127.0.0.1:5601/` terminaba en timeout.

**Causa (hipotesis)**

- Fallo / estado inconsistente del *port publishing* de Docker Desktop (Windows/WSL2) para ese puerto/servicio.
- No era un problema de Kibana como proceso (respondia correctamente dentro de la red Docker).

**Workarounds**

- Reiniciar el stack de red de Docker Desktop/WSL2:
  1. Cerrar Docker Desktop.
  2. Ejecutar `wsl --shutdown`.
  3. Abrir Docker Desktop y esperar a que este "Running".
  4. `docker compose up -d`
- (Intentado) Cambiar el puerto publicado de Kibana en `docker-compose.yml` (por ejemplo `15601:5601`) para evitar conflictos locales. Si el *port publishing* esta roto, esto puede no resolverlo.

**Comandos de diagnostico**

```powershell
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
docker logs --tail 200 om-kibana
netstat -ano | findstr :5601
Get-NetTCPConnection -LocalPort 5601 | Format-Table -AutoSize
Test-NetConnection -ComputerName localhost -Port 5601

# Prueba desde dentro de la red Docker (debe responder 302)
docker exec om-tools sh -lc "curl -I --max-time 5 http://kibana:5601/"
```
