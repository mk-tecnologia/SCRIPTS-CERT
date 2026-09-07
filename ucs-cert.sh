#!/usr/bin/env bash
# =============================================================================
# ucs-cert.sh — Corrigir/renovar certificado TLS de host no Univention UCS
# Versão  : consulte APP_VERSION abaixo ou execute --version
# Autor   : Marcos A. Campos <marcos@mktecnologia.net.br>
# Suporte : Univention Corporate Server — Primary Directory Node/DC Master
# Licença : MIT
# =============================================================================

set -euo pipefail

APP_NAME="ucs-cert"
APP_VERSION="2.5.3"
APP_RELEASE_DATE="2026-09-07"
DEFAULT_PORT="443"
DEFAULT_MAX_DAYS="3650"
LOG_DIR="/var/log/${APP_NAME}"
BACKUP_DIR="/var/backups/${APP_NAME}"

if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()    { printf "%bℹ️  %s%b\n" "$CYAN" "$*" "$NC"; }
success() { printf "%b✅ %s%b\n" "$GREEN" "$*" "$NC"; }
warn()    { printf "%b⚠️  %s%b\n" "$YELLOW" "$*" "$NC"; }
error()   { printf "%b❌ %s%b\n" "$RED" "$*" "$NC" >&2; exit 1; }
step()    { printf "\n%b── %s%b\n" "$BOLD" "$*" "$NC"; }

CN=""
SHORT_NAME=""
IP=""
PORT="$DEFAULT_PORT"
CERT_VALIDITY=""
ASSUME_YES="false"
VERBOSE="false"
CERT_DIR=""
OPENSSL_CONFIG=""
CERT_FILE=""
KEY_FILE=""
REQUEST_FILE=""
BACKUP_TARGET=""
WORK_DIR=""
FILES_MODIFIED="false"
RUN_COMPLETE="false"

usage() {
    cat <<EOF
${APP_NAME} v${APP_VERSION}
Adiciona nome/IP ao SAN e renova o certificado de host pela CA interna do UCS.

Uso:
  ${APP_NAME} [opções]

Opções:
  --cn FQDN          FQDN do host UCS (padrão: hostname -f)
  --short NOME       Nome curto no SAN (padrão: hostname -s)
  --ip IP            IPv4 que deve constar no SAN
  --port PORTA       Porta HTTPS verificada (padrão: 443)
  --days DIAS        Validade; padrão obtido de ssl/default/days
  -y, --yes          Executa sem confirmação
  -v, --verbose      Mostra os comandos executados
  -h, --help         Exibe esta ajuda
  --version          Exibe versão e data

Exemplo:
  sudo ${APP_NAME} --cn mkserver.cdl.intranet --short mkserver --ip 192.168.110.2
EOF
}

run_cmd() {
    if [ "$VERBOSE" = "true" ]; then
        printf "%b+" "$CYAN"
        printf " %q" "$@"
        printf "%b\n" "$NC"
    fi
    "$@"
}

log_msg() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$APP_NAME" "$*" \
        >> "$LOG_DIR/${APP_NAME}.log" 2>/dev/null || true
}

restore_backup() {
    [ "$FILES_MODIFIED" = "true" ] || return 0
    [ -n "$BACKUP_TARGET" ] && [ -d "$BACKUP_TARGET" ] || return 0

    warn "Restaurando os arquivos anteriores do certificado UCS."
    cp -a "$BACKUP_TARGET/openssl.cnf" "$OPENSSL_CONFIG" 2>/dev/null || true
    cp -a "$BACKUP_TARGET/req.pem" "$REQUEST_FILE" 2>/dev/null || true
    cp -a "$BACKUP_TARGET/cert.pem" "$CERT_FILE" 2>/dev/null || true
    systemctl reload apache2 >/dev/null 2>&1 || true
    FILES_MODIFIED="false"
}

