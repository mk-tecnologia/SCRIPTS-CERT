#!/usr/bin/env bash
# =============================================================================
# trust-cert.sh — Importar/remover certificado SSL/TLS como confiável
# Versão  : consulte APP_VERSION abaixo ou execute --version
# Autor   : Marcos A. Campos <marcos@mktecnologia.net.br>
# Suporte : macOS e Linux (Debian/Ubuntu/RHEL/Fedora/Arch)
# Licença : MIT
# Dica    : Use Linux :)
# =============================================================================

set -euo pipefail

# ── Metadados ────────────────────────────────────────────────────────────────
APP_NAME="trust-cert"
APP_VERSION="2.4.0"
APP_RELEASE_DATE="2026-08-30"
DEFAULT_PORT="443"
LOG_DIR="${HOME}/.local/state/trust-cert"
BACKUP_DIR="${HOME}/.local/share/trust-cert/certs"
INDEX_FILE="${HOME}/.local/share/trust-cert/index.tsv"
SYSTEM_KEYCHAIN="/Library/Keychains/System.keychain"

# ── Cores ────────────────────────────────────────────────────────────────────
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

# ── Variáveis globais ────────────────────────────────────────────────────────
OS=""
HOST=""
PORTA="$DEFAULT_PORT"
ACTION="install"
ASSUME_YES="false"
VERBOSE="false"
PORT_PROVIDED="false"
TMPFILE=""
ERRFILE=""
CERT_NAME=""
CERT_PATH=""
CN=""
SUBJECT=""
ISSUER=""
NOT_BEFORE=""
NOT_AFTER=""
FINGERPRINT_SHA256=""
FINGERPRINT_SHA1=""
SAN=""
MACOS_TRUST_RESULT="trustRoot"
IDENTITY_VALID="false"
IDENTITY_REASON=""

# ── Utilidades ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF_HELP
${APP_NAME} v${APP_VERSION}
Importa ou remove certificado SSL/TLS do repositório confiável do sistema.

Uso:
  ${APP_NAME} [opções]

Opções:
  -H, --host HOST        IP ou hostname do servidor
  -p, --port PORTA       Porta do servidor (padrão: 443)
  -r, --remove           Remove certificado instalado por este script
  -y, --yes              Executa sem confirmação interativa
  -v, --verbose          Mostra comandos e mais detalhes
  -h, --help             Exibe esta ajuda
  --version              Exibe a versão

Exemplos:
  ${APP_NAME}
  ${APP_NAME} --host mkserver.local --port 443
  ${APP_NAME} -H 10.0.1.10 -p 8443 -y
  ${APP_NAME} --remove --host mkserver.local

Observações:
  - No macOS, o script usa o Keychain do Sistema.
  - No Linux, execute com sudo/root.
  - Para servidores com Virtual Host, o script usa SNI automaticamente.
EOF_HELP
}

log_msg() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$APP_NAME" "$*" >> "$LOG_DIR/trust-cert.log" 2>/dev/null || true
}

run_cmd() {
    if [ "$VERBOSE" = "true" ]; then
        printf "%b+ %s%b\n" "$CYAN" "$*" "$NC"
    fi
    "$@"
}

cleanup() {
    local exit_code=$?
    if [ -n "${TMPFILE:-}" ] && [ -f "$TMPFILE" ]; then
        rm -f "$TMPFILE"
    fi
    if [ -n "${ERRFILE:-}" ] && [ -f "$ERRFILE" ]; then
        rm -f "$ERRFILE"
    fi
    return "$exit_code"
}

