# SCRIPTS-CERT

Versão atual dos scripts: **2.4.0** — 2026-08-30. Cada script mostra sua versão e data no cabeçalho e aceita a opção `--version`.

Coleção de scripts Bash para gerar, aplicar, importar e remover certificados SSL/TLS em ambientes internos. Todos podem ser usados de forma interativa: execute o comando e responda às perguntas.

Inclui:

- `trust-cert.sh`: importa ou remove certificados SSL/TLS como confiáveis no macOS e Linux.
- `proxmox-cert.sh`: gera e aplica certificado autoassinado com SAN em Proxmox VE ou Proxmox Backup Server.
- `unifi-cert.sh`: emite certificados para UniFi Network Application legado e UniFi OS.
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

- Debian/Ubuntu com UniFi Network Application legado
- UniFi OS Server self-hosted no Linux

`ucs-cert.sh`:

- Univention Corporate Server no Primary Directory Node/DC Master

## Instalação

### Linux e macOS

Baixe e execute o instalador:

```bash
curl -fsSLo /tmp/scripts-cert-install.sh \
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-CERT/main/install.sh
bash /tmp/scripts-cert-install.sh
```

Os comandos ficam disponíveis no terminal após a instalação:

```bash
trust-cert
sudo proxmox-cert
sudo unifi-cert
sudo ucs-cert
```

No macOS, o instalador cria os comandos em `/usr/local/bin` e solicita `sudo` somente se necessário. No Linux, usa `/usr/local/sbin` quando executado como `root` e `~/.local/bin` para usuários comuns.

O instalador guarda as versões em `~/.local/share/scripts-cert/` e permite listar, trocar ou restaurar versões:

```bash
scripts-cert-installer --list
scripts-cert-installer --use v2.4.0
scripts-cert-installer --rollback
```

Para instalar diretamente uma versão publicada:

```bash
bash /tmp/scripts-cert-install.sh --version v2.4.0 --yes
```

> `proxmox-cert`, `unifi-cert` e `ucs-cert` devem ser executados no servidor correspondente. O `trust-cert` pode ser usado no computador que acessa esses servidores.

### Windows

Requer o Git for Windows, que inclui o Git Bash. No PowerShell, execute:

```powershell
$installer = "$env:TEMP\scripts-cert-install.ps1"
Invoke-WebRequest `
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-CERT/main/install.ps1 `
  -OutFile $installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
```

Para gerenciar versões:

```powershell
scripts-cert-installer -List
scripts-cert-installer -Version v2.4.0 -Yes
scripts-cert-installer -Use v2.4.0
scripts-cert-installer -Rollback
```

No Windows, os atalhos executam os scripts pelo Git Bash. Os scripts de servidor continuam destinados ao Linux, e o `trust-cert` não altera o repositório nativo de certificados do Windows.

### Desinstalação

No Linux ou macOS:

```bash
scripts-cert-installer --uninstall
```

O desinstalador pede confirmação e remove:

- os comandos `trust-cert`, `proxmox-cert`, `unifi-cert` e `ucs-cert`;
- o comando `scripts-cert-installer`;
- as versões baixadas em `~/.local/share/scripts-cert/`.

Somente atalhos que apontam para esta instalação são removidos. Arquivos com o mesmo nome que não pertencem ao SCRIPTS-CERT são preservados.

Certificados já aplicados, CAs, backups e logs também são preservados para evitar perda de acesso ou dados. Para remover um certificado confiável antes de desinstalar, use:

```bash
trust-cert --remove --host SERVIDOR --port PORTA
```

No Windows PowerShell:

```powershell
scripts-cert-installer -Uninstall
```

### Instalação manual

Se você clonou o repositório e não quer usar o instalador, dê permissão de execução:

```bash
chmod +x trust-cert.sh proxmox-cert.sh unifi-cert.sh ucs-cert.sh
```

Para instalar `trust-cert` somente para o usuário atual:

```bash
mkdir -p ~/.local/bin
cp trust-cert.sh ~/.local/bin/trust-cert
chmod +x ~/.local/bin/trust-cert
```

Para instalar os scripts de servidor no PATH administrativo:

```bash
sudo cp proxmox-cert.sh /usr/local/sbin/proxmox-cert
sudo cp unifi-cert.sh /usr/local/sbin/unifi-cert
sudo cp ucs-cert.sh /usr/local/sbin/ucs-cert
sudo chmod +x /usr/local/sbin/proxmox-cert /usr/local/sbin/unifi-cert /usr/local/sbin/ucs-cert
```

