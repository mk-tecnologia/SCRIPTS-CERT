#!/usr/bin/env bash
# =============================================================================
# proxmox-cert.sh — Gerar/aplicar certificado SSL/TLS no Proxmox
# Versão  : consulte APP_VERSION abaixo ou execute --version
# Autor   : Marcos A. Campos <marcos@mktecnologia.net.br>
# Suporte : Debian/Ubuntu — Proxmox VE e Proxmox Backup Server
# Licença : MIT
# Dica    : Use Linux :)
# =============================================================================

set -euo pipefail

# ── Metadados ────────────────────────────────────────────────────────────────
APP_NAME="proxmox-cert"
APP_VERSION="2.3.0"
APP_RELEASE_DATE="2026-08-03"
CERT_VALIDITY="825"
KEY_BITS="4096"
LOG_DIR="/var/log/${APP_NAME}"
BACKUP_DIR="/var/backups/${APP_NAME}"
EXPORT_DIR="/root"

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
MODE="auto"
CN=""
SHORT_NAME=""
IP=""
ASSUME_YES="false"
VERBOSE="false"
ADD_HOSTS="ask"
WORK_DIR=""
CERT_FILE=""
KEY_FILE=""
ENV_NAME=""
PORT=""
EXPORT_PEM=""
BACKUP_TARGET=""
HAD_CERT="false"
HAD_KEY="false"

# ── Utilidades ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF_HELP
${APP_NAME} v${APP_VERSION}
Gera e aplica certificado autoassinado com SAN para Proxmox VE ou PBS.

Uso:
  ${APP_NAME} [opções]

Opções:
  --mode auto|pve|pbs       Ambiente alvo (padrão: auto)
  --cn FQDN                 Nome completo do servidor
  --short NOME              Nome curto / alias DNS
  --ip IP                   IP do servidor
  --days DIAS               Validade do certificado (padrão: 825)
  --add-hosts               Adiciona entrada no /etc/hosts sem perguntar
  --no-add-hosts            Não altera /etc/hosts
  -y, --yes                 Executa sem confirmação
  -v, --verbose             Mostra comandos e detalhes
  -h, --help                Exibe esta ajuda
  --version                 Exibe a versão

Exemplos:
  ${APP_NAME}
  ${APP_NAME} --mode pve --cn pve.lab.local --short pve --ip 10.0.1.10
  ${APP_NAME} --mode pbs --cn pbs.lab.local --short pbs --ip 10.0.1.20 -y
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
    [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    return "$exit_code"
}

on_interrupt() {
    echo ""
    warn "Operação interrompida. Ctrl+C: o extintor de incêndio emocional da linha de comando."
    cleanup
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
    step "Verificando dependências"
    require_cmd openssl
    require_cmd systemctl
    require_cmd hostname
    require_cmd awk
    require_cmd grep
    require_cmd sed
    require_cmd cut
    require_cmd tr
    require_cmd seq
    require_cmd sleep
    success "Dependências básicas disponíveis"
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
    if ! { [ "$CERT_VALIDITY" -ge 1 ] && [ "$CERT_VALIDITY" -le 825 ]; }; then
        error "Use validade entre 1 e 825 dias para certificado de servidor. macOS agradece, contrariado."
    fi
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
            --mode) [ "$#" -ge 2 ] || error "Faltou valor para --mode"; MODE="$2"; shift 2 ;;
            --cn) [ "$#" -ge 2 ] || error "Faltou valor para --cn"; CN="$2"; shift 2 ;;
            --short) [ "$#" -ge 2 ] || error "Faltou valor para --short"; SHORT_NAME="$2"; shift 2 ;;
            --ip) [ "$#" -ge 2 ] || error "Faltou valor para --ip"; IP="$2"; shift 2 ;;
            --days) [ "$#" -ge 2 ] || error "Faltou valor para --days"; CERT_VALIDITY="$2"; shift 2 ;;
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
    printf "%b║     proxmox-cert — Proxmox VE / PBS                  ║%b\n" "$BOLD" "$NC"
    printf "%b║     Versão: %-10sData: %-10s               ║%b\n" "$BOLD" "v${APP_VERSION}" "$APP_RELEASE_DATE" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo ""
}

