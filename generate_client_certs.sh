#!/bin/bash

# Script to generate client certificates for API Gateway to use with mTLS

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CA_DIR="${SCRIPT_DIR}/ca"
CERTS_DIR="${SCRIPT_DIR}/certs/api_gateway"

echo "====== Generating Client Certificates for mTLS ======"
echo ""

# Check if CA exists
if [ ! -f "${CA_DIR}/ca.crt" ] || [ ! -f "${CA_DIR}/ca.key" ]; then
    echo "❌ Error: CA certificate not found. Please run generate_certs.sh first."
    exit 1
fi

echo "📁 Using CA from: ${CA_DIR}"
echo "📁 Output directory: ${CERTS_DIR}"
echo ""

# Generate client private key
echo "🔑 Generating client private key..."
openssl genrsa -out "${CERTS_DIR}/client.key" 4096

# Generate client certificate signing request
echo "📝 Generating client CSR..."
openssl req -new -key "${CERTS_DIR}/client.key" \
    -out "${CERTS_DIR}/client.csr" \
    -subj "/C=CO/ST=Bogota/L=Bogota/O=OwlBoard/CN=api_gateway_client"

# Create client certificate extensions file
cat > "${CERTS_DIR}/client.ext.cnf" << EOF
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = api_gateway
DNS.2 = localhost
EOF

# Sign client certificate with CA
echo "✍️  Signing client certificate..."
openssl x509 -req \
    -in "${CERTS_DIR}/client.csr" \
    -CA "${CA_DIR}/ca.crt" \
    -CAkey "${CA_DIR}/ca.key" \
    -CAcreateserial \
    -out "${CERTS_DIR}/client.crt" \
    -days 365 \
    -sha256 \
    -extfile "${CERTS_DIR}/client.ext.cnf"

# Set proper permissions
chmod 600 "${CERTS_DIR}/client.key"
chmod 644 "${CERTS_DIR}/client.crt"

echo ""
echo "✅ Client certificates generated successfully!"
echo ""
echo "📋 Generated files:"
echo "   - ${CERTS_DIR}/client.key (private key)"
echo "   - ${CERTS_DIR}/client.crt (certificate)"
echo "   - ${CERTS_DIR}/client.csr (CSR)"
echo ""
echo "🔍 Verifying client certificate..."
openssl verify -CAfile "${CA_DIR}/ca.crt" "${CERTS_DIR}/client.crt"
echo ""
echo "✅ All done! Client certificates are ready for mTLS."