cleanup() {
    local exit_code=$?
    if [ "$RUN_COMPLETE" != "true" ]; then
        restore_backup
    fi
    [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    return "$exit_code"
}

on_interrupt() {
    echo ""
    warn "Operação interrompida; iniciando recuperação."
    exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

require_root() {
    [ "${EUID:-$(id -u)}" -eq 0 ] || error "Execute como root: sudo $0"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || error "Comando obrigatório não encontrado: $1"
}

check_dependencies() {
    local command=""
    for command in openssl univention-certificate ucr systemctl hostname grep sed awk cut tr mktemp seq sleep; do
        require_cmd "$command"
    done
    [ -r /usr/share/univention-ssl/make-certificates.sh ] \
        || error "Arquivo UCS não encontrado: /usr/share/univention-ssl/make-certificates.sh"
}

validate_ip() {
    local ip="$1" octet="" IFS='.'
    local octets=()
    read -r -a octets <<< "$ip"
    [ "${#octets[@]}" -eq 4 ] || error "IPv4 inválido: $ip"
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || error "IPv4 inválido: $ip"
        [ "$octet" -ge 0 ] 2>/dev/null && [ "$octet" -le 255 ] 2>/dev/null \
            || error "IPv4 inválido: $ip"
    done
}

validate_hostname() {
    local host="$1" label="" IFS='.'
    local labels=()
    [ -n "$host" ] || error "Hostname não pode ficar vazio."
    [ "${#host}" -le 253 ] || error "Hostname muito longo: $host"
    case "$host" in *..*|.*|*.) error "Hostname inválido: $host" ;; esac
    read -r -a labels <<< "$host"
    for label in "${labels[@]}"; do
        [ -n "$label" ] || error "Hostname inválido: $host"
        [ "${#label}" -le 63 ] || error "Label muito longo: $label"
        printf "%s" "$label" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$' \
            || error "Hostname inválido: $host"
    done
}

validate_number() {
    local value="$1" name="$2" maximum="$3"
    printf "%s" "$value" | grep -Eq '^[0-9]+$' || error "$name inválido: $value"
    [ "$value" -ge 1 ] 2>/dev/null && [ "$value" -le "$maximum" ] 2>/dev/null \
        || error "$name deve ficar entre 1 e $maximum: $value"
}

confirm_or_exit() {
    local message="$1" answer=""
    [ "$ASSUME_YES" = "true" ] && return 0
    read -r -p "$message [s/N]: " answer
    case "$answer" in s|S|sim|SIM|Sim) return 0 ;; *) warn "Cancelado."; exit 0 ;; esac
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --cn) [ "$#" -ge 2 ] || error "Faltou valor para --cn"; CN="$2"; shift 2 ;;
            --short) [ "$#" -ge 2 ] || error "Faltou valor para --short"; SHORT_NAME="$2"; shift 2 ;;
            --ip) [ "$#" -ge 2 ] || error "Faltou valor para --ip"; IP="$2"; shift 2 ;;
            --port) [ "$#" -ge 2 ] || error "Faltou valor para --port"; PORT="$2"; shift 2 ;;
            --days) [ "$#" -ge 2 ] || error "Faltou valor para --days"; CERT_VALIDITY="$2"; shift 2 ;;
            -y|--yes) ASSUME_YES="true"; shift ;;
            -v|--verbose) VERBOSE="true"; shift ;;
            -h|--help) usage; exit 0 ;;
            --version) echo "${APP_NAME} ${APP_VERSION} (${APP_RELEASE_DATE})"; exit 0 ;;
            *) error "Opção desconhecida: $1" ;;
        esac
    done
}

print_header() {
    echo ""
    printf "%b╔══════════════════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║     ucs-cert — Certificado de host Univention        ║%b\n" "$BOLD" "$NC"
    printf "%b║     Versão: %-10sData: %-10s               ║%b\n" "$BOLD" "v${APP_VERSION}" "$APP_RELEASE_DATE" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo ""
}

check_ucs_role() {
    local role=""
    role=$(ucr get server/role)
    case "$role" in
        domaincontroller_master|primary_directory_node)
            success "Papel UCS compatível: $role"
            ;;
        *)
            error "Este procedimento deve rodar no Primary Directory Node/DC Master. Papel atual: ${role:-desconhecido}"
            ;;
    esac
}

