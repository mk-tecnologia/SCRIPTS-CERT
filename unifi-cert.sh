#!/usr/bin/env bash
# =============================================================================
# unifi-cert.sh — Gerar/aplicar certificado SSL/TLS no UniFi
# Versão  : consulte APP_VERSION abaixo ou execute --version
# Autor   : Marcos A. Campos <marcos@mktecnologia.net.br>
# Suporte : Debian/Ubuntu (UniFi Network Application)
# Licença : MIT
# Dica    : Use Linux :)
# =============================================================================

set -euo pipefail

# ── Metadados ────────────────────────────────────────────────────────────────
APP_NAME="unifi-cert"
APP_VERSION="2.3.5"
APP_RELEASE_DATE="2026-08-14"
UNIFI_ALIAS="unifi"
KEYSTORE="/var/lib/unifi/keystore"
STOREPASS="aircontrolenterprise"
CA_DIR="/etc/ssl/unifi-ca"
CERT_VALIDITY="825"
CA_VALIDITY="3650"
SERVER_KEY_BITS="2048"
CA_KEY_BITS="4096"
LOG_DIR="/var/log/${APP_NAME}"
BACKUP_DIR="/var/backups/${APP_NAME}"

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
CN=""
SHORT_NAME=""
IP=""
ASSUME_YES="false"
VERBOSE="false"
ADD_HOSTS="ask"
RECREATE_CA="false"
WORK_DIR=""
CA_FILE=""
BACKUP_TARGET=""
HAD_KEYSTORE="false"
SERVICE_STOPPED="false"
KEYSTORE_REPLACED="false"
NEW_KEYSTORE=""
HAD_CA_CERT="false"
HAD_CA_KEY="false"
HAD_CA_SERIAL="false"
CA_CHANGED="false"
RUN_COMPLETE="false"

# ── Utilidades ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF_HELP
${APP_NAME} v${APP_VERSION}
Cria uma CA local, emite certificado para o UniFi e importa no Java keystore.

Uso:
  ${APP_NAME} [opções]

Opções:
  --cn FQDN              Nome completo do servidor
  --short NOME           Nome curto / alias DNS extra
  --ip IP                IP do servidor
  --keystore CAMINHO     Caminho do keystore UniFi (padrão: ${KEYSTORE})
  --storepass SENHA      Senha do keystore (padrão UniFi)
  --ca-dir CAMINHO       Diretório da CA local (padrão: ${CA_DIR})
  --days DIAS            Validade do certificado do servidor (padrão: 825)
  --ca-days DIAS         Validade da CA raiz (padrão: 3650)
  --recreate-ca          Recria a CA raiz local
  --add-hosts            Adiciona entrada no /etc/hosts sem perguntar
  --no-add-hosts         Não altera /etc/hosts
  -y, --yes              Executa sem confirmação
  -v, --verbose          Mostra comandos e detalhes
  -h, --help             Exibe esta ajuda
  --version              Exibe a versão

Exemplos:
  ${APP_NAME}
  ${APP_NAME} --cn unifi.lab.local --short unifi --ip 10.0.1.30
  ${APP_NAME} --cn unifi.lab.local --ip 10.0.1.30 -y --add-hosts
EOF_HELP
}

log_msg() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$APP_NAME" "$*" >> "$LOG_DIR/${APP_NAME}.log" 2>/dev/null || true
}

run_cmd() {
    if [ "$VERBOSE" = "true" ]; then
        printf "%b+ %s%b\n" "$CYAN" "$*" "$NC"
    fi
    "$@"
}

