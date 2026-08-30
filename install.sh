#!/usr/bin/env bash
# =============================================================================
# install.sh — Instalador versionado do SCRIPTS-CERT para macOS/Linux
# Versão  : consulte INSTALLER_VERSION ou execute --installer-version
# =============================================================================

set -euo pipefail

INSTALLER_VERSION="1.5.0"
MAX_REMOTE_VERSIONS="5"
DEFAULT_REPO="mk-tecnologia/SCRIPTS-CERT"
REPO="$DEFAULT_REPO"
GITHUB_API_BASE="${SCRIPTS_CERT_API_BASE:-https://api.github.com}"
GITHUB_RAW_BASE="${SCRIPTS_CERT_RAW_BASE:-https://raw.githubusercontent.com}"
REQUESTED_VERSION=""
ACTION="install"
ASSUME_YES="false"

DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
INSTALL_ROOT="${SCRIPTS_CERT_HOME:-${DATA_HOME}/scripts-cert}"
VERSIONS_DIR="${INSTALL_ROOT}/versions"
CURRENT_LINK="${INSTALL_ROOT}/current"
PREVIOUS_LINK="${INSTALL_ROOT}/previous"
MACOS_SYSTEM_BIN="false"
if [ -n "${SCRIPTS_CERT_BIN:-}" ]; then
    BIN_DIR="$SCRIPTS_CERT_BIN"
elif [ "$(id -u)" -eq 0 ]; then
    BIN_DIR="/usr/local/sbin"
elif [ "$(uname -s)" = "Darwin" ]; then
    BIN_DIR="/usr/local/bin"
    MACOS_SYSTEM_BIN="true"
else
    BIN_DIR="${HOME}/.local/bin"
fi
BIN_USE_SUDO="false"
if [ "$MACOS_SYSTEM_BIN" = "true" ] && [ ! -w "$BIN_DIR" ]; then
    BIN_USE_SUDO="true"
fi
SCRIPTS=(trust-cert proxmox-cert unifi-cert ucs-cert)
STAGING_DIR=""

info() { printf 'ℹ️  %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
SCRIPTS-CERT installer v${INSTALLER_VERSION}

Uso:
  ./install.sh [opções]

Opções:
  --version REF          Instala uma tag/branch/commit específica (ex.: v2.3.5)
  --list                 Lista versões publicadas no GitHub e versões locais
  --rollback             Volta para a versão anteriormente ativa
  --use VERSÃO           Ativa uma versão já instalada, sem baixar novamente
  --prune                Remove versões locais fora de ativa/anterior
  --uninstall            Remove os atalhos e todas as versões locais
  --repo DONO/REPO       Usa outro repositório GitHub
  -y, --yes              Não pede confirmação
  -h, --help             Exibe esta ajuda
  --installer-version    Exibe a versão do instalador

Sem --version, o instalador oferece as tags disponíveis. Se não houver tags,
usa a branch main. Apenas as ${MAX_REMOTE_VERSIONS} tags mais recentes são exibidas.
Localmente são preservadas somente a versão ativa e a anterior para rollback:
  ${VERSIONS_DIR}/
EOF
}

confirm() {
    local message="$1" answer=""
    [ "$ASSUME_YES" = "true" ] && return 0
    read -r -p "$message [s/N]: " answer
    case "$answer" in s|S|sim|SIM|Sim) return 0 ;; *) return 1 ;; esac
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

bin_cmd() {
    if [ "$BIN_USE_SUDO" = "true" ]; then
        require_cmd sudo
        sudo "$@"
    else
        "$@"
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --version) [ "$#" -ge 2 ] || die "Faltou o valor de --version"; REQUESTED_VERSION="$2"; shift 2 ;;
            --list) ACTION="list"; shift ;;
            --rollback) ACTION="rollback"; shift ;;
            --use) [ "$#" -ge 2 ] || die "Faltou o valor de --use"; ACTION="use"; REQUESTED_VERSION="$2"; shift 2 ;;
            --prune) ACTION="prune"; shift ;;
            --uninstall) ACTION="uninstall"; shift ;;
            --repo) [ "$#" -ge 2 ] || die "Faltou o valor de --repo"; REPO="$2"; shift 2 ;;
            -y|--yes) ASSUME_YES="true"; shift ;;
            -h|--help) usage; exit 0 ;;
            --installer-version) echo "scripts-cert-installer ${INSTALLER_VERSION}"; exit 0 ;;
            *) die "Opção desconhecida: $1" ;;
        esac
    done
    printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || die "Repositório inválido: $REPO"
}

github_tags() {
    curl -fsSL --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        "${GITHUB_API_BASE}/repos/${REPO}/tags?per_page=100" 2>/dev/null \
        | sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        | sed -n "1,${MAX_REMOTE_VERSIONS}p"
}

