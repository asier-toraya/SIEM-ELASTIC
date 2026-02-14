# SIEM-ELASTIC-SNORT

Este metodo evita los problemas de "mezclar imagenes latest con software viejo" y evita instalar cosas a mano dentro de contenedores de ELK.

Que monta:

- Elasticsearch 7.16.3
- Logstash 7.16.3 (entrada Beats 5044 sin TLS)
- Kibana 7.16.3
- Nginx (solo para generar logs HTTP)
- SSH victim (para fuerza bruta; usuario `victima`, password `a1`)
- Snort (IDS) mirando el trafico del victim (SSH + ICMP)
- Filebeat 7.16.3 (lee logs de nginx/snort/ssh y los envia a Logstash)


---

## 1) Donde ejecutar comandos

Todos los comandos se ejecutan en **Windows PowerShell**.

Importante (puertos):

- Este laboratorio usa los puertos `80`, `22`, `5044`, `5601`, `9200`.
- Si ya tienes otro ELK/containers usando esos puertos, este metodo NO arrancara hasta que los pares.

1. Abre PowerShell
2. Entra en la carpeta de tu proyecto:

```powershell
cd C:\Users\......
```

3. Comprueba que estas bien:

```powershell
Get-ChildItem
```

Debes ver `docker-compose.yml`, carpetas `filebeat`, `logstash`, `snort`, `ssh-victim`, `nginx`.

---

## 2) Crear carpetas de logs (obligatorio)

Estas carpetas guardan logs en tu Windows para que puedas verlos sin entrar al contenedor.

Ejecuta (desde tu proyecto):

```powershell
New-Item -ItemType Directory -Force -Path .\logs\nginx,.\logs\snort,.\logs\ssh | Out-Null
```

---

## 3) Arrancar todo (build + compose up)

1. Construir y levantar:

```powershell
docker compose up -d --build
```

2. Ver estado:

```powershell
docker compose ps
```

Es normal que tarde 1-2 minutos en estar todo "healthy/ready" (especialmente Elasticsearch).

AQUI es importante que mires que todos los contenedores estan encendidos, si no lo estan, probablemente
sea por que el start.sh no se ha ejecutado correctamente, para solucionar esto tenemos que cambiar el archivo `Dockerfile` del ssh-victim por este nuevo codigo:
```
FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server \
      rsyslog \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create the lab user (password: a1)
RUN useradd -m -s /bin/bash victima \
 && echo "victima:a1" | chpasswd

# Basic SSH hardening for a lab (still allows password auth)
RUN sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config

COPY start.sh /start.sh
# Windows checkouts can convert LF->CRLF; that breaks the shebang and yields
# "exec /start.sh: no such file or directory" at runtime inside Linux.
RUN sed -i 's/\r$//' /start.sh \
 && chmod +x /start.sh

EXPOSE 22

CMD ["/start.sh"]
```

Y luego ejecutar:
```
docker compose up -d --build --force-recreate ssh-victim

docker compose up -d snort filebeat
```

---

## 4) Abrir Kibana y crear el Data View

1. Abre Kibana:

`http://localhost:5601`

2. Crea un Data View (en tu version puede ser `Create index pattern`):
`Stack management` -> `Index patterns` -> `Create index pattern`

- Name/Pattern: `filebeat-*`
- Time field: `@timestamp`

1. Ve a `Discover` y selecciona `filebeat-*`.

Consejo:

- Pon el tiempo en `Last 15 minutes`.

---

## 5) Probar que entran eventos (comandos de prueba)

Importante:

- Mientras pruebas, deja el Dashboard/Discover en `Last 15 minutes` y refresco automatico (3s o 5s).

### 5.1 Probar Nginx (HTTP)

Genera 20 peticiones HTTP:

```powershell
1..20 | ForEach-Object { Invoke-WebRequest http://localhost -UseBasicParsing | Out-Null }
```

Comprueba que nginx escribio logs en Windows:

```powershell
Get-Content .\logs\nginx\access.log -Tail 10
```

### 5.2 Probar ICMP (ping) para Snort

Snort solo ve el trafico que entra al `ssh-victim`. Para generar ping de forma fiable, lo hacemos desde otro contenedor dentro de la red Docker.
Desde la carpeta de tu proyecto:

```powershell
docker compose exec tools ping -c 6 ssh-victim
```

Comprueba alertas Snort en Windows:

```powershell
Get-Content .\logs\snort\alert -Tail 20
```

Debes ver lineas como:

- `LAB ICMP echo request (ping)`

### 5.3 Probar SSH Failed password (sin Hydra)
(Puede dar error la key de localhost)


1. Ejecuta:

```powershell
ssh victima@localhost
```

2. Mete mal la password 3 a 5 veces.

3. Comprueba en Windows que se escribio `auth.log`:

```powershell
Get-Content .\logs\ssh\auth.log -Tail 30
```

Si te da error el `ssh...` ejecuta en Powershell:

```powershell
ssh-keygen -R localhost
ssh-keygen -R "[localhost]:22"
```

### 5.4 Probar fuerza bruta SSH (con Hydra desde Kali)

1. Averigua la IP de tu Windows en la red (192.168.x.x):

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Select-Object IPAddress,InterfaceAlias | Format-Table -Auto
```
Primero mira si la red de tu maquina kali (NAT o Bridged) esta bien con un `ping -c IP de tu pc` si todo esta bien y te da ping, ejecuta el comando de hydra.
Si no te da ping, prueba `ssh victima@IP-TUPC` si te funciona, la red esta bien pero tu PC tiene protegido por firewall el ICMPv4.

Abrirlo en PS como administrador:
```PowerShell
# Ver la config actual
Get-NetFirewallRule -Name CoreNet-Diag-ICMP4-EchoRequest-In | Select-Object Name,Enabled,Profile,Direction,Action

# Habilitar ping (ICMPv4 echo request) de entrada
Enable-NetFirewallRule -Name CoreNet-Diag-ICMP4-EchoRequest-In

# Habilitar red en public
Set-NetFirewallRule -Name CoreNet-Diag-ICMP4-EchoRequest-In -Profile Public
```

Para cerrarlo ICMPv4 despues (importante):
```PowerShell
Disable-NetFirewallRule -Name CoreNet-Diag-ICMP4-EchoRequest-In

Set-NetFirewallRule -Name CoreNet-Diag-ICMP4-EchoRequest-In -Profile Private

```

2. En Kali usa Hydra contra `ssh://<IP_WINDOWS>:22` (ejemplo: `192.168.1.35`).

Uno de los 2. Cuando diga "attacking..." espera unos 5-10 segundos y para con CTRL+C
```bash
hydra -L /usr/share/wordlists/rockyou.txt -P /usr/share/wordlists/rockyou.txt ssh://192.168.1.35

hydra -l asier -P /usr/share/wordlists/rockyou.txt ssh://192.168.1.35
```

Si no tienes descomprimido el rockyou, tendras que descomprimirlo primero. O crearte tu propia wordlist si te resulta mas facil y usar ese archivo.

Nota:

- Snort detecta "muchas conexiones" a 22 y lo escribe en `.\logs\snort\alert`.
- `sshd` escribe `Failed password` en `.\logs\ssh\auth.log`.

---

## 6) Paneles que debes crear (Lens) para cumplir requisitos

Crea un `Dashboard` y anade estos paneles.

Importante:

- En cada Lens, revisa que el Data View es `filebeat-*`.

### Panel A (requisito caso de uso): Snort SSH brute force (Metric)

Tipo: `Metric`

KQL:

```kql
type:"snort-alert" and message:"LAB SSH brute-force indicator"
```

Metric:

- `Count of records`

### Panel B: Snort SSH brute force (timeline)

Tipo: `Line`

KQL:

```kql
type:"snort-alert" and message:"LAB SSH brute-force indicator"
```

X:

- `@timestamp` -> `Date histogram` (interval `Auto` o `1m`)

Y:

- `Count of records`

### Panel C (requisito fuerza bruta): SSH Failed password (timeline)

Tipo: `Line`

KQL:

```kql
type:"ssh-auth" and message:"Failed password"
```

X:

- `@timestamp` -> `Date histogram`

Y:

- `Count of records`

### Panel D (requisito IDS): ICMP ping detectado por Snort (timeline)

Tipo: `Line`

KQL:

```kql
type:"snort-alert" and message:"LAB ICMP echo request"
```

X:

- `@timestamp` -> `Date histogram`

Y:

- `Count of records`

---

## 7) Errores tipicos y soluciones rapidas

### No veo nada en Kibana

1. Pon el tiempo en `Last 1 hour`.
2. Asegurate de usar Data View `filebeat-*`.
3. Genera eventos (seccion 5).

### Snort no genera alertas

1. Comprueba que `snort` esta `Up`:

```powershell
docker compose ps
```

2. Genera ping (seccion 5.2) y mira `.\logs\snort\alert`.

### Hydra no conecta a SSH

1. Comprueba el puerto 22 desde Windows:

```powershell
Test-NetConnection localhost -Port 22
```

2. Si falla, mira si el contenedor `ssh-victim` esta `Up`:

```powershell
docker compose ps
```

---

## 8) Parar todo (y borrar datos)

Parar contenedores:

```powershell
docker compose down
```

Parar y borrar volumenes internos (Elasticsearch y Filebeat registry):

```powershell
docker compose down -v
```


## 9 Recopilación de comandos de pruebas:
```
# PING Snort
docker compose exec tools ping -c 6 ssh-victim

# SSH Failed password
ssh victima@localhost

# Hydra SSH brute force
hydra -L /usr/share/wordlists/rockyou.txt -P /usr/share/wordlists/rockyou.txt ssh://[IP_WINDOWS]

```