cleanup() {
    local exit_code=$?
    if [ "${RUN_COMPLETE:-false}" != "true" ]; then
        if [ "${KEYSTORE_REPLACED:-false}" = "true" ] && [ -n "${BACKUP_TARGET:-}" ]; then
            if [ "${HAD_KEYSTORE:-false}" = "true" ]; then
                cp "$BACKUP_TARGET/keystore" "$KEYSTORE" 2>/dev/null || true
            else
                rm -f "$KEYSTORE"
            fi
        fi
        if [ "${CA_CHANGED:-false}" = "true" ] && [ -n "${BACKUP_TARGET:-}" ]; then
            if [ "${HAD_CA_CERT:-false}" = "true" ]; then cp "$BACKUP_TARGET/ca.crt" "$CA_DIR/ca.crt" 2>/dev/null || true; else rm -f "$CA_DIR/ca.crt"; fi
            if [ "${HAD_CA_KEY:-false}" = "true" ]; then cp "$BACKUP_TARGET/ca.key" "$CA_DIR/ca.key" 2>/dev/null || true; else rm -f "$CA_DIR/ca.key"; fi
            if [ "${HAD_CA_SERIAL:-false}" = "true" ]; then cp "$BACKUP_TARGET/ca.srl" "$CA_DIR/ca.srl" 2>/dev/null || true; else rm -f "$CA_DIR/ca.srl"; fi
        fi
    fi
    [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    [ -n "${NEW_KEYSTORE:-}" ] && [ -f "$NEW_KEYSTORE" ] && rm -f "$NEW_KEYSTORE"
    if [ "${SERVICE_STOPPED:-false}" = "true" ]; then
        systemctl start unifi >/dev/null 2>&1 || true
    fi
    return "$exit_code"
}

on_interrupt() {
    echo ""
    warn "Operação interrompida. O UniFi sobreviveu a coisas piores, provavelmente."
    cleanup
    exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

require_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || error "Execute como root: sudo $0"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || error "Comando obrigatório não encontrado: $1"; }

unifi_service_exists() {
    [ "$(systemctl show --property=LoadState --value unifi.service 2>/dev/null || true)" = "loaded" ]
}

check_dependencies() {
    step "Verificando dependências"
    require_cmd openssl
    require_cmd keytool
    require_cmd systemctl
    require_cmd hostname
    require_cmd awk
    require_cmd grep
    require_cmd sed
    require_cmd cut
    require_cmd tr
    require_cmd seq
    require_cmd sleep
    keytool -help >/dev/null 2>&1 || error "keytool encontrado, mas o runtime Java não está funcional."
    success "Dependências disponíveis"
}

validate_ip() {
    local ip="$1" octet="" IFS='.'
    local octets=()
    read -r -a octets <<< "$ip"
    [ "${#octets[@]}" -eq 4 ] || error "IP inválido: $ip"
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || error "IP inválido: $ip"
        if ! { [ "$octet" -ge 0 ] 2>/dev/null && [ "$octet" -le 255 ] 2>/dev/null; }; then
            error "IP inválido: $ip"
        fi
    done
}

validate_hostname() {
    local host="$1" label="" IFS='.'
    local labels=()
    [ -n "$host" ] || error "Nome do servidor não pode ficar vazio."
    [ "${#host}" -le 253 ] || error "Hostname muito longo: $host"
    case "$host" in *..*|.*|*.) error "Hostname inválido: $host" ;; esac
    read -r -a labels <<< "$host"
    for label in "${labels[@]}"; do
        [ -n "$label" ] || error "Hostname inválido: $host"
        [ "${#label}" -le 63 ] || error "Label muito longo: $label"
        printf "%s" "$label" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$' || error "Hostname inválido: $host"
    done
}

validate_days() {
    [[ "$CERT_VALIDITY" =~ ^[0-9]+$ ]] || error "Validade inválida: $CERT_VALIDITY"
    [[ "$CA_VALIDITY" =~ ^[0-9]+$ ]] || error "Validade da CA inválida: $CA_VALIDITY"
    if ! { [ "$CERT_VALIDITY" -ge 1 ] && [ "$CERT_VALIDITY" -le 825 ]; }; then
        error "Use validade entre 1 e 825 dias para o certificado do servidor."
    fi
    [ "$CA_VALIDITY" -ge 365 ] || error "Validade da CA muito baixa: $CA_VALIDITY"
}

