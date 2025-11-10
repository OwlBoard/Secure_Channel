# Secure Canal - SSL/TLS Certificate Management

Este componente gestiona los certificados SSL/TLS para la comunicación segura entre los microservicios de OwlBoard.

## 📁 Estructura del Directorio

```
Secure_Canal/
├── ca/                      # Autoridad Certificadora (CA)
│   ├── ca.crt              # Certificado de la CA (público)
│   ├── ca.key              # Llave privada de la CA (privado)
│   └── ca.srl              # Serial number para certificados firmados
├── certs/                   # Certificados de los servicios
│   ├── api_gateway/
│   │   ├── server.crt      # Certificado del API Gateway
│   │   ├── server.key      # Llave privada del API Gateway
│   │   ├── server.csr      # Certificate Signing Request
│   │   └── server.ext.cnf  # Configuración de extensiones
│   ├── chat_service/
│   │   ├── server.crt
│   │   ├── server.key
│   │   ├── server.csr
│   │   └── server.ext.cnf
│   └── user_service/
│       ├── server.crt
│       ├── server.key
│       ├── server.csr
│       └── server.ext.cnf
└── .gitignore
```

## 🔐 Componentes

### Autoridad Certificadora (CA)
La CA es la entidad raíz que firma todos los certificados de los servicios. Todos los servicios confían en esta CA.

### Certificados de Servicios
Cada servicio tiene su propio certificado firmado por la CA, que incluye:
- **server.crt**: Certificado público del servicio
- **server.key**: Llave privada del servicio (debe mantenerse segura)
- **server.csr**: Request usado para generar el certificado
- **server.ext.cnf**: Configuración de extensiones (SANs, uso de claves, etc.)

## 🔧 Configuración en Docker Compose

Cada servicio que usa SSL debe montar los certificados en sus volúmenes:

```yaml
services:
  chat_service:
    volumes:
      - ./Secure_Canal/certs/chat_service/server.crt:/etc/ssl/certs/server.crt:ro
      - ./Secure_Canal/certs/chat_service/server.key:/etc/ssl/private/server.key:ro
```

El API Gateway también necesita la CA para verificar los certificados de los servicios:

```yaml
  api_gateway:
    volumes:
      - ./Secure_Canal/certs/api_gateway/server.crt:/etc/ssl/certs/server.crt:ro
      - ./Secure_Canal/certs/api_gateway/server.key:/etc/ssl/private/server.key:ro
      - ./Secure_Canal/ca/ca.crt:/etc/ssl/certs/ca.crt:ro
```

## 🐳 Configuración en Dockerfile

Para servicios Python (FastAPI/Uvicorn), el Dockerfile debe:

1. **Crear los directorios SSL con permisos correctos:**
```dockerfile
RUN useradd -m -u 1000 serviceuser && \
    mkdir -p /etc/ssl/private /etc/ssl/certs && \
    chown -R serviceuser:serviceuser /app /etc/ssl/private /etc/ssl/certs

USER serviceuser
```

2. **Configurar Uvicorn para usar SSL:**
```dockerfile
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8443", \
     "--ssl-keyfile", "/etc/ssl/private/server.key", \
     "--ssl-certfile", "/etc/ssl/certs/server.crt"]
```

## 🔒 Permisos de Archivos

Los archivos de certificados deben tener permisos de lectura para que los contenedores puedan accederlos:

```bash
# Certificados públicos (644: rw-r--r--)
chmod 644 Secure_Canal/certs/*/server.crt
chmod 644 Secure_Canal/ca/ca.crt

# Llaves privadas (644 para Docker o 600 para mayor seguridad)
chmod 644 Secure_Canal/certs/*/server.key
chmod 600 Secure_Canal/ca/ca.key  # La CA key debe ser más restrictiva
```

## 🔄 Nginx SSL Configuration

El API Gateway (Nginx) debe configurarse para:

### 1. Escuchar en SSL:
```nginx
server {
    listen 443 ssl;
    
    ssl_certificate /etc/ssl/certs/server.crt;
    ssl_certificate_key /etc/ssl/private/server.key;
    
    # Configuración SSL segura
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
}
```

### 2. Proxy SSL a servicios backend:
```nginx
location /api/chat/ {
    proxy_pass https://chat_service:8443;
    
    # Verificar certificados del backend
    proxy_ssl_trusted_certificate /etc/ssl/certs/ca.crt;
    proxy_ssl_verify on;
    proxy_ssl_verify_depth 2;
    proxy_ssl_server_name on;
    proxy_ssl_name chat_service;
}
```

## 🛠️ Generación de Certificados

