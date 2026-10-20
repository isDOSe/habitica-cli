[CmdletBinding()]
param(
    [switch]$AddToProfile,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'habitica-cli.psd1'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "No se encontro el manifiesto del modulo en: $modulePath"
}

Write-Host ''
Write-Host '  HABITICA CLI - INSTALADOR' -ForegroundColor Yellow
Write-Host '  --------------------------'
Write-Host ''

Import-Module $modulePath -Force
Write-Host ('  [OK] Modulo cargado: {0}' -f $modulePath) -ForegroundColor Green
Write-Host ('  [i]  Version: {0}' -f (Get-Module habitica-cli).Version)
Write-Host ''

$importLine = "Import-Module '{0}'  # Habitica CLI" -f $modulePath

if (-not $AddToProfile) {
    Write-Host '  Para cargarlo automaticamente, agrega esta linea a tu perfil:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('    {0}' -f $importLine) -ForegroundColor White
    Write-Host ''
    Write-Host '  Ruta del perfil:' -ForegroundColor Cyan
    Write-Host ('    {0}' -f $PROFILE)
    Write-Host ''
    Write-Host '  O ejecuta:' -ForegroundColor Cyan
    Write-Host '    .\install.ps1 -AddToProfile'
    Write-Host ''
    Write-Host '  Siguiente paso:  h config init'
    Write-Host ''
    return
}

if (-not (Test-Path -LiteralPath $PROFILE)) {
    $profileDirectory = Split-Path -Parent $PROFILE
    if ($profileDirectory -and -not (Test-Path -LiteralPath $profileDirectory)) {
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    }
}

$profileContent = ''
if (Test-Path -LiteralPath $PROFILE) {
    $profileContent = [System.IO.File]::ReadAllText($PROFILE)
}

if ($profileContent -and $profileContent.Contains($modulePath)) {
    Write-Host '  [i] El perfil ya importa este modulo.' -ForegroundColor Cyan
    Write-Host ''
    return
}

if (-not $Force) {
    $answer = Read-Host ('  Anadir la importacion a {0}? [s/N]' -f $PROFILE)
    if ($answer -notmatch '^(s|si|y|yes)$') {
        Write-Host '  Cancelado.' -ForegroundColor Yellow
        return
    }
}

$prefix = ''
if ($profileContent -and -not $profileContent.EndsWith("`n")) { $prefix = "`r`n" }
[System.IO.File]::AppendAllText($PROFILE, ($prefix + '# Habitica CLI' + "`r`n" + $importLine + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ('  [OK] Importacion agregada a {0}' -f $PROFILE) -ForegroundColor Green
Write-Host '  Abre una nueva terminal o ejecuta:  . $PROFILE' -ForegroundColor Cyan
Write-Host '  Siguiente paso:  h config init' -ForegroundColor Cyan
Write-Host ''