on_interrupt() {
    echo ""
    warn "Operação interrompida pelo usuário. Porque aparentemente Ctrl+C ainda é o botão do pânico universal."
    cleanup
    exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

sanitize_name() {
    printf "%s" "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

is_ip_address() {
    printf "%s" "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

validate_ip() {
    local ip="$1"
    local octet=""
    local octets=()
    local IFS='.'

    read -r -a octets <<< "$ip"
    [ "${#octets[@]}" -eq 4 ] || return 1

    for octet in "${octets[@]}"; do
        if ! { [ "$octet" -ge 0 ] 2>/dev/null && [ "$octet" -le 255 ] 2>/dev/null; }; then
            return 1
        fi
    done
    return 0
}

validate_host() {
    local host="$1"
    local label=""
    local labels=()
    local IFS='.'

    [ -n "$host" ] || error "Hostname/IP não pode ficar vazio."
    [ "${#host}" -le 253 ] || error "Hostname muito longo: $host"

    if is_ip_address "$host"; then
        validate_ip "$host" || error "IP inválido: $host"
        return 0
    fi

    case "$host" in
        *..*|.*|*.) error "Hostname inválido: $host" ;;
    esac

    read -r -a labels <<< "$host"
    for label in "${labels[@]}"; do
        [ -n "$label" ] || error "Hostname inválido: $host"
        [ "${#label}" -le 63 ] || error "Label de hostname muito longo: $label"
        printf "%s" "$label" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$' \
            || error "Hostname inválido: $host"
    done
}

validate_port() {
    local port="$1"
    printf "%s" "$port" | grep -Eq '^[0-9]+$' || error "Porta inválida: $port"
    if ! { [ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null; }; then
        error "Porta fora do intervalo permitido: $port"
    fi
}

confirm_or_exit() {
    local message="$1"
    local answer=""

    if [ "$ASSUME_YES" = "true" ]; then
        return 0
    fi

    read -r -p "$message [s/N]: " answer
    case "$answer" in
        s|S|sim|SIM|Sim) return 0 ;;
        *) warn "Cancelado pelo usuário."; exit 0 ;;
    esac
}

confirm_choice() {
    local message="$1"
    local answer=""

    if [ "$ASSUME_YES" = "true" ]; then
        return 1
    fi

    read -r -p "$message [s/N]: " answer
    case "$answer" in
        s|S|sim|SIM|Sim) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Sistema operacional ──────────────────────────────────────────────────────
detect_os() {
    if [[ "${OSTYPE:-}" == "darwin"* ]]; then
        echo "macos"
    elif [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
            ubuntu|debian|linuxmint|pop)   echo "debian" ;;
            rhel|centos|fedora|rocky|alma) echo "rhel" ;;
            arch|manjaro|endeavouros)      echo "arch" ;;
            *)                             echo "linux-generic" ;;
        esac
    else
        echo "unknown"
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || error "Comando obrigatório não encontrado: $1"
}

check_dependencies() {
    require_cmd openssl
    require_cmd sed
    require_cmd grep
    require_cmd cut
    require_cmd tr
    require_cmd awk

    case "$OS" in
        macos)
            require_cmd security
            require_cmd sudo
            ;;
        debian|linux-generic)
            require_cmd update-ca-certificates
            ;;
        rhel)
            require_cmd update-ca-trust
            ;;
        arch)
            require_cmd trust
            ;;
    esac
}

check_privileges() {
    if [ "$OS" != "macos" ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
        error "No Linux execute como root: sudo $0"
    fi
}

# ── Parâmetros ────────────────────────────────────────────────────────────────
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -H|--host)
                [ "$#" -ge 2 ] || error "Faltou informar o valor de $1"
                HOST="$2"
                shift 2
                ;;
            -p|--port)
                [ "$#" -ge 2 ] || error "Faltou informar o valor de $1"
                PORTA="$2"
                PORT_PROVIDED="true"
                shift 2
                ;;
            -r|--remove)
                ACTION="remove"
                shift
                ;;
            -y|--yes)
                ASSUME_YES="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --version)
                echo "${APP_NAME} ${APP_VERSION} (${APP_RELEASE_DATE})"
                exit 0
                ;;
            *)
                error "Opção desconhecida: $1"
                ;;
        esac
    done
}