confirm_or_exit() {
    local message="$1" answer=""
    [ "$ASSUME_YES" = "true" ] && return 0
    read -r -p "$message [s/N]: " answer
    case "$answer" in s|S|sim|SIM|Sim) return 0 ;; *) warn "Cancelado pelo usuário."; exit 0 ;; esac
}

confirm_optional() {
    local message="$1" answer=""
    [ "$ASSUME_YES" = "true" ] && return 0
    read -r -p "$message [s/N]: " answer
    case "$answer" in s|S|sim|SIM|Sim) return 0 ;; *) return 1 ;; esac
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --cn) [ "$#" -ge 2 ] || error "Faltou valor para --cn"; CN="$2"; shift 2 ;;
            --short) [ "$#" -ge 2 ] || error "Faltou valor para --short"; SHORT_NAME="$2"; shift 2 ;;
            --ip) [ "$#" -ge 2 ] || error "Faltou valor para --ip"; IP="$2"; shift 2 ;;
            --keystore) [ "$#" -ge 2 ] || error "Faltou valor para --keystore"; KEYSTORE="$2"; shift 2 ;;
            --storepass) [ "$#" -ge 2 ] || error "Faltou valor para --storepass"; STOREPASS="$2"; shift 2 ;;
            --ca-dir) [ "$#" -ge 2 ] || error "Faltou valor para --ca-dir"; CA_DIR="$2"; shift 2 ;;
            --days) [ "$#" -ge 2 ] || error "Faltou valor para --days"; CERT_VALIDITY="$2"; shift 2 ;;
            --ca-days) [ "$#" -ge 2 ] || error "Faltou valor para --ca-days"; CA_VALIDITY="$2"; shift 2 ;;
            --recreate-ca) RECREATE_CA="true"; shift ;;
            --add-hosts) ADD_HOSTS="yes"; shift ;;
            --no-add-hosts) ADD_HOSTS="no"; shift ;;
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
    printf "%b║     unifi-cert — UniFi Network Application           ║%b\n" "$BOLD" "$NC"
    printf "%b║     Versão: %-10sData: %-10s               ║%b\n" "$BOLD" "v${APP_VERSION}" "$APP_RELEASE_DATE" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo ""
}

check_unifi() {
    step "Verificando UniFi"
    if unifi_service_exists; then
        success "Serviço unifi encontrado"
    else
        error "Serviço unifi não encontrado. Este script requer a instalação self-hosted com unifi.service."
    fi
    [ -d "$(dirname "$KEYSTORE")" ] || error "Diretório do keystore não encontrado: $(dirname "$KEYSTORE")"
}

collect_config() {
    step "Configuração do certificado"

    local fqdn_default short_default ip_default
    fqdn_default=$(hostname -f 2>/dev/null || hostname)
    short_default=$(hostname -s 2>/dev/null || hostname)
    ip_default=$(hostname -I 2>/dev/null | awk '{print $1}')

    [ -n "$CN" ] || { read -r -p "Nome completo do servidor [${fqdn_default}]: " CN; CN="${CN:-$fqdn_default}"; }
    [ -n "$SHORT_NAME" ] || { read -r -p "Nome curto / alias DNS [${short_default}]: " SHORT_NAME; SHORT_NAME="${SHORT_NAME:-$short_default}"; }
    [ -n "$IP" ] || { read -r -p "IP do servidor [${ip_default}]: " IP; IP="${IP:-$ip_default}"; }

    validate_hostname "$CN"
    validate_hostname "$SHORT_NAME"
    validate_ip "$IP"
    validate_days

    CA_FILE="$CA_DIR/ca.crt"

    echo ""
    printf "%bResumo:%b\n" "$BOLD" "$NC"
    echo "  CN/FQDN    : $CN"
    echo "  Alias DNS  : $SHORT_NAME"
    echo "  IP         : $IP"
    echo "  Porta      : 8443"
    echo "  Keystore   : $KEYSTORE"
    echo "  CA raiz    : $CA_FILE"
    echo "  Validade   : $CERT_VALIDITY dias"
    echo "  CA validade: $CA_VALIDITY dias"
    echo ""
    confirm_or_exit "Confirmar e aplicar?"
}

