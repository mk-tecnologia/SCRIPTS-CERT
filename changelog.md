# Changelog

## v2.5.1 — 2026-08-30

### unifi-cert.sh

- Removida a pergunta desnecessária sobre `/etc/hosts` no modo UniFi OS Server.
- Mantida a alteração explícita por meio de `--add-hosts`.

## v2.5.0 — 2026-08-30

### Instalador

- Limitada a seleção às cinco tags mais recentes publicadas no GitHub.
- Adicionada limpeza automática de versões locais, preservando apenas a ativa e a anterior para rollback.
- Adicionados `--prune` no Bash e `-Prune` no PowerShell para executar a limpeza manualmente.
- Retiradas as tags v2.4.0 e v2.4.1, substituídas pelas correções posteriores.

## v2.4.2 — 2026-08-30

### unifi-cert.sh

- Corrigida a verificação de dependências para exigir `keytool` somente no modo legado.
- Adicionado teste de regressão garantindo que o UniFi OS Server funcione sem Java.

## v2.4.1 — 2026-08-30

### unifi-cert.sh

- Adicionada detecção automática entre `uosserver.service` e `unifi.service`.
- Corrigida a execução sem `--platform` no UniFi OS Server, que exigia `keytool` incorretamente.

## v2.4.0 — 2026-08-30

### unifi-cert.sh

- Adicionado `--platform unifios-server` para instalar automaticamente certificado e chave no UniFi OS Server self-hosted.
- Adicionado `--uos-data-dir` para instalações cujo volume de dados esteja em outro caminho.
- O novo modo detecta `uosserver.service`, cria backup, reinicia o serviço, valida o fingerprint servido e executa rollback em caso de falha.
- Mantido `--platform legacy` como padrão para preservar compatibilidade.

## v2.3.5 — 2026-08-14

### Instalador

- Reforçada a desinstalação para remover atalhos gerenciados em todos os diretórios usados pelas versões atuais e anteriores.
- Adicionada proteção para preservar arquivos e atalhos que não apontam para a instalação do SCRIPTS-CERT.
- Documentado o processo de desinstalação e quais dados são preservados.

## v2.3.4 — 2026-08-14

### Instalador

- Alterada a instalação no macOS para criar os comandos em `/usr/local/bin`, tornando-os disponíveis imediatamente no terminal.
- Adicionado uso de `sudo` somente quando necessário para criar ou remover os atalhos em `/usr/local/bin`.

## v2.3.3 — 2026-08-14

### Instalador

- Alterada a instalação executada como `root` para criar os comandos em `/usr/local/sbin`, permitindo usá-los imediatamente sem configurar o `PATH`.
- Mantida a instalação em `~/.local/bin` para usuários comuns e adicionada confirmação explícita do diretório dos comandos.

## v2.3.2 — 2026-08-14

### Geral

- Simplificadas as instruções de instalação e uso no README, com fluxo rápido por equipamento.

### unifi-cert.sh

- Corrigida a detecção de `unifi.service` com `set -o pipefail`, que podia informar incorretamente que o serviço não existia.

## v2.3.1 — 2026-08-03

### ucs-cert.sh

- Corrigida atualização do SAN para localizar e alterar exclusivamente `subjectAltName` dentro da seção `[v3_req]`, permitindo configurações UCS com outras diretivas `subjectAltName` em seções diferentes.

## v2.3.0 — 2026-08-03

### Geral

- Adicionado `ucs-cert.sh` aos instaladores versionados para macOS/Linux e Windows com Git Bash.

### ucs-cert.sh

- Adicionado suporte específico ao certificado de host do Univention Corporate Server.
- Adicionadas validação do papel Primary Directory Node/DC Master, backup completo e restauração automática.
- Adicionada atualização de SAN com FQDN, nome curto e IPv4, recriação do CSR com a chave existente e renovação pela CA interna do UCS.
- Adicionadas validações de certificado/chave, `univention-certificate check` e confirmação do fingerprint realmente servido pelo Apache.

## v2.2.1 — 2026-08-01

### trust-cert.sh

- Corrigida remoção no macOS para enviar ao `security delete-certificate` fingerprints SHA-256/SHA-1 normalizados, sem `:`.
- Corrigida detecção de certificados anteriores para considerar apenas o SHA-256 e não listar o SHA-1 da mesma entrada como outro certificado.

## v2.2.0 — 2026-08-01

### Geral

- Padronizada a exibição da versão e da data de lançamento no cabeçalho e em `--version`.
- Adicionados instaladores versionados para macOS/Linux e Windows, com seleção por tag, troca de versão e rollback local.

### trust-cert.sh

- Adicionada validação do SAN para o hostname ou IP solicitado.
- Adicionada detecção de certificados anteriores com o mesmo CN no Keychain do Sistema.
- Normalizada a comparação de fingerprints SHA-1 e SHA-256 no macOS.

### proxmox-cert.sh

- Corrigida a instalação personalizada do PVE para usar `pveproxy-ssl.pem` e `pveproxy-ssl.key`.
- Corrigidas propriedade e permissões dos certificados do PBS para `root:backup` e modo `640`.
- Alterado PBS para recarregar o proxy sem interromper tarefas de backup.
- Adicionadas validação de SAN/chave, confirmação do fingerprint servido e restauração automática em caso de falha.

### unifi-cert.sh

- Adicionadas extensões explícitas e validações de chave, validade e autoridade da CA local.
- Alterada atualização do keystore para criação temporária e substituição somente após validação.
- Adicionadas confirmação do fingerprint servido, recuperação do keystore/CA e reinício de segurança em caso de falha.

## v2.1.0

### trust-cert.sh

- Adicionado índice local em `~/.local/share/trust-cert/index.tsv`.
- Alterada remoção para usar o índice local antes de consultar o servidor remoto.
- Melhorada remoção offline para certificados instalados por esta versão ou posterior.
- Substituído arquivo temporário fixo do OpenSSL por arquivo único via `mktemp`.
- Melhorada validação de hostname por labels.
- Corrigido modo interativo para perguntar a porta antes de usar o padrão `443`.
- Corrigido encerramento prematuro quando o certificado remoto não possui SAN.
- Ajustada importação no macOS para usar `trustRoot` em certificados raiz/autoassinados e `trustAsRoot` em certificados de servidor emitidos por outra CA.
- Alterada instalação no macOS para substituir a entrada existente e reaplicar a confiança quando o certificado já existe no Keychain.
- Atualizada documentação sobre execução direta, índice local e remoção.

### proxmox-cert.sh

- Removido `chmod` em certificados aplicados em `/etc/pve/nodes/...`, pois o `pmxcfs` do Proxmox pode rejeitar alteração de permissões mesmo como root.
- Ajustadas instruções finais para orientar `/etc/hosts` no Mac antes da importação por FQDN.
- Adicionada instrução explícita para importar pelo mesmo endereço que será acessado, FQDN ou IP.

### unifi-cert.sh

- Ajustadas instruções finais para orientar `/etc/hosts` no Mac antes da importação por FQDN.
- Reforçada a recomendação de confiar a CA raiz local no macOS.
- Adicionada instrução explícita para importar pelo mesmo endereço que será acessado, FQDN ou IP.

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