interactive_config() {
    local host_prompted="false"

    if [ -z "$HOST" ]; then
        read -r -p "IP ou hostname do servidor: " HOST
        host_prompted="true"
    fi

    if [ "$host_prompted" = "true" ] && [ "$PORT_PROVIDED" = "false" ]; then
        read -r -p "Porta [443]: " PORTA
    fi

    PORTA="${PORTA:-$DEFAULT_PORT}"
}

print_header() {
    echo ""
    printf "%b╔══════════════════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║     trust-cert — Certificados confiáveis             ║%b\n" "$BOLD" "$NC"
    printf "%b║     Versão: %-10sData: %-10s               ║%b\n" "$BOLD" "v${APP_VERSION}" "$APP_RELEASE_DATE" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo ""
}

print_destination() {
    case "$OS" in
        macos)          echo "  Keychain : $SYSTEM_KEYCHAIN" ;;
        debian)         echo "  Destino  : /usr/local/share/ca-certificates/" ;;
        rhel)           echo "  Destino  : /etc/pki/ca-trust/source/anchors/" ;;
        arch)           echo "  Destino  : /etc/ca-certificates/trust-source/anchors/" ;;
        linux-generic)  echo "  Destino  : /usr/local/share/ca-certificates/" ;;
    esac
}

# ── Certificado ───────────────────────────────────────────────────────────────
fetch_certificate() {
    step "Exportando certificado de $HOST:$PORTA"

    TMPFILE=$(mktemp "/tmp/${APP_NAME}_XXXXXX.pem")
    ERRFILE=$(mktemp "/tmp/${APP_NAME}_openssl_XXXXXX.err")

    if is_ip_address "$HOST"; then
        run_cmd openssl s_client -connect "$HOST:$PORTA" -showcerts </dev/null 2>"$ERRFILE" \
            | openssl x509 -outform PEM > "$TMPFILE" || true
    else
        run_cmd openssl s_client -connect "$HOST:$PORTA" -servername "$HOST" -showcerts </dev/null 2>"$ERRFILE" \
            | openssl x509 -outform PEM > "$TMPFILE" || true
    fi

    [ -s "$TMPFILE" ] || {
        if [ -f "$ERRFILE" ]; then
            sed -n '1,8p' "$ERRFILE" >&2 || true
        fi
        error "Não foi possível obter o certificado. Verifique host, porta, DNS e firewall. A internet segue sendo composta de cabos, magia e sofrimento."
    }

    rm -f "$ERRFILE" 2>/dev/null || true
    ERRFILE=""
}

extract_cert_info() {
    SUBJECT=$(openssl x509 -noout -subject -in "$TMPFILE" 2>/dev/null | sed 's/^subject=//')
    ISSUER=$(openssl x509 -noout -issuer -in "$TMPFILE" 2>/dev/null | sed 's/^issuer=//')
    CN=$(printf "%s" "$SUBJECT" | sed 's/.*CN *= *//; s/,.*//; s#/.*##')
    [ -n "$CN" ] || CN="$HOST"

    NOT_BEFORE=$(openssl x509 -noout -startdate -in "$TMPFILE" 2>/dev/null | sed 's/notBefore=//')
    NOT_AFTER=$(openssl x509 -noout -enddate -in "$TMPFILE" 2>/dev/null | sed 's/notAfter=//')

    FINGERPRINT_SHA256=$(openssl x509 -noout -fingerprint -sha256 -in "$TMPFILE" 2>/dev/null | cut -d= -f2)
    FINGERPRINT_SHA1=$(openssl x509 -noout -fingerprint -sha1 -in "$TMPFILE" 2>/dev/null | cut -d= -f2)

    SAN=$(openssl x509 -text -noout -in "$TMPFILE" 2>/dev/null \
        | awk '/Subject Alternative Name/{getline; gsub(/^ +/, ""); print}' || true)

    if [ "$SUBJECT" = "$ISSUER" ]; then
        MACOS_TRUST_RESULT="trustRoot"
    else
        MACOS_TRUST_RESULT="trustAsRoot"
    fi

    CERT_NAME="intranet-$(sanitize_name "$CN")"
    [ "$CERT_NAME" != "intranet-" ] || CERT_NAME="intranet-$(sanitize_name "$HOST")"
}

