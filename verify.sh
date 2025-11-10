#!/bin/bash
# Script para verificar la configuración del Secure Canal

set -e

echo "🔐 Verificando configuración del Secure Canal..."
echo ""

# Colores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para checks
check_success() {
    echo -e "${GREEN}✓${NC} $1"
}

check_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_error() {
    echo -e "${RED}✗${NC} $1"
}

# 1. Verificar estructura de directorios
echo "📁 Verificando estructura de directorios..."
if [ -d "Secure_Channel/ca" ] && [ -d "Secure_Channel/certs" ]; then
    check_success "Estructura de directorios correcta"
else
    check_error "Faltan directorios principales"
    exit 1
fi

# 2. Verificar CA
echo ""
echo "🔑 Verificando Autoridad Certificadora..."
if [ -f "Secure_Channel/ca/ca.crt" ] && [ -f "Secure_Channel/ca/ca.key" ]; then
    check_success "Archivos de CA presentes"
    
    # Verificar validez del certificado
    if openssl x509 -in Secure_Channel/ca/ca.crt -noout -checkend 86400 > /dev/null 2>&1; then
        check_success "Certificado de CA válido"
        
        # Mostrar información del certificado
        expiry=$(openssl x509 -in Secure_Channel/ca/ca.crt -noout -enddate | cut -d= -f2)
        echo "   Expira: $expiry"
    else
        check_error "Certificado de CA expirado o inválido"
    fi
else
    check_error "Faltan archivos de CA"
fi

# 3. Verificar certificados de servicios
echo ""
echo "📜 Verificando certificados de servicios..."
services=("api_gateway" "chat_service" "user_service")

for service in "${services[@]}"; do
    echo ""
    echo "  Servicio: $service"
    
    cert_path="Secure_Channel/certs/$service/server.crt"
    key_path="Secure_Channel/certs/$service/server.key"
    
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        check_success "Archivos presentes"
        
        # Verificar que el certificado fue firmado por nuestra CA
        if openssl verify -CAfile Secure_Channel/ca/ca.crt "$cert_path" > /dev/null 2>&1; then
            check_success "Certificado firmado por CA válida"
        else
            check_error "Certificado no firmado por nuestra CA"
        fi
        
        # Verificar que la llave y certificado coinciden
        cert_modulus=$(openssl x509 -noout -modulus -in "$cert_path" | openssl md5)
        key_modulus=$(openssl rsa -noout -modulus -in "$key_path" 2>/dev/null | openssl md5)
        
        if [ "$cert_modulus" = "$key_modulus" ]; then
            check_success "Certificado y llave coinciden"
        else
            check_error "Certificado y llave NO coinciden"
        fi
        
        # Verificar validez temporal
        if openssl x509 -in "$cert_path" -noout -checkend 86400 > /dev/null 2>&1; then
            check_success "Certificado válido"
            expiry=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
            echo "     Expira: $expiry"
        else
            check_error "Certificado expirado o inválido"
        fi
        
    else
        check_error "Faltan archivos de certificado o llave"
    fi
done

# 4. Verificar permisos de archivos
echo ""
echo "🔒 Verificando permisos de archivos..."

for service in "${services[@]}"; do
    cert_path="Secure_Channel/certs/$service/server.crt"
    key_path="Secure_Channel/certs/$service/server.key"
    
    if [ -f "$cert_path" ]; then
        perms=$(stat -c "%a" "$cert_path")
        if [ "$perms" = "644" ] || [ "$perms" = "444" ]; then
            check_success "$service/server.crt - permisos correctos ($perms)"
        else
            check_warning "$service/server.crt - permisos: $perms (recomendado: 644)"
        fi
    fi
    
    if [ -f "$key_path" ]; then
        perms=$(stat -c "%a" "$key_path")
        if [ "$perms" = "644" ] || [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
            check_success "$service/server.key - permisos correctos ($perms)"
        else
            check_warning "$service/server.key - permisos: $perms (recomendado: 644 o 600)"
        fi
    fi
done

# 5. Verificar configuración en docker-compose.yml
echo ""
echo "🐳 Verificando configuración de Docker Compose..."

if grep -q "Secure_Channel/certs/chat_service/server.crt" docker-compose.yml && \
   grep -q "Secure_Channel/certs/user_service/server.crt" docker-compose.yml && \
   grep -q "Secure_Channel/certs/api_gateway/server.crt" docker-compose.yml; then
    check_success "Volúmenes configurados en docker-compose.yml"
else
    check_error "Faltan volúmenes en docker-compose.yml"
fi

# 6. Verificar servicios en ejecución (si Docker está corriendo)
echo ""
echo "🚀 Verificando servicios en ejecución..."

if command -v docker-compose &> /dev/null; then
    if docker-compose ps | grep -q "chat_service.*Up"; then
        check_success "Chat Service en ejecución"
        
        # Verificar que está usando SSL
        if docker-compose logs chat_service 2>&1 | grep -q "https://0.0.0.0:8443"; then
            check_success "Chat Service usando SSL (puerto 8443)"
        else
            check_warning "Chat Service podría no estar usando SSL"
        fi
    else
        check_warning "Chat Service no está en ejecución"
    fi
    
    if docker-compose ps | grep -q "user_service.*Up"; then
        check_success "User Service en ejecución"
    else
        check_warning "User Service no está en ejecución"
    fi
    
    if docker-compose ps | grep -q "api_gateway.*Up"; then
        check_success "API Gateway en ejecución"
    else
        check_warning "API Gateway no está en ejecución"
    fi
else
    check_warning "docker-compose no disponible, omitiendo verificación de servicios"
fi

# 7. Resumen
echo ""
echo "════════════════════════════════════════════════"
echo "✅ Verificación completada"
echo "════════════════════════════════════════════════"
echo ""
echo "Para probar la comunicación SSL:"
echo "  curl -k https://localhost:8002/health"
echo ""
echo "Para ver detalles del certificado:"
echo "  openssl x509 -in Secure_Channel/certs/chat_service/server.crt -text -noout"
echo ""
