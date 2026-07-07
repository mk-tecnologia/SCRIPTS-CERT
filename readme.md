# SCRIPTS-CERT

Coleção de scripts Bash para gerar, aplicar, importar e remover certificados SSL/TLS em ambientes internos.

Inclui:

- `trust-cert.sh`: importa ou remove certificados SSL/TLS como confiáveis no macOS e Linux.
- `proxmox-cert.sh`: gera e aplica certificado autoassinado com SAN em Proxmox VE ou Proxmox Backup Server.
- `unifi-cert.sh`: cria uma CA local, emite certificado para UniFi Network Application e importa no Java Keystore.

## Suporte

`trust-cert.sh`:

- macOS Keychain do Sistema
- Debian/Ubuntu/Linux Mint/Pop!_OS
- RHEL/CentOS/Fedora/Rocky/AlmaLinux
- Arch/Manjaro/EndeavourOS

`proxmox-cert.sh`:

- Debian/Ubuntu com Proxmox VE
- Debian/Ubuntu com Proxmox Backup Server

`unifi-cert.sh`:

- Debian/Ubuntu com UniFi Network Application

## Instalação local

Para executar diretamente deste diretório:

```bash
chmod +x trust-cert.sh proxmox-cert.sh unifi-cert.sh
```

Instalação opcional no PATH:

```bash
mkdir -p ~/.local/bin
cp trust-cert.sh ~/.local/bin/trust-cert
chmod +x ~/.local/bin/trust-cert
```

Para os scripts de servidor, use um diretório administrativo:

```bash
sudo cp proxmox-cert.sh /usr/local/sbin/proxmox-cert
sudo cp unifi-cert.sh /usr/local/sbin/unifi-cert
sudo chmod +x /usr/local/sbin/proxmox-cert /usr/local/sbin/unifi-cert
```

Se `~/.local/bin` ainda não estiver no PATH, adicione ao `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Recarregue:

```bash
source ~/.zshrc
```

## trust-cert

Importa ou remove certificados SSL/TLS como confiáveis no sistema operacional.

Uso interativo:

```bash
trust-cert
```

Uso direto:

```bash
trust-cert --host mkserver.local --port 443
trust-cert -H 10.0.1.10 -p 8443
```

Modo automático:

```bash
trust-cert --host mkserver.local --port 443 --yes
```

Remover certificado:

```bash
trust-cert --remove --host mkserver.local --port 443
```

No Linux:

```bash
sudo trust-cert --remove --host mkserver.local --port 443
```

Opções:

```text
-H, --host HOST        IP ou hostname do servidor
-p, --port PORTA       Porta do servidor (padrão: 443)
-r, --remove           Remove certificado instalado por este script
-y, --yes              Executa sem confirmação interativa
-v, --verbose          Mostra comandos e mais detalhes
-h, --help             Exibe ajuda
--version              Exibe a versão
```

A partir da v2.1.0, o script grava um índice local durante a instalação. Isso permite remover o certificado instalado mesmo que o servidor esteja offline, desde que o certificado tenha sido instalado por esta versão ou posterior. Para instalações antigas sem índice, o script ainda tenta consultar o servidor remoto para identificar o certificado.

Arquivos locais:

```text
Log     : ~/.local/state/trust-cert/trust-cert.log
Índice  : ~/.local/share/trust-cert/index.tsv
Backups : ~/.local/share/trust-cert/certs/
```

## proxmox-cert

Gera certificado autoassinado com SAN e aplica no Proxmox VE ou Proxmox Backup Server.

Modo interativo:

```bash
sudo ./proxmox-cert.sh
```

Modo direto para PVE:

```bash
sudo ./proxmox-cert.sh \
  --mode pve \
  --cn pve.lab.local \
  --short pve \
  --ip 10.0.1.10
```

Modo direto para PBS:

```bash
sudo ./proxmox-cert.sh \
  --mode pbs \
  --cn pbs.lab.local \
  --short pbs \
  --ip 10.0.1.20
```

Opções:

```text
--mode auto|pve|pbs       Ambiente alvo (padrão: auto)
--cn FQDN                 Nome completo do servidor
--short NOME              Nome curto / alias DNS
--ip IP                   IP do servidor
--days DIAS               Validade do certificado (padrão: 825)
--add-hosts               Adiciona entrada no /etc/hosts sem perguntar
--no-add-hosts            Não altera /etc/hosts
-y, --yes                 Executa sem confirmação
-v, --verbose             Mostra comandos e detalhes
-h, --help                Exibe ajuda
--version                 Exibe a versão
```

O que o script faz:

- Detecta PVE ou PBS automaticamente quando `--mode auto` é usado.
- Gera certificado autoassinado com `DNS:FQDN`, `DNS:nome-curto` e `IP:endereco`.
- Usa validade padrão de 825 dias.
- Faz backup dos certificados antigos.
- Aplica o certificado no caminho correto do PVE ou PBS.
- Reinicia `pveproxy` ou `proxmox-backup-proxy`.
- Exporta o certificado para `/root/proxmox-cert-NOME.pem`.

Arquivos:

```text
Log     : /var/log/proxmox-cert/proxmox-cert.log
Backups : /var/backups/proxmox-cert/
Export  : /root/proxmox-cert-NOME.pem
```

## unifi-cert

Cria uma CA local, emite certificado de servidor com SAN e importa no Java Keystore do UniFi.

Modo interativo:

```bash
sudo ./unifi-cert.sh
```

Modo direto:

```bash
sudo ./unifi-cert.sh \
  --cn unifi.lab.local \
  --short unifi \
  --ip 10.0.1.30
```

Opções:

```text
--cn FQDN              Nome completo do servidor
--short NOME           Nome curto / alias DNS extra
--ip IP                IP do servidor
--keystore CAMINHO     Caminho do keystore UniFi
--storepass SENHA      Senha do keystore
--ca-dir CAMINHO       Diretório da CA local
--days DIAS            Validade do certificado do servidor
--ca-days DIAS         Validade da CA raiz
--recreate-ca          Recria a CA raiz local
--add-hosts            Adiciona entrada no /etc/hosts sem perguntar
--no-add-hosts         Não altera /etc/hosts
-y, --yes              Executa sem confirmação
-v, --verbose          Mostra comandos e detalhes
-h, --help             Exibe ajuda
--version              Exibe a versão
```

O que o script faz:

- Cria uma CA local em `/etc/ssl/unifi-ca/`.
- Reutiliza a mesma CA nas próximas renovações.
- Gera certificado do servidor com SAN.
- Converte o certificado para PKCS#12.
- Importa no Java Keystore do UniFi.
- Faz backup do keystore e da CA.
- Reinicia o serviço `unifi`.

Arquivos:

```text
Log      : /var/log/unifi-cert/unifi-cert.log
Backups  : /var/backups/unifi-cert/
CA raiz  : /etc/ssl/unifi-ca/ca.crt
Keystore : /var/lib/unifi/keystore
```

## macOS

O macOS exige certificados com SAN. CN sozinho não basta.

Para Proxmox, use `trust-cert` no Mac para importar o certificado servido pelo PVE/PBS:

```bash
trust-cert --host pve.lab.local --port 8006
trust-cert --host pbs.lab.local --port 8007
```

Para UniFi, você pode importar o certificado servido pelo UniFi:

```bash
trust-cert --host unifi.lab.local --port 8443
```

Ou confiar a CA raiz gerada pelo `unifi-cert`:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/unifi-local-ca.crt
```

## Licença

MIT
