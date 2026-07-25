#!/usr/bin/env bash
# Optional host-side helper: mint data/proxy/{cert,key}.pem without starting Docker.
# app also auto-generates these on first boot when they are missing.

set -euo pipefail

public_host="${PUBLIC_HOST:-localhost}"
cert_days="${TLS_CERT_DAYS:-825}"
cert_dir="${TLS_CERT_DIR:-data/proxy}"
cert="${cert_dir}/cert.pem"
key="${cert_dir}/key.pem"

if ! [[ "$public_host" =~ ^[A-Za-z0-9.:-]+$ ]]; then
  echo "PUBLIC_HOST must be a DNS name, IPv4 address, or IPv6 address" >&2
  exit 2
fi

if ! [[ "$cert_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "TLS_CERT_DAYS must be a positive integer" >&2
  exit 2
fi

if [[ -e "$cert" || -e "$key" ]] && [[ "${FORCE:-0}" != "1" ]]; then
  echo "TLS certificate already exists in ${cert_dir}; use FORCE=1 to replace it." >&2
  exit 0
fi

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required to generate the proxy certificate" >&2
  exit 127
}

mkdir -p "$cert_dir"
umask 077

if [[ "$public_host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$public_host" == *:* ]]; then
  subject_alt_name="IP:${public_host}"
else
  subject_alt_name="DNS:${public_host}"
fi

openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -days "$cert_days" \
  -keyout "$key" \
  -out "$cert" \
  -subj "/CN=${public_host}" \
  -config <(
    cat <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_req

[dn]

[v3_req]
subjectAltName = ${subject_alt_name}
EOF
  )

echo "Generated ${cert} and ${key} for ${public_host}."
