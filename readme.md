# SCRIPTS-CERT

Versão atual dos scripts: **2.3.1** — 2026-08-03. Cada script mostra sua versão e data no cabeçalho e aceita a opção `--version`.

Coleção de scripts Bash para gerar, aplicar, importar e remover certificados SSL/TLS em ambientes internos.

Inclui:

- `trust-cert.sh`: importa ou remove certificados SSL/TLS como confiáveis no macOS e Linux.
- `proxmox-cert.sh`: gera e aplica certificado autoassinado com SAN em Proxmox VE ou Proxmox Backup Server.
- `unifi-cert.sh`: cria uma CA local, emite certificado para UniFi Network Application e importa no Java Keystore.
- `ucs-cert.sh`: corrige os SANs e renova o certificado de host pela CA interna do Univention UCS.

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

`ucs-cert.sh`:

- Univention Corporate Server no Primary Directory Node/DC Master

## Instalação local

### Instalador versionado pelo GitHub

O instalador mantém cada versão em um diretório separado, registra a versão ativa e conserva a versão anterior para rollback. Tags Git como `v2.3.1` são usadas como versões publicadas; enquanto não houver tags, a branch `main` pode ser instalada.

macOS ou Linux:

```bash
curl -fsSLo /tmp/scripts-cert-install.sh \
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-CERT/main/install.sh
bash /tmp/scripts-cert-install.sh
```

Instalar diretamente uma versão publicada:

```bash
bash /tmp/scripts-cert-install.sh --version v2.3.1 --yes
```

Listar, trocar e voltar versões:

```bash
scripts-cert-installer --list
scripts-cert-installer --use v2.3.1
scripts-cert-installer --rollback
```

O comando `scripts-cert-installer` é preservado junto da instalação. As versões e o histórico ficam em `~/.local/share/scripts-cert/`.

Windows PowerShell com Git for Windows/Git Bash instalado:

```powershell
$installer = "$env:TEMP\scripts-cert-install.ps1"
Invoke-WebRequest `
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-CERT/main/install.ps1 `
  -OutFile $installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
```

Comandos de versão no Windows:

```powershell
scripts-cert-installer -List
scripts-cert-installer -Version v2.3.1 -Yes
scripts-cert-installer -Use v2.3.1
scripts-cert-installer -Rollback
```

No Windows, os atalhos chamam os arquivos Bash por meio do Git Bash. `proxmox-cert`, `unifi-cert` e `ucs-cert` continuam destinados aos respectivos servidores Linux. O `trust-cert` atualmente gerencia os repositórios de confiança do macOS e Linux; ele não importa certificados no repositório nativo do Windows.

Para publicar uma versão selecionável pelos instaladores:

```bash
git tag -a v2.3.1 -m "SCRIPTS-CERT v2.3.1"
git push origin v2.3.1
```

Depois da publicação da tag, ela aparecerá automaticamente em `--list` ou `-List`.

### Instalação manual

Para executar diretamente deste diretório:

```bash
chmod +x trust-cert.sh proxmox-cert.sh unifi-cert.sh ucs-cert.sh
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
sudo cp ucs-cert.sh /usr/local/sbin/ucs-cert
sudo chmod +x /usr/local/sbin/proxmox-cert /usr/local/sbin/unifi-cert /usr/local/sbin/ucs-cert
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

No macOS, a importação grava o certificado no Keychain do Sistema. Certificados raiz/autoassinados são adicionados como `trustRoot`; certificados de servidor emitidos por outra CA são adicionados como `trustAsRoot`. Se o certificado já existir, o script substitui a entrada e reaplica a confiança.

Quando encontra no Keychain do Sistema outro certificado com o mesmo CN e fingerprint diferente, o script mostra os fingerprints encontrados e oferece a remoção dos certificados anteriores. Por segurança, o modo `--yes` mantém certificados diferentes; execute sem `--yes` para confirmar essa limpeza interativamente. No Linux, o arquivo de destino baseado no CN já é substituído após confirmação.

Antes da importação, o script também confere se o endereço informado aparece no `Subject Alternative Name` do certificado (`DNS:nome` para hostname ou `IP Address:endereço` para IP). A confiança é aplicada ao certificado inteiro; portanto, para funcionar pelo nome e pelo IP, o certificado emitido pelo servidor deve conter ambos no SAN. A importação no cliente não consegue acrescentar identidades a um certificado já assinado.

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
- Reinicia `pveproxy` no PVE e recarrega `proxmox-backup-proxy` no PBS sem interromper backups.
- Confirma que chave e SANs são válidos e que a porta 8006/8007 está servindo o novo fingerprint.
- Restaura automaticamente o certificado anterior quando a aplicação ou a verificação falha.
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
- Valida a CA, a cadeia, os SANs e a correspondência das chaves.
- Cria e valida um keystore temporário antes de substituir o arquivo usado pelo UniFi.
- Confirma o fingerprint servido na porta 8443 e restaura o keystore/CA anterior em caso de falha.

Arquivos:

```text
Log      : /var/log/unifi-cert/unifi-cert.log
Backups  : /var/backups/unifi-cert/
CA raiz  : /etc/ssl/unifi-ca/ca.crt
Keystore : /var/lib/unifi/keystore
```

## ucs-cert

Corrige o SAN e renova o certificado de host pela CA interna do Univention Corporate Server. Deve ser executado no Primary Directory Node, anteriormente chamado de DC Master.

Modo interativo:

```bash
sudo ./ucs-cert.sh
```

Modo direto:

```bash
sudo ./ucs-cert.sh \
  --cn mkserver.cdl.intranet \
  --short mkserver \
  --ip 192.168.110.2
```

Opções:

```text
--cn FQDN          FQDN do host UCS
--short NOME       Nome curto incluído no SAN
--ip IP            IPv4 incluído no SAN
--port PORTA       Porta HTTPS verificada (padrão: 443)
--days DIAS        Validade do certificado
-y, --yes          Executa sem confirmação
-v, --verbose      Mostra os comandos executados
-h, --help         Exibe ajuda
--version          Exibe versão e data
```

O que o script faz:

- Confirma que está no Primary Directory Node/DC Master.
- Localiza `/etc/univention/ssl/FQDN/` e valida certificado e chave existentes.
- Faz backup de `openssl.cnf`, `req.pem`, `cert.pem` e `private.key`.
- Configura `DNS:FQDN`, `DNS:nome-curto` e `IP:endereço` no SAN.
- Recria o CSR usando a chave privada existente.
- Renova por `univention-certificate`, preservando a CA interna do domínio.
- Recarrega o Apache e compara o fingerprint servido com o certificado renovado.
- Restaura automaticamente os arquivos anteriores se qualquer etapa falhar.

Arquivos:

```text
Log     : /var/log/ucs-cert/ucs-cert.log
Backups : /var/backups/ucs-cert/
UCS SSL : /etc/univention/ssl/FQDN/
CA raiz : /etc/univention/ssl/ucsCA/CAcert.pem
```

## macOS

O macOS e os navegadores modernos exigem certificados com SAN. CN sozinho não basta.

Use no `trust-cert` o mesmo endereço que será usado no navegador.

Se for acessar pelo nome, adicione a resolução no Mac quando não houver DNS interno:

```bash
sudo sh -c 'echo "10.0.1.10  pve.lab.local  pve" >> /etc/hosts'
```

Para Proxmox, use `trust-cert` no Mac para importar o certificado servido pelo PVE/PBS:

```bash
trust-cert --host pve.lab.local --port 8006
trust-cert --host pbs.lab.local --port 8007
trust-cert --host 10.0.1.10 --port 8006
```

Para UniFi, você pode importar o certificado servido pelo UniFi:

```bash
trust-cert --host unifi.lab.local --port 8443
trust-cert --host 10.0.1.30 --port 8443
```

Para UCS, prefira confiar uma vez na CA raiz interna do domínio:

```bash
scp root@mkserver.cdl.intranet:/etc/univention/ssl/ucsCA/CAcert.pem \
  ~/Downloads/univention-root-ca.pem

sudo security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/Downloads/univention-root-ca.pem
```

Ou confiar a CA raiz gerada pelo `unifi-cert`:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/unifi-local-ca.crt
```

## Licença

MIT
