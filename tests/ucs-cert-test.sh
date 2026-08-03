#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "/tmp/ucs-cert-test_XXXXXX")

cleanup_test() {
    [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    rm -rf "$TEST_ROOT"
}

# shellcheck source=../ucs-cert.sh
source "$REPO_DIR/ucs-cert.sh"
trap cleanup_test EXIT

CERT_DIR="$TEST_ROOT/cert"
mkdir -p "$CERT_DIR"
OPENSSL_CONFIG="$CERT_DIR/openssl.cnf"
KEY_FILE="$CERT_DIR/private.key"
REQUEST_FILE="$CERT_DIR/req.pem"
CERT_FILE="$CERT_DIR/cert.pem"
BACKUP_DIR="$TEST_ROOT/backups"
CN="mkserver.cdl.intranet"
SHORT_NAME="mkserver"
IP="192.168.110.2"

cp "$REPO_DIR/tests/fixtures/ucs-openssl.cnf" "$OPENSSL_CONFIG"
openssl genrsa -out "$KEY_FILE" 2048 >/dev/null 2>&1
openssl req -new -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$REQUEST_FILE"
openssl req -x509 -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$CERT_FILE" -days 1

mkdir -p "$TEST_ROOT/expected"
cp "$OPENSSL_CONFIG" "$REQUEST_FILE" "$CERT_FILE" "$KEY_FILE" "$TEST_ROOT/expected/"

backup_current
update_san_config
restore_backup

cmp "$TEST_ROOT/expected/openssl.cnf" "$OPENSSL_CONFIG"
cmp "$TEST_ROOT/expected/req.pem" "$REQUEST_FILE"
cmp "$TEST_ROOT/expected/cert.pem" "$CERT_FILE"
cmp "$TEST_ROOT/expected/private.key" "$KEY_FILE"

update_san_config
openssl req -new -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$REQUEST_FILE"

SAN_OUTPUT=$(openssl req -in "$REQUEST_FILE" -noout -text \
    | awk '/Subject Alternative Name/{getline; gsub(/^ +/, ""); print}')

printf '%s\n' "$SAN_OUTPUT" | grep -Fq "DNS:$CN"
printf '%s\n' "$SAN_OUTPUT" | grep -Fq "DNS:$SHORT_NAME"
printf '%s\n' "$SAN_OUTPUT" | grep -Fq "IP Address:$IP"

RUN_COMPLETE="true"
FILES_MODIFIED="false"
success "Teste UCS: configuração SAN e CSR validados"