detect_environment() {
    step "Detectando ambiente Proxmox"

    case "$MODE" in
        pve) ENV_NAME="PVE" ;;
        pbs) ENV_NAME="PBS" ;;
        auto) ;;
        *) error "Modo inválido: $MODE. Use auto, pve ou pbs." ;;
    esac

    if [ -z "$ENV_NAME" ]; then
        if systemctl list-unit-files 2>/dev/null | grep -q '^pveproxy\.service'; then
            ENV_NAME="PVE"
        elif systemctl list-unit-files 2>/dev/null | grep -q '^proxmox-backup-proxy\.service'; then
            ENV_NAME="PBS"
        elif command -v pvecm >/dev/null 2>&1 || [ -d /etc/pve ]; then
            ENV_NAME="PVE"
        elif command -v proxmox-backup-manager >/dev/null 2>&1 || [ -d /etc/proxmox-backup ]; then
            ENV_NAME="PBS"
        else
            echo "Não foi possível detectar automaticamente."
            echo "  1) Proxmox VE (PVE)"
            echo "  2) Proxmox Backup Server (PBS)"
            read -r -p "Opção [1/2]: " choice
            case "$choice" in 1) ENV_NAME="PVE" ;; 2) ENV_NAME="PBS" ;; *) error "Opção inválida." ;; esac
        fi
    fi

    if [ "$ENV_NAME" = "PVE" ]; then
        PORT="8006"
        info "Ambiente detectado: Proxmox VE (PVE)"
    else
        PORT="8007"
        info "Ambiente detectado: Proxmox Backup Server (PBS)"
    fi
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

    echo ""
    printf "%bResumo:%b\n" "$BOLD" "$NC"
    echo "  Ambiente : $ENV_NAME"
    echo "  CN/FQDN  : $CN"
    echo "  Alias DNS: $SHORT_NAME"
    echo "  IP       : $IP"
    echo "  Porta    : $PORT"
    echo "  Validade : $CERT_VALIDITY dias"
    echo "  Chave    : RSA ${KEY_BITS} bits"
    echo ""
    confirm_or_exit "Confirmar e aplicar?"
}

create_certificate() {
    step "Gerando certificado autoassinado com SAN"
    WORK_DIR=$(mktemp -d "/tmp/${APP_NAME}_XXXXXX")

    cat > "$WORK_DIR/openssl.cnf" <<EOF_CONF
[req]
default_bits = ${KEY_BITS}
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = ${CN}
O = Local Network
C = BR

[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CN}
DNS.2 = ${SHORT_NAME}
IP.1 = ${IP}
EOF_CONF

    run_cmd openssl req -x509 -newkey "rsa:${KEY_BITS}" -days "$CERT_VALIDITY" -nodes \
        -keyout "$WORK_DIR/server.key" \
        -out "$WORK_DIR/server.pem" \
        -config "$WORK_DIR/openssl.cnf" \
        -extensions v3_req >/dev/null 2>&1

    success "Certificado gerado"
    info "SANs incluídos:"
    openssl x509 -in "$WORK_DIR/server.pem" -noout -text 2>/dev/null | awk '/Subject Alternative Name/{getline; gsub(/^ +/, ""); print "     " $0}'
}

verify_generated_certificate() {
    local cert_pubkey="" key_pubkey=""

    step "Validando certificado e chave"
    run_cmd openssl x509 -in "$WORK_DIR/server.pem" -noout -checkhost "$CN" >/dev/null \
        || error "O certificado gerado não contém DNS:$CN no SAN."
    run_cmd openssl x509 -in "$WORK_DIR/server.pem" -noout -checkhost "$SHORT_NAME" >/dev/null \
        || error "O certificado gerado não contém DNS:$SHORT_NAME no SAN."
    run_cmd openssl x509 -in "$WORK_DIR/server.pem" -noout -checkip "$IP" >/dev/null \
        || error "O certificado gerado não contém IP:$IP no SAN."

    cert_pubkey=$(openssl x509 -in "$WORK_DIR/server.pem" -pubkey -noout | openssl sha256)
    key_pubkey=$(openssl pkey -in "$WORK_DIR/server.key" -pubout | openssl sha256)
    [ "$cert_pubkey" = "$key_pubkey" ] || error "A chave privada não corresponde ao certificado gerado."
    success "SANs e correspondência da chave validados"
}

