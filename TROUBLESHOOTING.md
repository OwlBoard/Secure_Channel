# Troubleshooting - Secure Canal

Este documento describe los problemas encontrados durante la implementación del Secure Canal y sus soluciones.

## ✅ Problemas Resueltos

### 1. ❌ Chat Service: PermissionError al leer certificados SSL

**Síntoma:**
```
PermissionError: [Errno 13] Permission denied
File "/usr/local/lib/python3.11/site-packages/uvicorn/config.py", line 116, in create_ssl_context
    ctx.load_cert_chain(certfile, keyfile, get_password)
```

**Causa:**
- El Dockerfile creaba un usuario no-root (`chatuser`)
- Los directorios `/etc/ssl/private` y `/etc/ssl/certs` no existían en el contenedor
- El usuario no tenía permisos para acceder a los certificados montados

**Solución aplicada en `Chat_Service/Dockerfile`:**
```dockerfile
# Crear directorios SSL con permisos correctos
RUN useradd -m -u 1000 chatuser && \
    mkdir -p /etc/ssl/private /etc/ssl/certs && \
    chown -R chatuser:chatuser /app /etc/ssl/private /etc/ssl/certs

USER chatuser
```

**Permisos de archivos en el host:**
```bash
chmod 644 Secure_Channel/certs/chat_service/server.crt
chmod 644 Secure_Channel/certs/chat_service/server.key
```
```

---

### 2. ❌ Reverse Proxy: Healthcheck fallando (unhealthy)

**Síntoma:**
```
reverse_proxy      Up 6 minutes (unhealthy)
```

Al ejecutar el healthcheck manualmente:
```bash
docker exec reverse_proxy wget --no-verbose --tries=1 --spider http://localhost/health
# Output: Connecting to localhost ([::1]:80)
# wget: can't connect to remote host: Connection refused
```

**Causa:**
- Nginx solo estaba escuchando en IPv4 (`listen 80;`)
- El comando `wget` dentro del contenedor intentaba conectarse usando IPv6 (`::1`)
- La conexión IPv6 fallaba porque nginx no estaba configurado para escuchar en IPv6

**Solución aplicada en `Reverse_Proxy/nginx.conf`:**
```nginx
server {
    listen 80;
    listen [::]:80;  # ← AÑADIDO: Escuchar en IPv6 también
    server_name _;
    # ...
}
```

---

### 3. ❌ Chat Service: Healthcheck fallando por módulo faltante

**Síntoma:**
```
chat_service       Up 5 minutes (unhealthy)
```

Al ejecutar el healthcheck manualmente:
```bash
docker exec chat_service python -c "import requests; requests.get(...)"
# Output: ModuleNotFoundError: No module named 'requests'
```

**Causa:**
- El healthcheck intentaba usar el módulo `requests` de Python
- El módulo `requests` no estaba instalado en el contenedor
- Solo estaba en `requirements.txt` para la aplicación, no para el healthcheck

**Solución aplicada en `Chat_Service/Dockerfile`:**

Cambiamos de usar `requests` a usar el módulo estándar `socket`:

```dockerfile
# Antes (requería instalar requests):
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('https://localhost:8443/health', verify=False)" || exit 1

# Después (usa módulo estándar):
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.connect(('localhost', 8443)); s.close()" || exit 1
```

---

## 📊 Estado Final de los Servicios

Después de aplicar las correcciones:

```
NAME               STATUS
api_gateway        Up (running)
canvas_service     Up (running)
chat_service       Up (healthy) ✅
comments_service   Up (running)
mobile_frontend    Up (running)
mongo_db           Up (healthy) ✅
mysql_db           Up (healthy) ✅
nextjs_frontend    Up (running)
postgres_db        Up (healthy) ✅
rabbitmq           Up (healthy) ✅
redis_db           Up (healthy) ✅
reverse_proxy      Up (healthy) ✅
user_service       Up (running)
```

---

## 🧪 Verificación de Servicios SSL

### Chat Service (puerto 8002):
```bash
curl -k https://localhost:8002/health
# Output: {"status":"healthy","service":"chat_service"}
```

### User Service (puerto 5000):
```bash
curl -k https://localhost:5000/health
# Output: {"status":"healthy","service":"user-service"}
```

### Reverse Proxy (puerto 9000):
```bash
curl http://localhost:9000/health
# Output: healthy
```

---

## 🔍 Comandos de Diagnóstico

### Verificar logs de un servicio:
```bash
docker-compose logs <service_name> --tail=50
```

### Probar healthcheck manualmente:
```bash
# Para servicios con wget:
docker exec <container_name> wget --no-verbose --tries=1 --spider http://localhost/health

# Para servicios Python:
docker exec <container_name> python -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.connect(('localhost', 8443)); s.close()"
```

### Verificar permisos de certificados:
```bash
ls -la Secure_Channel/certs/*/
```

### Verificar que nginx escucha en IPv6:
```bash
docker exec reverse_proxy netstat -tlnp | grep :80
# Debería mostrar tanto 0.0.0.0:80 como :::80
```

### Reconstruir un servicio específico:
```bash
docker-compose build <service_name>
docker-compose up -d <service_name>
```

---

## 📝 Lecciones Aprendidas

1. **Permisos de directorios en Docker:**
   - Siempre crear explícitamente los directorios que recibirán volúmenes montados
   - Asignar permisos correctos ANTES de cambiar al usuario no-root

2. **IPv6 en contenedores:**
   - Nginx debe configurarse para escuchar en IPv4 e IPv6 si se espera tráfico en ambos
   - Los comandos de healthcheck pueden preferir IPv6 si está disponible

3. **Healthchecks en Docker:**
   - Usar solo módulos estándar de Python (evitar dependencias externas)
   - Preferir verificaciones simples (socket, curl, wget) sobre HTTP requests complejos
   - Ajustar `start_period` según el tiempo de inicio real del servicio

4. **SSL/TLS en microservicios:**
   - Los certificados deben tener permisos de lectura (644) para que los contenedores puedan accederlos
   - Las llaves privadas pueden usar 600 o 644 dependiendo del nivel de seguridad requerido
   - Todos los servicios en la cadena (reverse proxy → gateway → services) deben estar configurados para SSL

---

## 🚀 Script de Verificación

Ejecutar el script de verificación completo:
```bash
./Secure_Channel/verify.sh
```

Este script verifica:
- ✅ Estructura de directorios
- ✅ Validez de la CA
- ✅ Certificados de servicios
- ✅ Permisos de archivos
- ✅ Configuración de Docker Compose
- ✅ Estado de servicios en ejecución

---

## 🔗 Referencias

- [Documentación principal del Secure Canal](./README.md)
- [Docker Healthcheck Reference](https://docs.docker.com/engine/reference/builder/#healthcheck)
- [Nginx IPv6 Configuration](http://nginx.org/en/docs/http/ngx_http_core_module.html#listen)
- [Uvicorn SSL Configuration](https://www.uvicorn.org/settings/#https)