collect_config() {
    local default_cn="" default_short="" default_ip="" default_days=""
    default_cn=$(hostname -f)
    default_short=$(hostname -s)
    default_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    default_days=$(ucr get ssl/default/days)
    default_days="${default_days:-1825}"

    [ -n "$CN" ] || { read -r -p "FQDN do UCS [$default_cn]: " CN; CN="${CN:-$default_cn}"; }
    [ -n "$SHORT_NAME" ] || { read -r -p "Nome curto [$default_short]: " SHORT_NAME; SHORT_NAME="${SHORT_NAME:-$default_short}"; }
    [ -n "$IP" ] || { read -r -p "IPv4 do UCS [$default_ip]: " IP; IP="${IP:-$default_ip}"; }
    CERT_VALIDITY="${CERT_VALIDITY:-$default_days}"

    validate_hostname "$CN"
    validate_hostname "$SHORT_NAME"
    validate_ip "$IP"
    validate_number "$PORT" "Porta" "65535"
    validate_number "$CERT_VALIDITY" "Validade" "$DEFAULT_MAX_DAYS"

    CERT_DIR="/etc/univention/ssl/$CN"
    OPENSSL_CONFIG="$CERT_DIR/openssl.cnf"
    CERT_FILE="$CERT_DIR/cert.pem"
    KEY_FILE="$CERT_DIR/private.key"
    REQUEST_FILE="$CERT_DIR/req.pem"

    [ -d "$CERT_DIR" ] || error "Diretório do certificado não encontrado: $CERT_DIR"
    [ -f "$OPENSSL_CONFIG" ] || error "Configuração não encontrada: $OPENSSL_CONFIG"
    [ -f "$CERT_FILE" ] || error "Certificado não encontrado: $CERT_FILE"
    [ -f "$KEY_FILE" ] || error "Chave privada não encontrada: $KEY_FILE"
    [ -f "$REQUEST_FILE" ] || error "CSR não encontrado: $REQUEST_FILE"

    echo "  FQDN      : $CN"
    echo "  Nome curto: $SHORT_NAME"
    echo "  IPv4      : $IP"
    echo "  Porta     : $PORT"
    echo "  Validade  : $CERT_VALIDITY dias"
    echo "  Diretório : $CERT_DIR"
    echo "  Novo SAN  : DNS:$CN, DNS:$SHORT_NAME, IP:$IP"
    echo ""
    confirm_or_exit "Confirmar backup, renovação e aplicação?"
}

validate_existing_material() {
    local cert_pubkey="" key_pubkey=""
    step "Validando certificado e chave existentes"
    openssl x509 -in "$CERT_FILE" -noout >/dev/null 2>&1 || error "Certificado atual inválido: $CERT_FILE"
    openssl pkey -in "$KEY_FILE" -noout >/dev/null 2>&1 || error "Chave privada atual inválida: $KEY_FILE"
    cert_pubkey=$(openssl x509 -in "$CERT_FILE" -pubkey -noout | openssl sha256)
    key_pubkey=$(openssl pkey -in "$KEY_FILE" -pubout | openssl sha256)
    [ "$cert_pubkey" = "$key_pubkey" ] || error "A chave privada não corresponde ao certificado atual."
    success "Certificado e chave correspondem"
}

backup_current() {
    local stamp=""
    step "Criando backup"
    stamp=$(date +%Y%m%d%H%M%S)
    mkdir -p "$BACKUP_DIR"
    BACKUP_TARGET=$(mktemp -d "$BACKUP_DIR/$stamp-XXXXXX")
    cp -a "$OPENSSL_CONFIG" "$BACKUP_TARGET/openssl.cnf"
    cp -a "$REQUEST_FILE" "$BACKUP_TARGET/req.pem"
    cp -a "$CERT_FILE" "$BACKUP_TARGET/cert.pem"
    cp -a "$KEY_FILE" "$BACKUP_TARGET/private.key"
    success "Backup salvo em: $BACKUP_TARGET"
}