stop_unifi() {
    step "Parando UniFi"
    if unifi_service_exists; then
        if ! run_cmd systemctl stop unifi; then
            warn "Não foi possível parar o UniFi."
            return 1
        fi
        SERVICE_STOPPED="true"
        success "UniFi parado"
    else
        warn "Serviço unifi não encontrado. Pulando parada do serviço."
    fi
}

start_unifi() {
    step "Iniciando UniFi"
    if unifi_service_exists; then
        if ! run_cmd systemctl start unifi; then
            warn "Não foi possível iniciar o UniFi."
            return 1
        fi
        SERVICE_STOPPED="false"
        success "UniFi iniciado"
    else
        warn "Serviço unifi não encontrado. Inicie manualmente se necessário."
    fi
}

backup_current() {
    step "Backup"
    local stamp
    stamp=$(date +%Y%m%d%H%M%S)
    mkdir -p "$BACKUP_DIR"
    BACKUP_TARGET=$(mktemp -d "$BACKUP_DIR/$stamp-XXXXXX")
    if [ -f "$KEYSTORE" ]; then
        cp "$KEYSTORE" "$BACKUP_TARGET/keystore"
        HAD_KEYSTORE="true"
    fi
    if [ -f "$CA_DIR/ca.crt" ]; then cp "$CA_DIR/ca.crt" "$BACKUP_TARGET/ca.crt"; HAD_CA_CERT="true"; fi
    if [ -f "$CA_DIR/ca.key" ]; then cp "$CA_DIR/ca.key" "$BACKUP_TARGET/ca.key"; HAD_CA_KEY="true"; fi
    if [ -f "$CA_DIR/ca.srl" ]; then cp "$CA_DIR/ca.srl" "$BACKUP_TARGET/ca.srl"; HAD_CA_SERIAL="true"; fi
    success "Backup salvo em: $BACKUP_TARGET"
}

validate_ca() {
    local cert_pubkey="" key_pubkey="" minimum_seconds=""

    minimum_seconds=$((CERT_VALIDITY * 86400))
    openssl x509 -in "$CA_DIR/ca.crt" -noout >/dev/null 2>&1 \
        || error "Certificado da CA inválido. Use --recreate-ca."
    openssl pkey -in "$CA_DIR/ca.key" -noout >/dev/null 2>&1 \
        || error "Chave privada da CA inválida. Use --recreate-ca."
    openssl x509 -in "$CA_DIR/ca.crt" -noout -checkend "$minimum_seconds" >/dev/null 2>&1 \
        || error "A CA expira antes do certificado solicitado. Use --recreate-ca ou reduza --days."
    openssl x509 -in "$CA_DIR/ca.crt" -noout -text \
        | grep -A1 'Basic Constraints' | grep -q 'CA:TRUE' \
        || error "A CA existente não possui CA:TRUE. Use --recreate-ca."

    cert_pubkey=$(openssl x509 -in "$CA_DIR/ca.crt" -pubkey -noout | openssl sha256)
    key_pubkey=$(openssl pkey -in "$CA_DIR/ca.key" -pubout | openssl sha256)
    [ "$cert_pubkey" = "$key_pubkey" ] || error "A chave privada não corresponde à CA. Use --recreate-ca."
}

