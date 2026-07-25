#!/bin/sh
# ensure-tls-cert.sh — mint a self-signed TLS cert/key for the pi container
# nginx if they don't already exist. Ported from the old cdp-proxy sidecar's
# docker-entrypoint.sh; openssl is now installed at build time (apt), so
# unlike the original this does not attempt to install it at runtime.
set -eu

cert="${TLS_CERT_DIR:-/etc/nginx/certs}/cert.pem"
key="${TLS_CERT_DIR:-/etc/nginx/certs}/key.pem"
public_host="${PUBLIC_HOST:-localhost}"
cert_days="${TLS_CERT_DAYS:-825}"

is_ip() {
  # IPv4 dotted quad or any string containing ':' (IPv6 / host:port-style IP).
  case "$1" in
    *:*) return 0 ;;
  esac
  echo "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

if [ -s "$cert" ] && [ -s "$key" ]; then
  exit 0
fi

echo "ensure-tls-cert: generating self-signed TLS certificate for ${public_host}" >&2

case "$public_host" in
  ''|*[!A-Za-z0-9.:-]*)
    echo "ensure-tls-cert: PUBLIC_HOST must be a DNS name, IPv4, or IPv6 address" >&2
    exit 2
    ;;
esac

case "$cert_days" in
  ''|*[!0-9]*)
    echo "ensure-tls-cert: TLS_CERT_DAYS must be a positive integer" >&2
    exit 2
    ;;
esac
if [ "$cert_days" -lt 1 ]; then
  echo "ensure-tls-cert: TLS_CERT_DAYS must be a positive integer" >&2
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ensure-tls-cert: openssl binary missing (should be baked into the image)" >&2
  exit 127
fi

cert_dir=$(dirname "$cert")
mkdir -p "$cert_dir"
umask 077

if is_ip "$public_host"; then
  san="IP:${public_host}"
else
  san="DNS:${public_host}"
fi

# Write to temp paths then rename so a partial failure never leaves empty
# files that would skip regeneration on the next restart.
tmp_cert="${cert}.tmp"
tmp_key="${key}.tmp"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -days "$cert_days" \
  -keyout "$tmp_key" \
  -out "$tmp_cert" \
  -subj "/CN=${public_host}" \
  -addext "subjectAltName=${san}"
mv "$tmp_key" "$key"
mv "$tmp_cert" "$cert"
echo "ensure-tls-cert: wrote ${cert} and ${key}" >&2