backup_current() {
    local stamp
    stamp=$(date +%Y%m%d%H%M%S)
    mkdir -p "$BACKUP_DIR"
    BACKUP_TARGET=$(mktemp -d "$BACKUP_DIR/$ENV_NAME-$stamp-XXXXXX")

    if [ -f "$CERT_FILE" ]; then
        cp "$CERT_FILE" "$BACKUP_TARGET/$(basename "$CERT_FILE")"
        HAD_CERT="true"
    fi
    if [ -f "$KEY_FILE" ]; then
        cp "$KEY_FILE" "$BACKUP_TARGET/$(basename "$KEY_FILE")"
        HAD_KEY="true"
    fi
    success "Backup salvo em: $BACKUP_TARGET"
}

restore_previous_certificate() {
    warn "Restaurando certificado anterior após falha na aplicação."
    if [ "$HAD_CERT" = "true" ]; then
        cp "$BACKUP_TARGET/$(basename "$CERT_FILE")" "$CERT_FILE" || true
    else
        rm -f "$CERT_FILE"
    fi
    if [ "$HAD_KEY" = "true" ]; then
        cp "$BACKUP_TARGET/$(basename "$KEY_FILE")" "$KEY_FILE" || true
    else
        rm -f "$KEY_FILE"
    fi

    if [ "$ENV_NAME" = "PBS" ]; then
        chown root:backup "$CERT_FILE" "$KEY_FILE" 2>/dev/null || true
        chmod 640 "$CERT_FILE" "$KEY_FILE" 2>/dev/null || true
        systemctl reload proxmox-backup-proxy 2>/dev/null || true
    else
        systemctl restart pveproxy 2>/dev/null || true
    fi
}

deployment_error() {
    local message="$1"
    restore_previous_certificate
    error "$message O certificado anterior foi restaurado."
}