create_or_reuse_ca() {
    step "CA raiz local"
    mkdir -p "$CA_DIR"

    if [ "$RECREATE_CA" = "true" ] && { [ -f "$CA_DIR/ca.crt" ] || [ -f "$CA_DIR/ca.key" ]; }; then
        warn "A CA raiz será recriada. Macs que confiavam na CA antiga precisarão importar a nova. Porque confiança digital também tem crise de relacionamento."
        confirm_or_exit "Continuar recriando a CA?"
        CA_CHANGED="true"
        rm -f "$CA_DIR/ca.crt" "$CA_DIR/ca.key" "$CA_DIR/ca.srl"
    fi

    if [ ! -f "$CA_DIR/ca.crt" ] || [ ! -f "$CA_DIR/ca.key" ]; then
        CA_CHANGED="true"
        info "Criando CA raiz local"
        cat > "$CA_DIR/ca.cnf" <<EOF_CA_CONF
[req]
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca

[dn]
CN = UniFi Local CA
O = Local Network
C = BR

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF_CA_CONF
        run_cmd openssl genrsa -out "$CA_DIR/ca.key" "$CA_KEY_BITS" >/dev/null 2>&1
        run_cmd openssl req -x509 -new -nodes \
            -key "$CA_DIR/ca.key" \
            -sha256 \
            -days "$CA_VALIDITY" \
            -out "$CA_DIR/ca.crt" \
            -config "$CA_DIR/ca.cnf" \
            -extensions v3_ca >/dev/null 2>&1
        chmod 600 "$CA_DIR/ca.key"
        chmod 644 "$CA_DIR/ca.crt"
        success "CA criada em: $CA_DIR/ca.crt"
    else
        success "CA existente reutilizada: $CA_DIR/ca.crt"
    fi
    validate_ca
    success "CA, chave e validade verificadas"
}

create_server_certificate() {
    step "Gerando certificado do servidor"
    WORK_DIR=$(mktemp -d "/tmp/${APP_NAME}_XXXXXX")

    run_cmd openssl genrsa -out "$WORK_DIR/server.key" "$SERVER_KEY_BITS" >/dev/null 2>&1

    cat > "$WORK_DIR/server.cnf" <<EOF_CONF
[req]
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
CN = ${CN}
OU = UniFi
O = Local Network
C = BR

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CN}
DNS.2 = ${SHORT_NAME}
IP.1 = ${IP}
EOF_CONF

    run_cmd openssl req -new \
        -key "$WORK_DIR/server.key" \
        -out "$WORK_DIR/server.csr" \
        -config "$WORK_DIR/server.cnf" >/dev/null 2>&1

    run_cmd openssl x509 -req \
        -in "$WORK_DIR/server.csr" \
        -CA "$CA_DIR/ca.crt" \
        -CAkey "$CA_DIR/ca.key" \
        -CAcreateserial \
        -out "$WORK_DIR/server.crt" \
        -days "$CERT_VALIDITY" \
        -sha256 \
        -extensions v3_req \
        -extfile "$WORK_DIR/server.cnf" >/dev/null 2>&1

    success "Certificado gerado"
    info "SANs incluídos:"
    openssl x509 -in "$WORK_DIR/server.crt" -noout -text 2>/dev/null | awk '/Subject Alternative Name/{getline; gsub(/^ +/, ""); print "     " $0}'
}

verify_server_certificate() {
    local cert_pubkey="" key_pubkey=""

    step "Validando certificado do servidor"
    openssl verify -CAfile "$CA_DIR/ca.crt" "$WORK_DIR/server.crt" >/dev/null \
        || error "O certificado do servidor não valida contra a CA local."
    openssl x509 -in "$WORK_DIR/server.crt" -noout -checkhost "$CN" >/dev/null \
        || error "O certificado não contém DNS:$CN no SAN."
    openssl x509 -in "$WORK_DIR/server.crt" -noout -checkhost "$SHORT_NAME" >/dev/null \
        || error "O certificado não contém DNS:$SHORT_NAME no SAN."
    openssl x509 -in "$WORK_DIR/server.crt" -noout -checkip "$IP" >/dev/null \
        || error "O certificado não contém IP:$IP no SAN."
    cert_pubkey=$(openssl x509 -in "$WORK_DIR/server.crt" -pubkey -noout | openssl sha256)
    key_pubkey=$(openssl pkey -in "$WORK_DIR/server.key" -pubout | openssl sha256)
    [ "$cert_pubkey" = "$key_pubkey" ] || error "A chave privada não corresponde ao certificado do servidor."
    success "Cadeia, SANs e chave validados"
}