Se `~/.local/bin` não estiver no `PATH`, adicione esta linha ao `~/.zshrc` ou `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Depois, abra um novo terminal ou recarregue o arquivo correspondente. Por exemplo:

```bash
source ~/.zshrc
```

## Uso rápido

Escolha o script conforme o equipamento:

| Objetivo | Onde executar | Comando |
| --- | --- | --- |
| Confiar em um certificado | Computador cliente Linux ou macOS | `trust-cert` |
| Criar certificado para Proxmox VE/PBS | Servidor Proxmox | `sudo proxmox-cert` |
| Criar certificado para UniFi Network legado | Servidor UniFi legado | `sudo unifi-cert` |
| Criar certificado para UniFi OS Server | UniFi OS Server self-hosted | `sudo unifi-cert --platform unifios-server` |
| Renovar certificado do UCS | UCS Primary Directory Node | `sudo ucs-cert` |

O fluxo recomendado é:

1. Instale os scripts no equipamento em que serão executados.
2. Execute o comando correspondente sem opções para usar o assistente interativo.
3. Informe o nome completo do servidor, o nome curto e o endereço IP quando solicitado.
4. Revise o resumo e confirme a aplicação.
5. No computador cliente, execute `trust-cert` para confiar no certificado apresentado pelo servidor.

Exemplo: depois de configurar um Proxmox no próprio servidor, confie no certificado a partir do computador usado para acessá-lo:

```bash
# No servidor Proxmox
sudo proxmox-cert

# No computador cliente Linux ou macOS
trust-cert --host pve.lab.local --port 8006
```

Use `COMANDO --help` para consultar todas as opções e `COMANDO --version` para verificar a versão instalada.

## trust-cert

Importa ou remove certificados SSL/TLS como confiáveis no sistema operacional.

Uso interativo:

```bash
trust-cert
```

Informe o endereço e a porta do servidor quando o script solicitar. A porta padrão é `443`.

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

Uso interativo no servidor Proxmox:

```bash
sudo proxmox-cert
```

Modo direto para PVE:

```bash
sudo proxmox-cert \
  --mode pve \
  --cn pve.lab.local \
  --short pve \
  --ip 10.0.1.10
```

Modo direto para PBS:

```bash
sudo proxmox-cert \
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

Cria uma CA local e emite certificado de servidor com SAN para o UniFi Network Application legado ou para o UniFi OS Server self-hosted.

Uso interativo no servidor UniFi:

```bash
sudo unifi-cert
```

Modo direto:

```bash
sudo unifi-cert \
  --cn unifi.lab.local \
  --short unifi \
  --ip 10.0.1.30
```

Para UniFi OS Server self-hosted:

```bash
sudo unifi-cert \
  --platform unifios-server \
  --cn unifi.lab.local \
  --short unifi \
  --ip 10.0.1.30
```

O modo `unifios-server` detecta `uosserver.service`, instala o certificado no volume local, reinicia o serviço, confirma o fingerprint servido e restaura os arquivos anteriores se houver falha. Ele não se destina a CloudKey, UDM ou Cloud Gateway.

> A Ubiquiti documenta oficialmente o serviço `uosserver` e o upload de certificados pelo Control Plane, mas não documenta a substituição direta dos arquivos no volume local. Esse modo automatizado depende da estrutura atual do UniFi OS Server e pode exigir atualização se a Ubiquiti alterar seus diretórios internos.

O caminho padrão do volume é detectado nesta localização:

```text
/home/uosserver/.local/share/containers/storage/volumes/uosserver_data/_data
```

Se a instalação usa outro local, informe a raiz `_data`:

```bash
sudo unifi-cert \
  --platform unifios-server \
  --uos-data-dir /outro/caminho/_data \
  --cn unifi.lab.local \
  --short unifi \
  --ip 10.0.1.30
```

Opções:

```text
--cn FQDN              Nome completo do servidor
--short NOME           Nome curto / alias DNS extra
--ip IP                IP do servidor
--platform ALVO        legacy ou unifios-server
--uos-data-dir CAMINHO Volume de dados do UniFi OS Server
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

Comportamento comum aos dois modos:

- Cria uma CA local em `/etc/ssl/unifi-ca/`.
- Reutiliza a mesma CA nas próximas renovações.
- Gera certificado do servidor com SAN.
- Valida a CA, a cadeia, os SANs e a correspondência das chaves.

No modo `legacy`:

- Converte o certificado para PKCS#12.
- Importa no Java Keystore do UniFi.
- Faz backup do keystore e da CA.
- Cria e valida um keystore temporário antes de substituir o arquivo usado pelo UniFi.
- Confirma o fingerprint servido na porta 8443 e restaura o keystore/CA anterior em caso de falha.

No modo `unifios-server`:

- Exige uma instalação Linux com `uosserver.service` e usuário `uosserver`.
- Instala automaticamente `unifi-core.crt` e `unifi-core.key` no volume local.
- Faz backup dos certificados anteriores e da CA.
- Reinicia o serviço e procura o novo fingerprint nas portas 443 e 11443.
- Restaura os arquivos anteriores automaticamente se a inicialização ou a verificação falhar.

Arquivos:

```text
Log      : /var/log/unifi-cert/unifi-cert.log
Backups  : /var/backups/unifi-cert/
CA raiz  : /etc/ssl/unifi-ca/ca.crt
Keystore : /var/lib/unifi/keystore
UniFi OS : /home/uosserver/.local/share/containers/storage/volumes/uosserver_data/_data/unifi-core/config/
```

## ucs-cert

Corrige o SAN e renova o certificado de host pela CA interna do Univention Corporate Server. Deve ser executado no Primary Directory Node, anteriormente chamado de DC Master.

Uso interativo no servidor UCS Primary Directory Node:

```bash
sudo ucs-cert
```

Modo direto:

```bash
sudo ucs-cert \
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
