# =============================================================================
# install.ps1 — Instalador versionado do SCRIPTS-CERT para Windows + Git Bash
# Versão: consulte $InstallerVersion ou use -InstallerVersionOnly
# =============================================================================

[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')][string]$Version,
    [Parameter(ParameterSetName = 'Use', Mandatory = $true)][string]$Use,
    [Parameter(ParameterSetName = 'List', Mandatory = $true)][switch]$List,
    [Parameter(ParameterSetName = 'Rollback', Mandatory = $true)][switch]$Rollback,
    [Parameter(ParameterSetName = 'Uninstall', Mandatory = $true)][switch]$Uninstall,
    [string]$Repo = 'mk-tecnologia/SCRIPTS-CERT',
    [switch]$Yes,
    [switch]$InstallerVersionOnly
)

$ErrorActionPreference = 'Stop'
$InstallerVersion = '1.0.0'
$InstallRoot = if ($env:SCRIPTS_CERT_HOME) { $env:SCRIPTS_CERT_HOME } else { Join-Path $env:LOCALAPPDATA 'Programs\ScriptsCert' }
$VersionsDir = Join-Path $InstallRoot 'versions'
$BinDir = Join-Path $InstallRoot 'bin'
$CurrentFile = Join-Path $InstallRoot 'current.txt'
$PreviousFile = Join-Path $InstallRoot 'previous.txt'
$ScriptNames = @('trust-cert', 'proxmox-cert', 'unifi-cert')

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Warning $Message }

if ($InstallerVersionOnly) {
    Write-Output "scripts-cert-installer $InstallerVersion"
    exit 0
}

if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Repositorio GitHub invalido: $Repo"
}

function Confirm-Action([string]$Message) {
    if ($Yes) { return $true }
    return (Read-Host "$Message [s/N]") -match '^(s|sim)$'
}

function Get-GitHubTags {
    try {
        $headers = @{ Accept = 'application/vnd.github+json' }
        return @((Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/tags?per_page=100" -TimeoutSec 30) | ForEach-Object { $_.name })
    }
    catch {
        Write-Warn "Nao foi possivel consultar tags: $($_.Exception.Message)"
        return @()
    }
}

function Get-LocalVersions {
    if (-not (Test-Path $VersionsDir)) { return @() }
    return @(Get-ChildItem -Path $VersionsDir -Directory | Where-Object { $_.Name -notlike '.staging-*' } | Sort-Object Name | ForEach-Object { $_.Name })
}

function Read-State([string]$Path) {
    if (Test-Path $Path) { return (Get-Content -Path $Path -Raw).Trim() }
    return ''
}

function Find-GitBash {
    $candidates = @()
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($root) {
            $suffix = if ($root -eq $env:LOCALAPPDATA) { 'Programs\Git\bin\bash.exe' } else { 'Git\bin\bash.exe' }
            $candidate = Join-Path $root $suffix
            if (Test-Path $candidate) { $candidates += $candidate }
        }
    }
    if ($candidates.Count -gt 0) { return $candidates[0] }
    $command = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -match 'Git') { return $command.Source }
    throw 'Git Bash nao foi encontrado. Instale Git for Windows antes de usar estes scripts Bash.'
}

function Add-BinToUserPath {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $BinDir) {
        $newPath = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Warn "$BinDir foi adicionado ao PATH do usuario. Abra um novo terminal para utiliza-lo."
    }
}

