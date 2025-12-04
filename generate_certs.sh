#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CA_DIR="$ROOT_DIR/ca"
CERTS_DIR="$ROOT_DIR/certs"
SERVICES=(api_gateway chat_service user_service reverse_proxy load_balancer auth_service)

echo "== Generating/refreshing certificates in $ROOT_DIR =="

# Ensure directories
mkdir -p "$CA_DIR" "$CERTS_DIR"

# 1) Create CA if not present
if [ ! -f "$CA_DIR/ca.key" ] || [ ! -f "$CA_DIR/ca.crt" ]; then
  echo "* Creating CA (ca.key / ca.crt)..."
  openssl genrsa -out "$CA_DIR/ca.key" 4096
  openssl req -new -x509 -days 3650 -key "$CA_DIR/ca.key" -out "$CA_DIR/ca.crt" -subj "/C=CO/ST=Bogota/L=Bogota/O=OwlBoard/OU=IT/CN=OwlBoardInternalCA"
  chmod 600 "$CA_DIR/ca.key"
  chmod 644 "$CA_DIR/ca.crt"
else
  echo "* CA already exists, skipping CA creation"
fi

# 2) For each service, generate key, CSR and certificate if missing or forced
for svc in "${SERVICES[@]}"; do
  svc_dir="$CERTS_DIR/$svc"
  mkdir -p "$svc_dir"

  key="$svc_dir/server.key"
  csr="$svc_dir/server.csr"
  crt="$svc_dir/server.crt"
  extcnf="$svc_dir/server.ext.cnf"

  echo "\n-- Service: $svc --"

  if [ ! -f "$key" ]; then
    echo "  - Generating private key: $key"
    openssl genrsa -out "$key" 4096
    chmod 600 "$key"
  else
    echo "  - Key exists, skipping"
  fi

  if [ ! -f "$csr" ]; then
    echo "  - Creating CSR: $csr"
    # If extcnf exists, use commonName from it by not prompting
    openssl req -new -key "$key" -out "$csr" -subj "/C=CO/ST=Bogota/L=Bogota/O=OwlBoard/OU=Services/CN=$svc"
  else
    echo "  - CSR exists, skipping"
  fi

  if [ ! -f "$extcnf" ]; then
    echo "  - Creating default ext cnf: $extcnf"
    cat > "$extcnf" <<EOF
[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
req_extensions      = v3_req
prompt              = no

[ req_distinguished_name ]
countryName                 = CO
stateOrProvinceName         = Bogota
localityName                = Bogota
organizationName            = OwlBoard
commonName                  = $svc

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $svc
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF
  else
    echo "  - Extfile exists, using: $extcnf"
  fi

  echo "  - Signing certificate (server.crt) with CA"
  openssl x509 -req -in "$csr" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial -out "$crt" -days 825 -sha256 -extfile "$extcnf" -extensions v3_req
  chmod 644 "$crt"
  echo "  - Generated: $crt"
done

echo "\nAll done. Certificates are in: $CERTS_DIR"

exit 0