check_expiration() {
    if ! openssl x509 -checkend 0 -noout -in "$TMPFILE" >/dev/null 2>&1; then
        warn "O certificado está expirado. Importar certificado vencido é tipo colocar cadeado em porta sem parede."
        confirm_or_exit "Deseja continuar mesmo assim?"
    fi
}

certificate_matches_host() {
    if is_ip_address "$HOST"; then
        printf "%s\n" "$SAN" \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//' \
            | grep -Fxiq -e "IP Address:$HOST" -e "IP:$HOST"
    else
        printf "%s\n" "$SAN" \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//' \
            | grep -Fxiq "DNS:$HOST"
    fi
}

check_certificate_identity() {
    if [ -z "$SAN" ]; then
        IDENTITY_REASON="o certificado não possui Subject Alternative Name (SAN)"
    elif certificate_matches_host; then
        IDENTITY_VALID="true"
        IDENTITY_REASON="o SAN contém $HOST"
        success "Identidade válida para '$HOST'."
        return 0
    elif is_ip_address "$HOST"; then
        IDENTITY_REASON="o SAN não contém IP Address:$HOST"
    else
        IDENTITY_REASON="o SAN não contém DNS:$HOST"
    fi

    warn "Identidade incompatível: $IDENTITY_REASON."
    warn "Confiar no certificado não corrige nome ou IP. O servidor precisa emitir um certificado cujo SAN contenha o endereço acessado."
    confirm_or_exit "Importar mesmo assim? O navegador continuará indicando certificado inválido para $HOST"
}

print_cert_summary() {
    success "Certificado obtido"
    echo "  CN          : $CN"
    echo "  Subject     : $SUBJECT"
    echo "  Issuer      : $ISSUER"
    echo "  Válido de   : $NOT_BEFORE"
    echo "  Válido até  : $NOT_AFTER"
    echo "  SHA-256     : $FINGERPRINT_SHA256"
    echo "  SHA-1       : $FINGERPRINT_SHA1"
    if [ -n "$SAN" ]; then
        echo "  SAN         : $SAN"
    else
        echo "  SAN         : ausente"
    fi
}

backup_certificate() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    local backup_file="$BACKUP_DIR/${CERT_NAME}-${FINGERPRINT_SHA256}.pem"
    cp "$TMPFILE" "$backup_file" 2>/dev/null || true
}

safe_index_field() {
    printf "%s" "$1" | tr '\t\n' '  '
}

index_delete() {
    local tmp_index=""

    [ -f "$INDEX_FILE" ] || return 0

    mkdir -p "${INDEX_FILE%/*}" 2>/dev/null || true
    tmp_index=$(mktemp "/tmp/${APP_NAME}_index_XXXXXX.tsv")

    awk -F '\t' -v host="$HOST" -v port="$PORTA" -v os="$OS" \
        '!(($1 == host) && ($2 == port) && ($3 == os))' "$INDEX_FILE" > "$tmp_index" || true

    mv "$tmp_index" "$INDEX_FILE" 2>/dev/null || true
}

index_upsert() {
    local installed_path="$1"
    local now=""

    mkdir -p "${INDEX_FILE%/*}" 2>/dev/null || true
    index_delete

    now=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(safe_index_field "$HOST")" \
        "$(safe_index_field "$PORTA")" \
        "$(safe_index_field "$OS")" \
        "$(safe_index_field "$CERT_NAME")" \
        "$(safe_index_field "$installed_path")" \
        "$(safe_index_field "$FINGERPRINT_SHA1")" \
        "$(safe_index_field "$FINGERPRINT_SHA256")" \
        "$(safe_index_field "$CN")" \
        "$(safe_index_field "$now")" >> "$INDEX_FILE" 2>/dev/null || true
}

