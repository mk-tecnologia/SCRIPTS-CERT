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
grep -Fq 'subjectAltName = DNS:must-remain.example.test' "$OPENSSL_CONFIG"
openssl req -new -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$REQUEST_FILE"

SAN_OUTPUT=$(openssl req -in "$REQUEST_FILE" -noout -text \
    | awk '/Subject Alternative Name/{getline; gsub(/^ +/, ""); print}')

printf '%s\n' "$SAN_OUTPUT" | grep -Fq "DNS:$CN"
printf '%s\n' "$SAN_OUTPUT" | grep -Fq "DNS:$SHORT_NAME"
printf '%s\n' "$SAN_OUTPUT" | grep -Fq "IP Address:$IP"

# Missing SAN, commented section header, and section at EOF must produce a usable CSR.
for variant in missing commented eof spaced crlf; do
    awk -v variant="$variant" '
        /^subjectAltName = DNS:old/ { next }
        /^\[v3_req\]/ && variant == "commented" { print " [ v3_req ] # request extensions"; next }
        /^\[server_cert\]/ && variant == "eof" { exit }
        { print }
    ' "$REPO_DIR/tests/fixtures/ucs-openssl.cnf" > "$OPENSSL_CONFIG"
    if [ "$variant" = spaced ] || [ "$variant" = crlf ]; then
        sed 's/\[v3_req\]/[ v3_req ]/' "$REPO_DIR/tests/fixtures/ucs-openssl.cnf" > "$OPENSSL_CONFIG"
    fi
    if [ "$variant" = crlf ]; then
        while IFS= read -r line; do printf '%s\r\n' "$line"; done \
            < "$OPENSSL_CONFIG" > "$TEST_ROOT/crlf.cnf"
        cp "$TEST_ROOT/crlf.cnf" "$OPENSSL_CONFIG"
    fi
    # Parsing and rewriting SAN must work even when awk is unavailable.
    awk() { return 99; }
    update_san_config
    unset -f awk
    cp "$OPENSSL_CONFIG" "$TEST_ROOT/updated.cnf"
    update_san_config
    cmp "$TEST_ROOT/updated.cnf" "$OPENSSL_CONFIG"
    if [ "$variant" != "eof" ]; then
        grep -Fq 'subjectAltName = DNS:must-remain.example.test' "$OPENSSL_CONFIG"
    fi
    openssl req -new -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$REQUEST_FILE"
    SAN_OUTPUT=$(openssl req -in "$REQUEST_FILE" -noout -text \
        | awk '/Subject Alternative Name/{getline; gsub(/^ +/, ""); print}')
    printf '%s\n' "$SAN_OUTPUT" | grep -Fxq "DNS:$CN, DNS:$SHORT_NAME, IP Address:$IP"
done

# Ambiguous or missing sections must fail without changing the file.
for variant in no_section duplicate_section duplicate_san; do
    cp "$REPO_DIR/tests/fixtures/ucs-openssl.cnf" "$OPENSSL_CONFIG"
    case "$variant" in
        no_section) sed 's/v3_req/other_extensions/g' "$OPENSSL_CONFIG" > "$TEST_ROOT/invalid.cnf" ;;
        duplicate_section) { cat "$OPENSSL_CONFIG"; printf '\n[v3_req]\n'; } > "$TEST_ROOT/invalid.cnf" ;;
        duplicate_san) sed '/^subjectAltName = DNS:old/a\
subjectAltName = DNS:duplicate.example.test
' "$OPENSSL_CONFIG" > "$TEST_ROOT/invalid.cnf" ;;
    esac
    cp "$TEST_ROOT/invalid.cnf" "$OPENSSL_CONFIG"
    if (trap - EXIT; update_san_config) > "$TEST_ROOT/error.log" 2>&1; then
        error "Configuração inválida aceita: $variant"
    fi
    grep -Fq 'Nenhum arquivo foi alterado.' "$TEST_ROOT/error.log"
    cmp "$TEST_ROOT/invalid.cnf" "$OPENSSL_CONFIG"
done

RUN_COMPLETE="true"
FILES_MODIFIED="false"
success "Teste UCS: configuração SAN e CSR validados"