import_keystore() {
    step "Importando no Java Keystore do UniFi"

    run_cmd openssl pkcs12 -export \
        -in "$WORK_DIR/server.crt" \
        -inkey "$WORK_DIR/server.key" \
        -certfile "$CA_DIR/ca.crt" \
        -out "$WORK_DIR/server.p12" \
        -name "$UNIFI_ALIAS" \
        -passout "pass:${STOREPASS}" >/dev/null 2>&1

    NEW_KEYSTORE=$(mktemp "${KEYSTORE}.new.XXXXXX")
    rm -f "$NEW_KEYSTORE"

    run_cmd keytool -importkeystore \
        -deststorepass "$STOREPASS" \
        -destkeypass "$STOREPASS" \
        -destkeystore "$NEW_KEYSTORE" \
        -srckeystore "$WORK_DIR/server.p12" \
        -srcstoretype PKCS12 \
        -srcstorepass "$STOREPASS" \
        -alias "$UNIFI_ALIAS" \
        -noprompt >/dev/null 2>&1

    run_cmd keytool -list -keystore "$NEW_KEYSTORE" -storepass "$STOREPASS" -alias "$UNIFI_ALIAS" >/dev/null 2>&1 \
        || error "O novo keystore não contém o alias '$UNIFI_ALIAS'. O keystore atual foi preservado."

    if id unifi >/dev/null 2>&1; then
        run_cmd chown unifi:unifi "$NEW_KEYSTORE"
    else
        warn "Usuário unifi não encontrado. Mantive o dono atual do keystore."
    fi
    run_cmd chmod 600 "$NEW_KEYSTORE"
    run_cmd mv "$NEW_KEYSTORE" "$KEYSTORE"
    NEW_KEYSTORE=""
    KEYSTORE_REPLACED="true"
    success "Keystore atualizado: $KEYSTORE"
}

restore_previous_keystore() {
    warn "Restaurando o keystore anterior."
    if [ "$HAD_KEYSTORE" = "true" ]; then
        cp "$BACKUP_TARGET/keystore" "$KEYSTORE" || true
    else
        rm -f "$KEYSTORE"
    fi
    KEYSTORE_REPLACED="false"
}