### 1. Crear la CA (solo una vez):
```bash
# Generar llave privada de la CA
openssl genrsa -out ca/ca.key 4096

# Crear certificado auto-firmado de la CA
openssl req -new -x509 -days 3650 -key ca/ca.key -out ca/ca.crt \
    -subj "/C=CO/ST=Bogota/L=Bogota/O=OwlBoard/OU=IT/CN=OwlBoard CA"
```

### 2. Crear certificado para un servicio:
```bash
SERVICE_NAME="chat_service"

# Generar llave privada del servicio
openssl genrsa -out certs/$SERVICE_NAME/server.key 4096

# Crear Certificate Signing Request (CSR)
openssl req -new -key certs/$SERVICE_NAME/server.key \
    -out certs/$SERVICE_NAME/server.csr \
    -subj "/C=CO/ST=Bogota/L=Bogota/O=OwlBoard/OU=Services/CN=$SERVICE_NAME"

# Crear archivo de configuración de extensiones
cat > certs/$SERVICE_NAME/server.ext.cnf << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $SERVICE_NAME
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

# Firmar el certificado con la CA
openssl x509 -req -in certs/$SERVICE_NAME/server.csr \
    -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
    -out certs/$SERVICE_NAME/server.crt -days 825 \
    -extfile certs/$SERVICE_NAME/server.ext.cnf
```

## 🐛 Troubleshooting

### Error: Permission denied al leer certificados

**Síntoma:** El servicio falla con `PermissionError: [Errno 13] Permission denied`

**Solución:**
1. Verificar permisos de archivos en el host:
   ```bash
   ls -la Secure_Canal/certs/service_name/
   ```

2. Asegurar que el Dockerfile crea los directorios con permisos correctos:
   ```dockerfile
   RUN mkdir -p /etc/ssl/private /etc/ssl/certs && \
       chown -R user:user /etc/ssl/private /etc/ssl/certs
   ```

3. Dar permisos de lectura a los certificados:
   ```bash
   chmod 644 Secure_Canal/certs/*/server.{crt,key}
   ```

### Error: host not found in upstream

**Síntoma:** Nginx no puede encontrar el servicio backend

**Solución:**
1. Asegurar que el servicio está levantado primero
2. Verificar el nombre del servicio en `docker-compose.yml`
3. Reiniciar el API Gateway después de que el servicio esté disponible

### Error: SSL verification failed

**Síntoma:** El proxy no puede verificar el certificado del backend

**Solución:**
1. Verificar que la CA está montada en el API Gateway
2. Verificar configuración de `proxy_ssl_*` en Nginx
3. Asegurar que los certificados fueron firmados por la misma CA

## 🔐 Seguridad

### Buenas Prácticas:
1. **Nunca commitear llaves privadas** (`.gitignore` debe incluir `*.key`)
2. **Rotar certificados** regularmente (antes de expiración)
3. **Usar llaves de al menos 2048 bits** (recomendado: 4096)
4. **Limitar permisos** de las llaves privadas (600 o 644)
5. **Usar TLS 1.2+** solamente, deshabilitar versiones antiguas
6. **Habilitar verificación SSL** en proxies para prevenir MITM

### Archivos que NO deben commitearse:
- `*.key` (llaves privadas)
- `*.csr` (requests de certificados)
- `ca.key` (llave privada de la CA)
- `ca.srl` (serial de la CA)

## 📋 Checklist de Implementación

- [x] Crear estructura de directorios (`ca/`, `certs/`)
- [x] Generar CA raíz
- [x] Generar certificados para cada servicio
- [x] Configurar permisos de archivos (644 para certs)
- [x] Actualizar `docker-compose.yml` con volumes
- [x] Actualizar Dockerfiles con configuración SSL
- [x] Configurar Nginx para SSL en API Gateway
- [x] Configurar proxy SSL para backends
- [x] Agregar `.gitignore` para llaves privadas
- [x] Probar comunicación SSL entre servicios
- [x] Documentar configuración

## 🚀 Verificación

Para verificar que SSL está funcionando:

```bash
# Ver logs del servicio
docker-compose logs chat_service

# Debería mostrar: "Uvicorn running on https://0.0.0.0:8443"

# Probar endpoint SSL
curl -k https://localhost:8002/health

# Ver certificado
openssl s_client -connect localhost:8002 -showcerts
```

## 📚 Referencias
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [Uvicorn SSL Configuration](https://www.uvicorn.org/settings/#https)
- [Nginx SSL Module](http://nginx.org/en/docs/http/ngx_http_ssl_module.html)
