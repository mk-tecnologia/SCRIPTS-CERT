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

# Primary and Backup roles, discovery, and refusal of non-authoritative issuers.
ucr() {
    case "$2" in
        server/role) printf '%s\n' "$TEST_ROLE" ;;
        ldap/master) echo primary.example.test ;;
    esac
}
for TEST_ROLE in domaincontroller_master primary_directory_node domaincontroller_backup backup_directory_node; do
    PRIMARY=""
    check_ucs_role
    if [[ "$TEST_ROLE" == *backup* ]]; then
        [ "$PRIMARY" = primary.example.test ]
    fi
done
for TEST_ROLE in memberserver domaincontroller_slave unknown; do
    if (trap - EXIT; check_ucs_role) > "$TEST_ROOT/error.log" 2>&1; then
        error "Papel indevido aceito: $TEST_ROLE"
    fi
done
TEST_ROLE=domaincontroller_backup
if (trap - EXIT; ISSUE_ONLY=true; check_ucs_role) > "$TEST_ROOT/error.log" 2>&1; then
    error "Backup aceito como emissor"
fi
unset -f ucr

# Discovery validates the entire inventory before any renewal begins.
python3() { printf '%s\n' "$INVENTORY"; return "${DISCOVERY_RESULT:-0}"; }
INVENTORY=$'srv-ad-bkp\tsrv-ad-bkp\t192.168.170.18,192.168.170.19'
discover_backups
[ "${#BACKUP_NODES[@]}" -eq 1 ]
INVENTORY=""
discover_backups
[ "${#BACKUP_NODES[@]}" -eq 0 ]
renew_backups
INVENTORY=$'bad/host\tbad\t192.168.170.18'
if (trap - EXIT; discover_backups) > "$TEST_ROOT/error.log" 2>&1; then
    error "Hostname inseguro aceito no LDAP"
fi
DISCOVERY_RESULT=1
if (trap - EXIT; discover_backups) > "$TEST_ROOT/error.log" 2>&1; then
    error "Falha LDAP ignorada"
fi
unset -f python3

# Multiple IPs must survive CSR creation and real certificate verification.
cp "$REPO_DIR/tests/fixtures/ucs-openssl.cnf" "$OPENSSL_CONFIG"
IP="192.168.170.18,192.168.170.19"
validate_ip "$IP"
update_san_config
openssl req -new -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$REQUEST_FILE"
openssl req -x509 -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -extensions v3_req -out "$CERT_FILE" -days 1
CA_FILE="$CERT_FILE"
univention-certificate() { return 0; }
verify_new_certificate
if (trap - EXIT; IP=192.168.170.20; verify_new_certificate) > "$TEST_ROOT/error.log" 2>&1; then
    error "SAN sem o IP solicitado aceito"
fi
unset -f univention-certificate

# Child failures do not stop subsequent backups; pending activation is explicit.
BACKUP_NODES=($'bad.example.test\tbad\t192.168.170.18' $'good.example.test\tgood\t192.168.170.19')
bash() {
    printf '%s\n' "$*" >> "$TEST_ROOT/issued"
    [[ "$*" != *bad.example.test* ]]
}
openssl() { echo 'sha256 Fingerprint=AA:BB'; }
served_fingerprint() { echo AA:BB; }
if renew_backups > "$TEST_ROOT/batch.log"; then
    error "Falha de emissão não reportada"
fi
grep -Fq 'good.example.test' "$TEST_ROOT/issued"
grep -Fq 'certificado servido confirmado' "$TEST_ROOT/batch.log"
BACKUP_NODES=($'good.example.test\tgood\t192.168.170.19')
served_fingerprint() { return 1; }
renew_backups > "$TEST_ROOT/batch.log"
grep -Fq 'sincronização/ativação ainda não confirmada' "$TEST_ROOT/batch.log"
unset -f bash openssl served_fingerprint

# Remote rollback must not reload the Primary Apache.
systemctl() { echo called > "$TEST_ROOT/reloaded"; }
ISSUE_ONLY=true
FILES_MODIFIED=true
restore_backup
[ ! -e "$TEST_ROOT/reloaded" ]
unset -f systemctl
ISSUE_ONLY=false

RUN_COMPLETE="true"
FILES_MODIFIED="false"
success "Teste UCS: SAN, CSR, papéis e descoberta LDAP e emissão em lote validados"