index_lookup() {
    local line=""
    local _idx_host=""
    local _idx_port=""
    local _idx_os=""
    local _idx_date=""

    [ -f "$INDEX_FILE" ] || return 1

    line=$(awk -F '\t' -v host="$HOST" -v port="$PORTA" -v os="$OS" \
        '($1 == host) && ($2 == port) && ($3 == os) { found = $0 } END { if (found) print found }' "$INDEX_FILE")

    [ -n "$line" ] || return 1

    IFS="$(printf '\t')" read -r _idx_host _idx_port _idx_os CERT_NAME CERT_PATH FINGERPRINT_SHA1 FINGERPRINT_SHA256 CN _idx_date <<EOF_INDEX
$line
EOF_INDEX

    [ -n "$CERT_NAME" ] || return 1
    return 0
}

print_index_summary() {
    success "Registro local encontrado"
    echo "  CN          : $CN"
    echo "  Nome local  : $CERT_NAME"
    echo "  Caminho     : $CERT_PATH"
    echo "  SHA-256     : $FINGERPRINT_SHA256"
    echo "  SHA-1       : $FINGERPRINT_SHA1"
}

# ── Verificações de instalação ───────────────────────────────────────────────
macos_cert_exists() {
    local current_sha1=""
    local current_sha256=""

    current_sha1=$(printf "%s" "$FINGERPRINT_SHA1" | tr -d ':' | tr '[:lower:]' '[:upper:]')
    current_sha256=$(printf "%s" "$FINGERPRINT_SHA256" | tr -d ':' | tr '[:lower:]' '[:upper:]')

    security find-certificate -a -Z "$SYSTEM_KEYCHAIN" 2>/dev/null \
        | awk '/hash:/ { print toupper($NF) }' \
        | grep -Fxiq -e "$current_sha1" -e "$current_sha256"
}

normalize_fingerprint() {
    printf "%s" "$1" | tr -d ':' | tr '[:lower:]' '[:upper:]'
}

macos_delete_current_certificate() {
    local current_sha256=""
    local current_sha1=""

    current_sha256=$(normalize_fingerprint "$FINGERPRINT_SHA256")
    current_sha1=$(normalize_fingerprint "$FINGERPRINT_SHA1")

    if run_cmd sudo security delete-certificate -Z "$current_sha256" "$SYSTEM_KEYCHAIN"; then
        return 0
    fi

    warn "Não consegui remover pelo SHA-256; tentando pelo SHA-1."
    run_cmd sudo security delete-certificate -Z "$current_sha1" "$SYSTEM_KEYCHAIN"
}

macos_stale_certificates() {
    local current_sha1=""
    local current_sha256=""

    current_sha1=$(printf "%s" "$FINGERPRINT_SHA1" | tr -d ':' | tr '[:lower:]' '[:upper:]')
    current_sha256=$(printf "%s" "$FINGERPRINT_SHA256" | tr -d ':' | tr '[:lower:]' '[:upper:]')

    security find-certificate -a -c "$CN" -Z "$SYSTEM_KEYCHAIN" 2>/dev/null \
        | awk '/SHA-256 hash:/ { print $NF }' \
        | tr '[:lower:]' '[:upper:]' \
        | awk -v sha1="$current_sha1" -v sha256="$current_sha256" \
            '($0 != sha1) && ($0 != sha256) && !seen[$0]++'
}

linux_cert_path() {
    case "$OS" in
        debian|linux-generic)
            CERT_PATH="/usr/local/share/ca-certificates/${CERT_NAME}.crt"
            ;;
        rhel)
            CERT_PATH="/etc/pki/ca-trust/source/anchors/${CERT_NAME}.pem"
            ;;
        arch)
            CERT_PATH="/etc/ca-certificates/trust-source/anchors/${CERT_NAME}.pem"
            ;;
    esac
}

