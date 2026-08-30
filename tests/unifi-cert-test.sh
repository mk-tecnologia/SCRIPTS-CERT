#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "/tmp/unifi-cert-test_XXXXXX")

# shellcheck source=../unifi-cert.sh
source "$PROJECT_ROOT/unifi-cert.sh"
trap 'rm -rf "$TEST_ROOT"' EXIT

(
    PLATFORM="auto"
    systemctl() {
        [ "$*" = "show --property=LoadState --value uosserver.service" ] && printf 'loaded\n'
    }
    detect_platform
    [ "$PLATFORM" = "unifios-server" ]
)

(
    PLATFORM="unifios-server"
    require_cmd() {
        [ "$1" != "keytool" ] || error "keytool não deve ser exigido no UniFi OS Server"
        return 0
    }
    check_dependencies
)

PLATFORM="unifios-server"
CA_DIR="$TEST_ROOT/ca"
BACKUP_DIR="$TEST_ROOT/backups"
UOS_CONFIG_DIR="$TEST_ROOT/uosserver-data/unifi-core/config"
UOS_CERT_FILE="$UOS_CONFIG_DIR/unifi-core.crt"
UOS_KEY_FILE="$UOS_CONFIG_DIR/unifi-core.key"
CN="unifi.lab.local"
SHORT_NAME="unifi"
IP="10.0.1.30"
ASSUME_YES="true"

backup_current
create_or_reuse_ca
create_server_certificate
verify_server_certificate
mkdir -p "$UOS_CONFIG_DIR"

# O usuário/grupo uosserver só existe no host de produção.
run_cmd() {
    [ "$1" = "chown" ] && return 0
    "$@"
}
install_unifios_server_certificate

openssl verify -CAfile "$CA_DIR/ca.crt" "$UOS_CERT_FILE" >/dev/null
openssl x509 -in "$UOS_CERT_FILE" -noout -checkhost "$CN" >/dev/null
openssl x509 -in "$UOS_CERT_FILE" -noout -checkhost "$SHORT_NAME" >/dev/null
openssl x509 -in "$UOS_CERT_FILE" -noout -checkip "$IP" >/dev/null
openssl pkey -in "$UOS_KEY_FILE" -noout >/dev/null
cmp "$WORK_DIR/server.key" "$UOS_KEY_FILE"

RUN_COMPLETE="true"
success "Teste UniFi OS Server: instalação, certificado, chave e cadeia validados"