update_san_config() {
    local config_counts="" section_count="" san_count="" generated_config=""
    step "Atualizando SAN no openssl.cnf"
    config_counts=$(awk '
        /^[[:space:]]*\[[[:space:]]*v3_req[[:space:]]*\][[:space:]]*(#.*)?$/ { in_v3_req = 1; sections++; next }
        /^[[:space:]]*\[/ { in_v3_req = 0 }
        in_v3_req && /^[[:space:]]*subjectAltName[[:space:]]*=/ { count++ }
        END { print sections + 0, count + 0 }
    ' "$OPENSSL_CONFIG")
    read -r section_count san_count <<< "$config_counts"
    [ "$section_count" -eq 1 ] \
        || error "Esperava exatamente uma seção [v3_req] em $OPENSSL_CONFIG; encontrei $section_count. Nenhum arquivo foi alterado."
    [ "$san_count" -le 1 ] \
        || error "Encontrei $san_count linhas subjectAltName na seção [v3_req] de $OPENSSL_CONFIG. Nenhum arquivo foi alterado."

    [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    WORK_DIR=$(mktemp -d "/tmp/${APP_NAME}_XXXXXX")
    generated_config="$WORK_DIR/openssl.cnf"
    awk -v san="subjectAltName = DNS:${CN}, DNS:${SHORT_NAME}, IP:${IP}" -v san_count="$san_count" '
        /^[[:space:]]*\[[[:space:]]*v3_req[[:space:]]*\][[:space:]]*(#.*)?$/ {
            in_v3_req = 1
            print
            if (san_count == 0) print san
            next
        }
        /^[[:space:]]*\[/ { in_v3_req = 0 }
        in_v3_req && /^[[:space:]]*subjectAltName[[:space:]]*=/ { print san; next }
        { print }
    ' "$OPENSSL_CONFIG" > "$generated_config"

    FILES_MODIFIED="true"
    run_cmd cp "$generated_config" "$OPENSSL_CONFIG"
    grep -Fq "subjectAltName = DNS:${CN}, DNS:${SHORT_NAME}, IP:${IP}" "$OPENSSL_CONFIG" \
        || error "Não consegui confirmar a nova configuração SAN."
    success "SAN configurado: DNS:$CN, DNS:$SHORT_NAME, IP:$IP"
}

rebuild_request() {
    step "Recriando CSR com a chave existente"
    set +u
    # shellcheck disable=SC1091
    . /usr/share/univention-ssl/make-certificates.sh
    set -u
    run_cmd openssl req -new -key "$KEY_FILE" -config "$OPENSSL_CONFIG" -out "$REQUEST_FILE"
    openssl req -in "$REQUEST_FILE" -noout -verify >/dev/null 2>&1 \
        || error "O CSR gerado é inválido."
    openssl req -in "$REQUEST_FILE" -noout -text \
        | grep -A1 'Subject Alternative Name' || error "O CSR não contém SAN."
    success "CSR recriado e validado"
}

renew_certificate() {
    step "Renovando pela CA interna do UCS"
    run_cmd univention-certificate renew -name "$CN" -days "$CERT_VALIDITY"
    [ -s "$CERT_FILE" ] || error "O UCS não gerou o certificado esperado: $CERT_FILE"
}

verify_new_certificate() {
    local cert_pubkey="" key_pubkey=""
    step "Validando certificado renovado"
    openssl x509 -in "$CERT_FILE" -noout -checkhost "$CN" >/dev/null \
        || error "O certificado renovado não contém DNS:$CN."
    openssl x509 -in "$CERT_FILE" -noout -checkhost "$SHORT_NAME" >/dev/null \
        || error "O certificado renovado não contém DNS:$SHORT_NAME."
    openssl x509 -in "$CERT_FILE" -noout -checkip "$IP" >/dev/null \
        || error "O certificado renovado não contém IP:$IP."
    cert_pubkey=$(openssl x509 -in "$CERT_FILE" -pubkey -noout | openssl sha256)
    key_pubkey=$(openssl pkey -in "$KEY_FILE" -pubout | openssl sha256)
    [ "$cert_pubkey" = "$key_pubkey" ] || error "A chave deixou de corresponder ao certificado renovado."
    run_cmd univention-certificate check -name "$CN"
    success "Certificado, SANs e chave validados"
}

activate_and_verify() {
    local expected="" served="" attempt=""
    step "Recarregando Apache e verificando a porta $PORT"
    run_cmd systemctl reload apache2 || error "Falha ao recarregar o Apache."
    expected=$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')
    for attempt in $(seq 1 15); do
        if systemctl is-active --quiet apache2; then
            served=$(openssl s_client -connect "$IP:$PORT" -servername "$CN" </dev/null 2>/dev/null \
                | openssl x509 -noout -fingerprint -sha256 2>/dev/null \
                | cut -d= -f2 | tr -d ':') || true
            if [ -n "$served" ] && [ "$served" = "$expected" ]; then
                success "Apache está servindo o novo fingerprint SHA-256: $served"
                return 0
            fi
        fi
        sleep 1
    done
    error "O certificado servido em $IP:$PORT não corresponde ao certificado renovado."
}

final_summary() {
    local fingerprint=""
    fingerprint=$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 | cut -d= -f2)
    echo ""
    printf "%b╔══════════════════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║       ✅ Certificado UCS renovado e verificado        ║%b\n" "$BOLD" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo "  Certificado: $CERT_FILE"
    echo "  SAN        : DNS:$CN, DNS:$SHORT_NAME, IP:$IP"
    echo "  SHA-256    : $fingerprint"
    echo "  Backup     : $BACKUP_TARGET"
    echo "  Log        : $LOG_DIR/${APP_NAME}.log"
    echo ""
    echo "No Mac, confie preferencialmente na CA raiz do domínio UCS:"
    echo "  /etc/univention/ssl/ucsCA/CAcert.pem"
}

main() {
    parse_args "$@"
    print_header
    require_root
    check_dependencies
    check_ucs_role
    collect_config
    validate_existing_material
    backup_current
    update_san_config
    rebuild_request
    renew_certificate
    verify_new_certificate
    activate_and_verify
    log_msg "RENEWED cn=$CN short=$SHORT_NAME ip=$IP port=$PORT days=$CERT_VALIDITY backup=$BACKUP_TARGET"
    RUN_COMPLETE="true"
    FILES_MODIFIED="false"
    final_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