linux_cert_exists() {
    linux_cert_path
    [ -f "$CERT_PATH" ] && grep -q "BEGIN CERTIFICATE" "$CERT_PATH"
}

# ── Instalação ────────────────────────────────────────────────────────────────
install_macos() {
    local stale_hashes=""
    local stale_hash=""

    step "Importando no Keychain do Sistema (macOS)"

    stale_hashes=$(macos_stale_certificates || true)
    if [ -n "$stale_hashes" ]; then
        warn "Encontrei certificado(s) anterior(es) com o mesmo CN '$CN' no Keychain do Sistema:"
        while IFS= read -r stale_hash; do
            [ -n "$stale_hash" ] && echo "  Fingerprint : $stale_hash"
        done <<EOF_STALE_LIST
$stale_hashes
EOF_STALE_LIST

        if confirm_choice "Remover os certificados anteriores antes de importar o novo?"; then
            while IFS= read -r stale_hash; do
                [ -n "$stale_hash" ] || continue
                run_cmd sudo security delete-certificate -Z "$stale_hash" "$SYSTEM_KEYCHAIN"
            done <<EOF_STALE_DELETE
$stale_hashes
EOF_STALE_DELETE
            success "Certificados anteriores removidos."
        else
            if [ "$ASSUME_YES" = "true" ]; then
                warn "Os certificados anteriores foram mantidos no modo --yes; execute sem --yes para confirmar a limpeza interativamente."
            else
                warn "Os certificados anteriores foram mantidos. Eles podem causar seleção ambígua no Keychain."
            fi
        fi
    fi

    if macos_cert_exists; then
        warn "Este certificado já está no Keychain. Vou substituir e reaplicar a confiança."
        macos_delete_current_certificate
    fi

    info "Pode ser solicitada sua senha de administrador."
    run_cmd sudo security add-trusted-cert \
        -d \
        -r "$MACOS_TRUST_RESULT" \
        -k "$SYSTEM_KEYCHAIN" \
        "$TMPFILE"

    if macos_cert_exists; then
        success "Importação validada no Keychain."
    else
        warn "Importação executada, mas não consegui validar pelo fingerprint. Verifique no Acesso às Chaves."
    fi
}

install_linux() {
    linux_cert_path
    step "Importando no repositório do sistema"

    if linux_cert_exists; then
        warn "Arquivo já existe: $CERT_PATH"
        confirm_or_exit "Sobrescrever?"
    fi

    run_cmd cp "$TMPFILE" "$CERT_PATH"
    run_cmd chmod 644 "$CERT_PATH"

    case "$OS" in
        debian|linux-generic)
            run_cmd update-ca-certificates
            ;;
        rhel)
            run_cmd update-ca-trust extract
            ;;
        arch)
            run_cmd trust extract-compat
            ;;
    esac

    [ -f "$CERT_PATH" ] && success "Arquivo instalado em: $CERT_PATH"
}

install_certificate() {
    fetch_certificate
    extract_cert_info
    check_expiration
    print_cert_summary
    check_certificate_identity
    backup_certificate

    echo ""
    printf "%bResumo:%b\n" "$BOLD" "$NC"
    echo "  Ação     : importar"
    echo "  Servidor : $HOST:$PORTA"
    print_destination
    echo ""

    confirm_or_exit "Confirmar e importar?"

    case "$OS" in
        macos) install_macos ;;
        debian|linux-generic|rhel|arch) install_linux ;;
    esac

    if [ "$OS" = "macos" ]; then
        index_upsert "$SYSTEM_KEYCHAIN"
    else
        index_upsert "$CERT_PATH"
    fi

    log_msg "INSTALLED host=$HOST port=$PORTA cn=$CN sha256=$FINGERPRINT_SHA256"

    success "Certificado '$CN' importado e marcado como confiável."
    final_instructions
}