verify_live_certificate() {
    local expected="" served="" attempt=""

    step "Verificando certificado servido em $IP:$PORT"
    expected=$(openssl x509 -in "$WORK_DIR/server.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')
    for attempt in $(seq 1 15); do
        if systemctl is-active --quiet "$1"; then
            served=$(openssl s_client -connect "$IP:$PORT" -servername "$CN" </dev/null 2>/dev/null \
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

apply_pbs() {
    step "Aplicando certificado no PBS"

    CERT_FILE="/etc/proxmox-backup/proxy.pem"
    KEY_FILE="/etc/proxmox-backup/proxy.key"
    [ -d /etc/proxmox-backup ] || error "Diretório /etc/proxmox-backup não encontrado. Isso não parece PBS. A realidade discorda do modo escolhido."

    backup_current
    run_cmd cp "$WORK_DIR/server.pem" "$CERT_FILE" || deployment_error "Falha ao instalar o certificado do PBS."
    run_cmd cp "$WORK_DIR/server.key" "$KEY_FILE" || deployment_error "Falha ao instalar a chave do PBS."
    run_cmd chown root:backup "$CERT_FILE" "$KEY_FILE" || deployment_error "Falha ao ajustar o proprietário dos arquivos do PBS."
    run_cmd chmod 640 "$CERT_FILE" "$KEY_FILE" || deployment_error "Falha ao ajustar as permissões dos arquivos do PBS."

    run_cmd systemctl reload proxmox-backup-proxy || deployment_error "O PBS não aceitou o novo certificado."
    verify_live_certificate proxmox-backup-proxy || deployment_error "O PBS não está servindo o certificado recém-gerado."
    success "PBS recarregado com novo certificado"
}

apply_pve() {
    step "Aplicando certificado no PVE"

    local node
    node=$(hostname -s)
    CERT_FILE="/etc/pve/nodes/$node/pveproxy-ssl.pem"
    KEY_FILE="/etc/pve/nodes/$node/pveproxy-ssl.key"
    [ -d "/etc/pve/nodes/$node" ] || error "Diretório /etc/pve/nodes/$node não encontrado. Isso não parece PVE."

    backup_current
    run_cmd cp "$WORK_DIR/server.pem" "$CERT_FILE" || deployment_error "Falha ao instalar o certificado personalizado do PVE."
    run_cmd cp "$WORK_DIR/server.key" "$KEY_FILE" || deployment_error "Falha ao instalar a chave personalizada do PVE."

    run_cmd systemctl restart pveproxy || deployment_error "O PVE não aceitou o novo certificado."
    verify_live_certificate pveproxy || deployment_error "O PVE não está servindo o certificado recém-gerado."
    success "PVE reiniciado com novo certificado"
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

export_certificate() {
    EXPORT_PEM="${EXPORT_DIR}/proxmox-cert-${SHORT_NAME}.pem"
    run_cmd cp "$WORK_DIR/server.pem" "$EXPORT_PEM"
    run_cmd chmod 644 "$EXPORT_PEM"
}

final_instructions() {
    echo ""
    printf "%b╔══════════════════════════════════════════════════════╗%b\n" "$BOLD" "$NC"
    printf "%b║        ✅ Certificado aplicado com sucesso!           ║%b\n" "$BOLD" "$NC"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$BOLD" "$NC"
    echo ""
    printf "%b━━━ Próximos passos no Mac ━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$BOLD" "$NC"
    echo ""
    echo "1. Copie o certificado para o Mac:"
    printf "   %bscp root@%s:%s ~/Downloads/%s.pem%b\n" "$CYAN" "$IP" "$EXPORT_PEM" "$SHORT_NAME" "$NC"
    echo ""
    echo "2. Adicione ao /etc/hosts do Mac se for acessar pelo nome:"
    printf "   %bsudo sh -c 'echo \"%s  %s  %s\" >> /etc/hosts'%b\n" "$CYAN" "$IP" "$CN" "$SHORT_NAME" "$NC"
    echo ""
    echo "3. Importe com o trust-cert usando o mesmo endereço que será acessado:"
    printf "   %btrust-cert --host %s --port %s%b\n" "$CYAN" "$CN" "$PORT" "$NC"
    printf "   %btrust-cert --host %s --port %s%b\n" "$CYAN" "$IP" "$PORT" "$NC"
    echo ""
    echo "   Ou manualmente no Acesso às Chaves → Sistema → Sempre Confiar. Sim, o macOS faz você pedir bênção ao certificado."
    echo ""
    echo "4. Acesse:"
    printf "   %bhttps://%s:%s%b\n" "$CYAN" "$CN" "$PORT" "$NC"
    printf "   %bhttps://%s:%s%b\n" "$CYAN" "$IP" "$PORT" "$NC"
    echo ""
    printf "%b━━━ Detalhes ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$BOLD" "$NC"
    echo "  Ambiente : $ENV_NAME"
    echo "  CN       : $CN"
    echo "  SANs     : DNS:$CN, DNS:$SHORT_NAME, IP:$IP"
    echo "  Validade : $CERT_VALIDITY dias"
    echo "  Exportado: $EXPORT_PEM"
    echo "  Log      : $LOG_DIR/${APP_NAME}.log"
    echo "  Backup   : $BACKUP_DIR"
    echo ""
}

main() {
    parse_args "$@"
    print_header
    require_root
    check_dependencies
    detect_environment
    collect_config
    create_certificate
    verify_generated_certificate

    if [ "$ENV_NAME" = "PBS" ]; then
        apply_pbs
    else
        apply_pve
    fi

    update_hosts
    export_certificate
    log_msg "APPLIED env=$ENV_NAME cn=$CN short=$SHORT_NAME ip=$IP days=$CERT_VALIDITY cert=$CERT_FILE key=$KEY_FILE"
    final_instructions
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
