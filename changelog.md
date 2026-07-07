# Changelog

## v2.1.0

### trust-cert.sh

- Adicionado índice local em `~/.local/share/trust-cert/index.tsv`.
- Alterada remoção para usar o índice local antes de consultar o servidor remoto.
- Melhorada remoção offline para certificados instalados por esta versão ou posterior.
- Substituído arquivo temporário fixo do OpenSSL por arquivo único via `mktemp`.
- Melhorada validação de hostname por labels.
- Corrigido modo interativo para perguntar a porta antes de usar o padrão `443`.
- Atualizada documentação sobre execução direta, índice local e remoção.

## v2.0.0

### trust-cert.sh

- Adicionado suporte a argumentos CLI.
- Adicionado modo `--yes`.
- Adicionado modo `--verbose`.
- Adicionado suporte a remoção com `--remove`.
- Adicionado SNI com `-servername`.
- Alterado fingerprint principal para SHA-256.
- Mantido SHA-1 para compatibilidade com `security` no macOS.
- Adicionada validação de hostname/IP.
- Adicionada validação de porta.
- Adicionada verificação de dependências.
- Adicionado backup local do certificado.
- Adicionado log local das operações.
- Adicionada exibição de Subject, Issuer, validade completa e SAN.
- Melhorado tratamento de erros.
- Adicionado tratamento de Ctrl+C.

### proxmox-cert.sh

- Adicionado script para gerar e aplicar certificado autoassinado com SAN em Proxmox VE e Proxmox Backup Server.
- Adicionado `--mode auto|pve|pbs`.
- Adicionados `--cn`, `--short`, `--ip` e `--days`.
- Adicionados `--yes`, `--verbose`, `--add-hosts` e `--no-add-hosts`.
- Adicionada detecção automática de PVE ou PBS.
- Adicionada validação de hostname, IP e validade.
- Adicionado backup organizado em `/var/backups/proxmox-cert/`.
- Adicionado log em `/var/log/proxmox-cert/proxmox-cert.log`.
- Adicionada exportação do certificado para `/root/proxmox-cert-NOME.pem`.
- Adicionadas instruções finais para uso com `trust-cert` no macOS.

### unifi-cert.sh

- Adicionado script para criar CA local, emitir certificado do servidor e importar no Java Keystore do UniFi.
- Adicionados `--cn`, `--short`, `--ip`, `--keystore`, `--storepass` e `--ca-dir`.
- Adicionados `--days`, `--ca-days` e `--recreate-ca`.
- Adicionados `--yes`, `--verbose`, `--add-hosts` e `--no-add-hosts`.
- Adicionada validação de hostname, IP e validade.
- Adicionada CA local reutilizável por padrão.
- Adicionado backup organizado em `/var/backups/unifi-cert/`.
- Adicionado log em `/var/log/unifi-cert/unifi-cert.log`.
- Adicionadas instruções finais para importar o certificado servido pelo UniFi ou confiar a CA raiz no macOS.

## v1.0.0

### trust-cert.sh

- Primeira versão interativa.
- Suporte inicial para macOS, Debian/Ubuntu, RHEL/Fedora e Arch.