# ── Remoção ──────────────────────────────────────────────────────────────────
remove_macos() {
    step "Removendo do Keychain do Sistema (macOS)"

    if index_lookup; then
        print_index_summary
    else
        warn "Registro local não encontrado. Tentando identificar pelo certificado remoto."
        fetch_certificate
        extract_cert_info
        print_cert_summary
    fi

    if ! macos_cert_exists; then
        warn "Não encontrei este certificado no Keychain pelo fingerprint SHA-1."
        return 0
    fi

    confirm_or_exit "Confirmar remoção do certificado?"
    macos_delete_current_certificate
    index_delete
    success "Certificado removido do Keychain."
    log_msg "REMOVED macos host=$HOST port=$PORTA cn=$CN sha256=$FINGERPRINT_SHA256"
}

remove_linux() {
    step "Removendo do repositório do sistema"

    if index_lookup; then
        print_index_summary
    else
        warn "Registro local não encontrado. Tentando identificar pelo certificado remoto."
        fetch_certificate
        extract_cert_info
        linux_cert_path
        print_cert_summary
    fi

    if [ ! -f "$CERT_PATH" ]; then
        warn "Arquivo não encontrado: $CERT_PATH"
        return 0
    fi

    confirm_or_exit "Confirmar remoção de $CERT_PATH?"
    run_cmd rm -f "$CERT_PATH"

    case "$OS" in
        debian|linux-generic)
            run_cmd update-ca-certificates --fresh
            ;;
        rhel)
            run_cmd update-ca-trust extract
            ;;
        arch)
            run_cmd trust extract-compat
            ;;
    esac

    index_delete
    success "Certificado removido."
    log_msg "REMOVED linux host=$HOST port=$PORTA cn=$CN sha256=$FINGERPRINT_SHA256"
}

remove_certificate() {
    echo ""
    printf "%bResumo:%b\n" "$BOLD" "$NC"
    echo "  Ação     : remover"
    echo "  Servidor : $HOST:$PORTA"
    print_destination
    echo ""

    case "$OS" in
        macos) remove_macos ;;
        debian|linux-generic|rhel|arch) remove_linux ;;
    esac
}

# ── Final ────────────────────────────────────────────────────────────────────
final_instructions() {
    echo ""
    printf "%b━━━ Próximos passos ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$BOLD" "$NC"
    echo ""
    echo "  1. Feche e reabra o navegador"
    echo "  2. Acesse https://$HOST:$PORTA"
    if [ "$IDENTITY_VALID" = "true" ]; then
        echo "  3. O certificado é confiável e o SAN corresponde ao endereço"
    else
        echo "  3. Atenção: o navegador continuará alertando porque $IDENTITY_REASON"
        echo "     Gere no servidor um certificado com o nome e o IP desejados no SAN"
    fi
    echo ""

    if [ "$OS" = "macos" ]; then
        info "Para remover futuramente:"
        echo "     ${APP_NAME} --remove --host $HOST --port $PORTA"
        echo "     ou: Acesso às Chaves → Sistema → localizar '$CN' → Apagar"
    else
        info "Para remover futuramente:"
        echo "     sudo ${APP_NAME} --remove --host $HOST --port $PORTA"
    fi

    echo ""
    info "Log: $LOG_DIR/trust-cert.log"
    info "Backup do certificado: $BACKUP_DIR"
    echo ""
}

main() {
    parse_args "$@"
    OS=$(detect_os)
    [ "$OS" = "unknown" ] && error "Sistema operacional não suportado."

    print_header
    info "Sistema detectado: $OS"

    check_dependencies
    check_privileges
    interactive_config
    validate_host "$HOST"
    validate_port "$PORTA"

    case "$ACTION" in
        install) install_certificate ;;
        remove)  remove_certificate ;;
        *) error "Ação inválida: $ACTION" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