local_versions() {
    [ -d "$VERSIONS_DIR" ] || return 0
    find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.staging-*' -exec basename {} \; 2>/dev/null | sort
}

cleanup_staging() {
    if [ -n "${STAGING_DIR:-}" ] && [ -d "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR"
    fi
}

link_version_name() {
    local link="$1" target=""
    [ -L "$link" ] || return 0
    target=$(readlink "$link")
    basename "$target"
}

prune_local_versions() {
    local current="" previous="" version="" directory="" removed="0"
    current=$(link_version_name "$CURRENT_LINK")
    previous=$(link_version_name "$PREVIOUS_LINK")
    [ -d "$VERSIONS_DIR" ] || return 0
    while IFS= read -r version; do
        [ -n "$version" ] || continue
        [ "$version" = "$current" ] && continue
        [ "$version" = "$previous" ] && continue
        directory="$VERSIONS_DIR/$version"
        case "$directory" in
            "$VERSIONS_DIR"/*) rm -rf "$directory" ;;
            *) die "Caminho recusado durante limpeza: $directory" ;;
        esac
        info "Versão local removida: $version"
        removed=$((removed + 1))
    done <<EOF_LOCAL
$(local_versions)
EOF_LOCAL
    if [ "$removed" -gt 0 ]; then
        ok "Limpeza concluída; ativa e anterior foram preservadas."
    fi
}

list_versions() {
    local current="" previous="" tags=""
    current=$(link_version_name "$CURRENT_LINK")
    previous=$(link_version_name "$PREVIOUS_LINK")

    echo "Versões publicadas em github.com/${REPO}:"
    tags=$(github_tags || true)
    if [ -n "$tags" ]; then printf '  %s\n' $tags; else echo "  (nenhuma tag; main está disponível)"; fi
    echo ""
    echo "Versões instaladas localmente:"
    if [ -d "$VERSIONS_DIR" ] && [ -n "$(local_versions)" ]; then
        while IFS= read -r version; do
            if [ "$version" = "$current" ]; then
                echo "  $version  [ativa]"
            elif [ "$version" = "$previous" ]; then
                echo "  $version  [anterior]"
            else
                echo "  $version"
            fi
        done <<EOF_LOCAL
$(local_versions)
EOF_LOCAL
    else
        echo "  (nenhuma)"
    fi
}

select_remote_version() {
    local tags="" choice="" count="0" version=""
    [ -n "$REQUESTED_VERSION" ] && return 0
    tags=$(github_tags || true)
    if [ -z "$tags" ]; then
        REQUESTED_VERSION="main"
        warn "O repositório ainda não possui tags; instalando a branch main."
        return 0
    fi
    if [ "$ASSUME_YES" = "true" ]; then
        REQUESTED_VERSION=$(printf '%s\n' "$tags" | sed -n '1p')
        return 0
    fi
    echo "Versões disponíveis:"
    while IFS= read -r version; do
        count=$((count + 1))
        echo "  $count) $version"
    done <<EOF_TAGS
$tags
EOF_TAGS
    echo "  0) main (desenvolvimento)"
    read -r -p "Escolha uma versão [1]: " choice
    choice="${choice:-1}"
    if [ "$choice" = "0" ]; then REQUESTED_VERSION="main"; return 0; fi
    printf '%s' "$choice" | grep -Eq '^[0-9]+$' || die "Escolha inválida: $choice"
    REQUESTED_VERSION=$(printf '%s\n' "$tags" | sed -n "${choice}p")
    [ -n "$REQUESTED_VERSION" ] || die "Escolha fora da lista: $choice"
}

download_script() {
    local ref="$1" name="$2" destination="$3"
    curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
        "${GITHUB_RAW_BASE}/${REPO}/${ref}/${name}.sh" \
        -o "$destination"
}

detect_package_version() {
    local directory="$1" detected=""
    detected=$(sed -n 's/^APP_VERSION="\([^"]*\)"/\1/p' "$directory/trust-cert.sh" | sed -n '1p')
    [ -n "$detected" ] && printf 'v%s' "$detected" || printf '%s' "$REQUESTED_VERSION"
}

activate_version() {
    local version="$1" target="" current=""
    target="$VERSIONS_DIR/$version"
    [ -d "$target" ] || die "Versão local não encontrada: $version"
    current=$(link_version_name "$CURRENT_LINK")
    if [ -n "$current" ] && [ "$current" != "$version" ]; then
        ln -sfn "$VERSIONS_DIR/$current" "$PREVIOUS_LINK"
    fi
    ln -sfn "$target" "$CURRENT_LINK"
    bin_cmd mkdir -p "$BIN_DIR"
    for name in "${SCRIPTS[@]}"; do
        bin_cmd ln -sfn "$CURRENT_LINK/${name}.sh" "$BIN_DIR/$name"
    done
    if [ -f "$0" ] && { [ ! -f "$INSTALL_ROOT/install.sh" ] || [ ! "$0" -ef "$INSTALL_ROOT/install.sh" ]; }; then
        cp "$0" "$INSTALL_ROOT/install.sh"
        chmod 755 "$INSTALL_ROOT/install.sh"
    fi
    [ -f "$INSTALL_ROOT/install.sh" ] && bin_cmd ln -sfn "$INSTALL_ROOT/install.sh" "$BIN_DIR/scripts-cert-installer"
    ok "Versão ativa: $version"
    prune_local_versions
}

install_version() {
    local staging="" package_version="" destination=""
    require_cmd curl
    require_cmd sed
    require_cmd grep
    select_remote_version
    info "Baixando ${REPO}@${REQUESTED_VERSION}"
    mkdir -p "$VERSIONS_DIR"
    staging=$(mktemp -d "$VERSIONS_DIR/.staging-XXXXXX")
    STAGING_DIR="$staging"
    trap cleanup_staging EXIT INT TERM
    for name in "${SCRIPTS[@]}"; do
        destination="$staging/${name}.sh"
        download_script "$REQUESTED_VERSION" "$name" "$destination"
        bash -n "$destination" || die "Falha de sintaxe em ${name}.sh"
        chmod 755 "$destination"
    done
    package_version=$(detect_package_version "$staging")
    [ -n "$package_version" ] || die "Não foi possível identificar a versão baixada."
    if [ -d "$VERSIONS_DIR/$package_version" ]; then
        warn "A versão $package_version já está instalada; ativando a cópia local preservada."
        cleanup_staging
        STAGING_DIR=""
        trap - EXIT INT TERM
        activate_version "$package_version"
        return 0
    fi
    printf '%s\n' "$REPO@$REQUESTED_VERSION" > "$staging/SOURCE_REF"
    mv "$staging" "$VERSIONS_DIR/$package_version"
    staging=""
    STAGING_DIR=""
    trap - EXIT INT TERM
    activate_version "$package_version"
    echo ""
    ok "Instalação concluída em $VERSIONS_DIR/$package_version"
    if ! printf '%s' ":${PATH}:" | grep -Fq ":${BIN_DIR}:"; then
        warn "$BIN_DIR não está no PATH. Adicione ao perfil do shell:"
        echo "  export PATH=\"${BIN_DIR}:\$PATH\""
    else
        ok "Comandos disponíveis em $BIN_DIR"
    fi
}

rollback_version() {
    local current="" previous=""
    current=$(link_version_name "$CURRENT_LINK")
    previous=$(link_version_name "$PREVIOUS_LINK")
    [ -n "$previous" ] || die "Não há versão anterior registrada para rollback."
    [ -d "$VERSIONS_DIR/$previous" ] || die "Arquivos da versão anterior não foram encontrados: $previous"
    ln -sfn "$VERSIONS_DIR/$previous" "$CURRENT_LINK"
    if [ -n "$current" ] && [ -d "$VERSIONS_DIR/$current" ]; then
        ln -sfn "$VERSIONS_DIR/$current" "$PREVIOUS_LINK"
    fi
    ok "Rollback concluído: $previous está ativa."
    prune_local_versions
}

uninstall_all() {
    local name="" directory="" link="" target=""
    local bin_directories=("$BIN_DIR" "${HOME}/.local/bin" "/usr/local/bin" "/usr/local/sbin")
    confirm "Remover todos os scripts e versões de $INSTALL_ROOT?" || { warn "Cancelado."; return 0; }

    for directory in "${bin_directories[@]}"; do
        for name in "${SCRIPTS[@]}" scripts-cert-installer; do
            link="$directory/$name"
            [ -L "$link" ] || continue
            target=$(readlink "$link")
            case "$target" in
                "$INSTALL_ROOT"/*)
                    if [ -w "$directory" ]; then
                        rm -f "$link"
                    else
                        require_cmd sudo
                        sudo rm -f "$link"
                    fi
                    ;;
                *) warn "Atalho não gerenciado preservado: $link" ;;
            esac
        done
    done

    case "$INSTALL_ROOT" in
        "${DATA_HOME}/scripts-cert"|"${SCRIPTS_CERT_HOME:-__unset__}") rm -rf "$INSTALL_ROOT" ;;
        *) die "Diretório personalizado não removido por segurança: $INSTALL_ROOT" ;;
    esac
    ok "SCRIPTS-CERT e seus atalhos foram removidos."
    info "Certificados, CAs, backups e logs criados durante o uso foram preservados."
}

main() {
    parse_args "$@"
    case "$ACTION" in
        install) install_version ;;
        list) require_cmd curl; list_versions ;;
        rollback) rollback_version ;;
        use) activate_version "$REQUESTED_VERSION" ;;
        prune) prune_local_versions ;;
        uninstall) uninstall_all ;;
        *) die "Ação inválida: $ACTION" ;;
    esac
}

main "$@"