function Write-Wrappers([string]$ActiveVersion) {
    $bash = Find-GitBash
    $versionDir = Join-Path $VersionsDir $ActiveVersion
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    foreach ($name in $ScriptNames) {
        $scriptPath = Join-Path $versionDir "$name.sh"
        $wrapperPath = Join-Path $BinDir "$name.cmd"
        $content = "@echo off`r`n`"$bash`" `"$scriptPath`" %*`r`n"
        [IO.File]::WriteAllText($wrapperPath, $content, [Text.Encoding]::ASCII)
    }
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $savedInstaller = Join-Path $InstallRoot 'install.ps1'
        if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($savedInstaller)) {
            Copy-Item -Path $PSCommandPath -Destination $savedInstaller -Force
        }
        $managerWrapper = Join-Path $BinDir 'scripts-cert-installer.cmd'
        $managerContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$savedInstaller`" %*`r`n"
        [IO.File]::WriteAllText($managerWrapper, $managerContent, [Text.Encoding]::ASCII)
    }
    Add-BinToUserPath
}

function Set-ActiveVersion([string]$TargetVersion) {
    $target = Join-Path $VersionsDir $TargetVersion
    if (-not (Test-Path $target -PathType Container)) { throw "Versao local nao encontrada: $TargetVersion" }
    $current = Read-State $CurrentFile
    if ($current -and $current -ne $TargetVersion) {
        [IO.File]::WriteAllText($PreviousFile, $current)
    }
    [IO.File]::WriteAllText($CurrentFile, $TargetVersion)
    Write-Wrappers $TargetVersion
    Write-Ok "Versao ativa: $TargetVersion"
}

function Select-RemoteVersion {
    if ($Version) { return $Version }
    $tags = @(Get-GitHubTags)
    if ($tags.Count -eq 0) {
        Write-Warn 'O repositorio ainda nao possui tags; instalando a branch main.'
        return 'main'
    }
    if ($Yes) { return $tags[0] }
    Write-Host 'Versoes disponiveis:'
    for ($index = 0; $index -lt $tags.Count; $index++) {
        Write-Host "  $($index + 1)) $($tags[$index])"
    }
    Write-Host '  0) main (desenvolvimento)'
    $choice = Read-Host 'Escolha uma versao [1]'
    if (-not $choice) { $choice = '1' }
    if ($choice -eq '0') { return 'main' }
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $tags.Count) {
        throw "Escolha invalida: $choice"
    }
    return $tags[$number - 1]
}

function Install-Version {
    $ref = Select-RemoteVersion
    $bash = Find-GitBash
    New-Item -ItemType Directory -Path $VersionsDir -Force | Out-Null
    $staging = Join-Path $VersionsDir ".staging-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        Write-Info "Baixando $Repo@$ref"
        foreach ($name in $ScriptNames) {
            $uri = "https://raw.githubusercontent.com/$Repo/$ref/$name.sh"
            $downloadedScript = Join-Path $staging "$name.sh"
            Invoke-WebRequest -Uri $uri -OutFile $downloadedScript -TimeoutSec 60
            & $bash -n $downloadedScript
            if ($LASTEXITCODE -ne 0) { throw "Falha de sintaxe em $name.sh" }
        }
        $trustContent = Get-Content -Path (Join-Path $staging 'trust-cert.sh') -Raw
        $match = [regex]::Match($trustContent, '(?m)^APP_VERSION="([^"]+)"')
        $packageVersion = if ($match.Success) { "v$($match.Groups[1].Value)" } else { $ref }
        $destination = Join-Path $VersionsDir $packageVersion
        if (Test-Path $destination) {
            Write-Warn "A versao $packageVersion ja esta instalada; ativando a copia local preservada."
            Set-ActiveVersion $packageVersion
            return
        }
        [IO.File]::WriteAllText((Join-Path $staging 'SOURCE_REF'), "$Repo@$ref`r`n")
        Move-Item -Path $staging -Destination $destination
        $staging = $null
        Set-ActiveVersion $packageVersion
        Write-Ok "Instalacao concluida em $destination"
        Write-Warn 'No Windows, os scripts executam pelo Git Bash. proxmox-cert e unifi-cert continuam destinados a servidores Linux.'
    }
    finally {
        if ($staging -and (Test-Path $staging)) { Remove-Item -Path $staging -Recurse -Force }
    }
}

function Show-Versions {
    $current = Read-State $CurrentFile
    $previous = Read-State $PreviousFile
    Write-Host "Versoes publicadas em github.com/${Repo}:"
    $tags = @(Get-GitHubTags)
    if ($tags.Count) { $tags | ForEach-Object { Write-Host "  $_" } } else { Write-Host '  (nenhuma tag; main esta disponivel)' }
    Write-Host ''
    Write-Host 'Versoes instaladas localmente:'
    $locals = @(Get-LocalVersions)
    if (-not $locals.Count) { Write-Host '  (nenhuma)'; return }
    foreach ($item in $locals) {
        if ($item -eq $current) { Write-Host "  $item  [ativa]" }
        elseif ($item -eq $previous) { Write-Host "  $item  [anterior]" }
        else { Write-Host "  $item" }
    }
}

function Invoke-Rollback {
    $current = Read-State $CurrentFile
    $previous = Read-State $PreviousFile
    if (-not $previous) { throw 'Nao ha versao anterior registrada para rollback.' }
    if (-not (Test-Path (Join-Path $VersionsDir $previous))) { throw "Arquivos da versao anterior nao encontrados: $previous" }
    [IO.File]::WriteAllText($CurrentFile, $previous)
    if ($current) { [IO.File]::WriteAllText($PreviousFile, $current) }
    Write-Wrappers $previous
    Write-Ok "Rollback concluido: $previous esta ativa."
}

function Uninstall-All {
    if (-not (Confirm-Action "Remover todas as versoes de $InstallRoot?")) { Write-Warn 'Cancelado.'; return }
    $defaultRoot = Join-Path $env:LOCALAPPDATA 'Programs\ScriptsCert'
    if ($InstallRoot -ne $defaultRoot -and -not $env:SCRIPTS_CERT_HOME) { throw "Diretorio recusado por seguranca: $InstallRoot" }
    if (Test-Path $InstallRoot) { Remove-Item -Path $InstallRoot -Recurse -Force }
    Write-Ok 'SCRIPTS-CERT removido. A entrada antiga no PATH pode ser removida nas configuracoes do Windows.'
}

switch ($PSCmdlet.ParameterSetName) {
    'Install' { Install-Version }
    'Use' { Set-ActiveVersion $Use }
    'List' { Show-Versions }
    'Rollback' { Invoke-Rollback }
    'Uninstall' { Uninstall-All }
}