verify_live_unifi() {
    local expected="" served="" attempt=""

    step "Verificando certificado servido em $IP:8443"
    expected=$(openssl x509 -in "$WORK_DIR/server.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')
    for attempt in $(seq 1 30); do
        if systemctl is-active --quiet unifi; then
            served=$(openssl s_client -connect "$IP:8443" -servername "$CN" </dev/null 2>/dev/null \
                | openssl x509 -noout -fingerprint -sha256 2>/dev/null \
                | cut -d= -f2 | tr -d ':') || true
            if [ -n "$served" ] && [ "$served" = "$expected" ]; then
                success "Serviço ativo e fingerprint SHA-256 servido confirmado: $served"
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}

activate_and_verify_unifi() {
    if ! start_unifi; then
        restore_previous_keystore
        systemctl start unifi >/dev/null 2>&1 || true
        SERVICE_STOPPED="false"
        error "O UniFi não iniciou com o novo keystore; o anterior foi restaurado."
    fi
    if ! verify_live_unifi; then
        run_cmd systemctl stop unifi >/dev/null 2>&1 || true
        SERVICE_STOPPED="true"
        restore_previous_keystore
        systemctl start unifi >/dev/null 2>&1 || true
        SERVICE_STOPPED="false"
        error "O UniFi não serviu o novo certificado; o keystore anterior foi restaurado."
    fi
}

update_hosts() {
    step "Verificando /etc/hosts"
    local line="${IP}  ${CN}  ${SHORT_NAME}"

    if grep -qE "^[[:space:]]*${IP}[[:space:]].*\b${CN}\b" /etc/hosts 2>/dev/null; then
        success "/etc/hosts já possui entrada para $CN"
        return 0
    fi

    warn "Entrada não encontrada em /etc/hosts"
    echo "  Linha sugerida: ${line}"

    case "$ADD_HOSTS" in
        yes) ;;
        no) warn "Não alterei /etc/hosts por opção do usuário."; return 0 ;;
        ask) if ! confirm_optional "Adicionar ao /etc/hosts do servidor?"; then warn "Não alterei /etc/hosts."; return 0; fi ;;
    esac

    printf "%s\n" "$line" >> /etc/hosts
    success "Entrada adicionada ao /etc/hosts do servidor"
}

final_instructions() {
    echo ""
    printf "%b╔══════════════════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║        ✅ Certificado aplicado com sucesso!           ║%b\n" "$BOLD" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo ""
    printf "%b━━━ Próximos passos no Mac ━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$BOLD" "$NC"
    echo ""
    echo "1. Copie a CA raiz para o Mac:"
    printf "   %bscp root@%s:%s ~/Downloads/unifi-local-ca.crt%b\n" "$CYAN" "$IP" "$CA_DIR/ca.crt" "$NC"
    echo ""
    echo "2. Adicione ao /etc/hosts do Mac se for acessar pelo nome:"
    printf "   %bsudo sh -c 'echo \"%s  %s  %s\" >> /etc/hosts'%b\n" "$CYAN" "$IP" "$CN" "$SHORT_NAME" "$NC"
    echo ""
    echo "3. Prefira confiar a CA raiz local no Keychain:"
    printf "   %bsudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/unifi-local-ca.crt%b\n" "$CYAN" "$NC"
    echo ""
    echo "   Alternativa: importe o certificado servido pelo UniFi com trust-cert usando o mesmo endereço que será acessado:"
    printf "   %btrust-cert --host %s --port 8443%b\n" "$CYAN" "$CN" "$NC"
    printf "   %btrust-cert --host %s --port 8443%b\n" "$CYAN" "$IP" "$NC"
    echo ""
    echo "4. Acesse:"
    printf "   %bhttps://%s:8443%b\n" "$CYAN" "$CN" "$NC"
    printf "   %bhttps://%s:8443%b\n" "$CYAN" "$IP" "$NC"
    echo ""
    printf "%b━━━ Detalhes ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$BOLD" "$NC"
    echo "  CN       : $CN"
    echo "  SANs     : DNS:$CN, DNS:$SHORT_NAME, IP:$IP"
    echo "  Validade : $CERT_VALIDITY dias"
    echo "  CA raiz  : $CA_DIR/ca.crt"
    echo "  Keystore : $KEYSTORE"
    echo "  Log      : $LOG_DIR/${APP_NAME}.log"
    echo "  Backup   : $BACKUP_DIR"
    echo ""
}

main() {
    parse_args "$@"
    print_header
    require_root
    check_dependencies
    check_unifi
    collect_config
    stop_unifi
    backup_current
    create_or_reuse_ca
    create_server_certificate
    verify_server_certificate
    import_keystore
    activate_and_verify_unifi
    update_hosts
    log_msg "APPLIED cn=$CN short=$SHORT_NAME ip=$IP days=$CERT_VALIDITY ca=$CA_DIR/ca.crt keystore=$KEYSTORE"
    RUN_COMPLETE="true"
    final_instructions
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
