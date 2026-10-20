# =============================================================================
#  Habitica CLI - Configuracion y credenciales
# =============================================================================

$script:ConfigFileName = 'config.json'
$script:StateFileName = 'state.json'
$script:UserCacheFileName = 'user-cache.json'
$script:ContentCacheFileName = 'content-cache.json'
$script:ConfigVersion = 1

function Get-HabiticaConfigDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:HABITICA_CLI_HOME)) {
        return $env:HABITICA_CLI_HOME
    }

    $base = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = [Environment]::GetFolderPath('ApplicationData')
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = $HOME
    }
    return (Join-Path $base 'HabiticaCLI')
}

function Get-HabiticaConfigPath {
    return (Join-Path (Get-HabiticaConfigDirectory) $script:ConfigFileName)
}

function Get-HabiticaStatePath {
    return (Join-Path (Get-HabiticaConfigDirectory) $script:StateFileName)
}

function Get-HabiticaUserCachePath {
    return (Join-Path (Get-HabiticaConfigDirectory) $script:UserCacheFileName)
}

function Get-HabiticaContentCachePath {
    return (Join-Path (Get-HabiticaConfigDirectory) $script:ContentCacheFileName)
}

function Protect-HabiticaFile {
    param([Parameter(Mandatory)][string]$Path)

    if ($env:OS -ne 'Windows_NT') { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $security = New-Object System.Security.AccessControl.FileSecurity
        $security.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $security.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    }
    catch {
        # Si no se pueden ajustar los permisos, el archivo sigue siendo valido.
    }
}

function Protect-HabiticaSecret {
    param([Parameter(Mandatory)][string]$PlainText)

    try {
        $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
        return (ConvertFrom-SecureString -SecureString $secure)
    }
    catch {
        # Ultimo recurso: base64 (solo si DPAPI no esta disponible).
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
        return ('b64:' + [Convert]::ToBase64String($bytes))
    }
}

function Unprotect-HabiticaSecret {
    param([Parameter(Mandatory)][string]$CipherText)

    if ([string]::IsNullOrWhiteSpace($CipherText)) { return '' }

    if ($CipherText.StartsWith('b64:')) {
        $bytes = [Convert]::FromBase64String($CipherText.Substring(4))
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    $bstr = [IntPtr]::Zero
    try {
        $secure = ConvertTo-SecureString -String $CipherText
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    catch {
        return ''
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Read-HabiticaConfigFile {
    $path = Get-HabiticaConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        $raw = [System.IO.File]::ReadAllText($path)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Save-HabiticaConfigFile {
    param([Parameter(Mandatory)]$Data)

    $directory = Get-HabiticaConfigDirectory
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $path = Get-HabiticaConfigPath
    $json = $Data | ConvertTo-Json -Depth 10
    $temporary = '{0}.tmp-{1}' -f $path, [Guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $path) {
        [System.IO.File]::Replace($temporary, $path, $null)
    }
    else {
        [System.IO.File]::Move($temporary, $path)
    }
    Protect-HabiticaFile -Path $path
}

function Initialize-HabiticaConfig {
    $file = Read-HabiticaConfigFile

    $userId = ''
    $apiToken = ''
    $clientId = ''
    $baseUrl = 'https://habitica.com/api/v3'
    $timeoutSec = 30

    if ($file) {
        if ($file.PSObject.Properties['userId']) { $userId = [string]$file.userId }
        if ($file.PSObject.Properties['apiToken'] -and $file.apiToken) { $apiToken = Unprotect-HabiticaSecret -CipherText ([string]$file.apiToken) }
        if ($file.PSObject.Properties['clientId']) { $clientId = [string]$file.clientId }
        if ($file.PSObject.Properties['baseUrl'] -and $file.baseUrl) { $baseUrl = [string]$file.baseUrl }
        if ($file.PSObject.Properties['timeoutSec'] -and $file.timeoutSec) { $timeoutSec = [int]$file.timeoutSec }
    }

    # Las variables de entorno tienen prioridad absoluta.
    if (-not [string]::IsNullOrWhiteSpace($env:HABITICA_USER_ID)) { $userId = $env:HABITICA_USER_ID }
    if (-not [string]::IsNullOrWhiteSpace($env:HABITICA_API_TOKEN)) { $apiToken = $env:HABITICA_API_TOKEN }
    if (-not [string]::IsNullOrWhiteSpace($env:HABITICA_CLIENT_ID)) { $clientId = $env:HABITICA_CLIENT_ID }
    if (-not [string]::IsNullOrWhiteSpace($env:HABITICA_BASE_URL)) { $baseUrl = $env:HABITICA_BASE_URL }
    if (-not [string]::IsNullOrWhiteSpace($env:HABITICA_TIMEOUT) -and $env:HABITICA_TIMEOUT -match '^\d+$') { $timeoutSec = [int]$env:HABITICA_TIMEOUT }

    if ([string]::IsNullOrWhiteSpace($clientId) -and -not [string]::IsNullOrWhiteSpace($userId)) {
        $clientId = '{0}-habitica-cli' -f $userId
    }

    $script:Config = @{
        UserId     = $userId
        ApiToken   = $apiToken
        ClientId   = $clientId
        BaseUrl    = $baseUrl.TrimEnd('/')
        TimeoutSec = $timeoutSec
        ConfigFile = Get-HabiticaConfigPath
    }
}

function Assert-HabiticaConfigured {
    if ($null -eq $script:Config) { Initialize-HabiticaConfig }

    if ([string]::IsNullOrWhiteSpace($script:Config.UserId)) {
        throw [System.InvalidOperationException]::new(
            'Falta el User ID. Ejecuta "h config init" o define HABITICA_USER_ID.'
        )
    }
    if ([string]::IsNullOrWhiteSpace($script:Config.ApiToken)) {
        throw [System.InvalidOperationException]::new(
            'Falta el API Token. Ejecuta "h config init" o define HABITICA_API_TOKEN.'
        )
    }
    if ([string]::IsNullOrWhiteSpace($script:Config.ClientId)) {
        $script:Config.ClientId = '{0}-habitica-cli' -f $script:Config.UserId
    }
}

function Get-HabiticaHeaders {
    Assert-HabiticaConfigured
    return @{
        'x-api-user' = [string]$script:Config.UserId
        'x-api-key'  = [string]$script:Config.ApiToken
        'x-client'   = [string]$script:Config.ClientId
        'Accept'     = 'application/json'
    }
}

function Get-HabiticaConfig {
    <#
    .SYNOPSIS
      Muestra la configuracion actual. El token aparece enmascarado.
    #>
    param()

    if ($null -eq $script:Config) { Initialize-HabiticaConfig }

    $masked = ''
    if (-not [string]::IsNullOrWhiteSpace($script:Config.ApiToken)) {
        $token = [string]$script:Config.ApiToken
        if ($token.Length -ge 8) { $masked = $token.Substring(0, 4) + '****' + $token.Substring($token.Length - 2) }
        else { $masked = '****' }
    }

    [pscustomobject]@{
        PSTypeName = 'HabiticaCli.Config'
        UserId     = $script:Config.UserId
        ApiToken   = $masked
        ClientId   = $script:Config.ClientId
        BaseUrl    = $script:Config.BaseUrl
        TimeoutSec = $script:Config.TimeoutSec
        ConfigFile = $script:Config.ConfigFile
    }
}

function Set-HabiticaConfig {
    <#
    .SYNOPSIS
      Guarda las credenciales y opciones de Habitica CLI.
    .DESCRIPTION
      El token se cifra con DPAPI (Windows) antes de escribirlo a disco.
      Las variables de entorno siempre tienen prioridad sobre el archivo.
    #>
    [CmdletBinding()]
    param(
        [string]$UserId,
        [string]$ApiToken,
        [string]$ClientId,
        [string]$BaseUrl,
        [ValidateRange(5, 300)]
        [int]$TimeoutSec,
        [switch]$PassThru
    )

    if ($null -eq $script:Config) { Initialize-HabiticaConfig }

    $file = Read-HabiticaConfigFile
    $data = [ordered]@{
        version    = $script:ConfigVersion
        userId     = $script:Config.UserId
        apiToken   = $null
        clientId   = $script:Config.ClientId
        baseUrl    = $script:Config.BaseUrl
        timeoutSec = $script:Config.TimeoutSec
    }

    if ($file) {
        if ($file.PSObject.Properties['apiToken']) { $data.apiToken = $file.apiToken }
        if ($file.PSObject.Properties['clientId'] -and $file.clientId) { $data.clientId = $file.clientId }
        if ($file.PSObject.Properties['baseUrl'] -and $file.baseUrl) { $data.baseUrl = $file.baseUrl }
        if ($file.PSObject.Properties['timeoutSec'] -and $file.timeoutSec) { $data.timeoutSec = [int]$file.timeoutSec }
    }

    if ($PSBoundParameters.ContainsKey('UserId')) {
        $data.userId = $UserId
        $script:Config.UserId = $UserId
        if ([string]::IsNullOrWhiteSpace($data.clientId) -or $data.clientId -eq '') {
            $data.clientId = '{0}-habitica-cli' -f $UserId
            $script:Config.ClientId = $data.clientId
        }
    }
    if ($PSBoundParameters.ContainsKey('ApiToken')) {
        if ([string]::IsNullOrWhiteSpace($ApiToken)) {
            throw 'El API Token no puede estar vacio.'
        }
        $data.apiToken = Protect-HabiticaSecret -PlainText $ApiToken
        $script:Config.ApiToken = $ApiToken
    }
    if ($PSBoundParameters.ContainsKey('ClientId')) {
        $data.clientId = $ClientId
        $script:Config.ClientId = $ClientId
    }
    if ($PSBoundParameters.ContainsKey('BaseUrl')) {
        $data.baseUrl = $BaseUrl.TrimEnd('/')
        $script:Config.BaseUrl = $data.baseUrl
    }
    if ($PSBoundParameters.ContainsKey('TimeoutSec')) {
        $data.timeoutSec = $TimeoutSec
        $script:Config.TimeoutSec = $TimeoutSec
    }

    if ([string]::IsNullOrWhiteSpace($data.clientId) -and -not [string]::IsNullOrWhiteSpace($data.userId)) {
        $data.clientId = '{0}-habitica-cli' -f $data.userId
        $script:Config.ClientId = $data.clientId
    }

    Save-HabiticaConfigFile -Data $data

    if ($PassThru) { return (Get-HabiticaConfig) }
}

function Reset-HabiticaConfig {
    <#
    .SYNOPSIS
      Elimina el archivo de configuracion local.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $path = Get-HabiticaConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        Write-HabiticaWarn 'No hay configuracion guardada.'
        return
    }

    if ($PSCmdlet.ShouldProcess($path, 'Eliminar configuracion')) {
        Remove-Item -LiteralPath $path -Force
        Initialize-HabiticaConfig
        Write-HabiticaOk 'Configuracion eliminada.'
    }
}

function Test-HabiticaConnection {
    <#
    .SYNOPSIS
      Comprueba que las credenciales funcionan contra Habitica.
    .PARAMETER Quiet
      Devuelve solo $true o $false.
    #>
    [CmdletBinding()]
    param([switch]$Quiet)

    try {
        Assert-HabiticaConfigured
        $response = Invoke-HabiticaApi -Method GET -Path 'user' -Query @{ userFields = 'profile,stats' } -NoRetry -Full
        if ($Quiet) { return $true }

        $data = $response.data
        $name = Get-HabiticaPropertyText -Object (Get-HabiticaObjectValue $data 'profile') -Name 'name' -Default 'Heroe'
        $level = Get-HabiticaObjectValue (Get-HabiticaObjectValue $data 'stats') 'lvl' 0

        [pscustomobject]@{
            PSTypeName = 'HabiticaCli.ConnectionTest'
            Success    = $true
            Name       = $name
            Level      = $level
            UserId     = Get-HabiticaObjectValue $data '_id'
            Message    = 'Credenciales validas.'
        }
    }
    catch {
        if ($Quiet) { return $false }
        throw
    }
}

function Invoke-HabiticaSetup {
    <#
    .SYNOPSIS
      Asistente interactivo para configurar las credenciales.
    #>
    [CmdletBinding()]
    param()

    $width = Get-TerminalWidth
    Write-HabiticaBlank
    Write-HabiticaLine "~gold~  CONFIGURACION DE HABITICA CLI~/~"
    Write-HabiticaLine "  ~gray~Consigue tus datos en Habitica -> Ajustes -> API~/~"
    Write-HabiticaBlank
    Write-HabiticaLine "  ~gray~1.~/~ User ID (UUID de tu cuenta)"
    Write-HabiticaLine "  ~gray~2.~/~ API Token (Ajustes -> API -> Show API Token)"
    Write-HabiticaLine "  ~gray~3.~/~ Client ID (puede ser tu User ID + nombre de app)"
    Write-HabiticaBlank

    $userId = Read-Host '  User ID'
    if ([string]::IsNullOrWhiteSpace($userId)) {
        Write-HabiticaError 'El User ID es obligatorio.'
        return
    }

    $secureToken = Read-Host '  API Token' -AsSecureString
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $apiToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }

    if ([string]::IsNullOrWhiteSpace($apiToken)) {
        Write-HabiticaError 'El API Token es obligatorio.'
        return
    }

    $defaultClient = '{0}-habitica-cli' -f $userId.Trim()
    $clientId = Read-Host ("  Client ID [{0}]" -f $defaultClient)
    if ([string]::IsNullOrWhiteSpace($clientId)) { $clientId = $defaultClient }

    Set-HabiticaConfig -UserId $userId.Trim() -ApiToken $apiToken.Trim() -ClientId $clientId.Trim()

    Write-HabiticaBlank
    Write-HabiticaInfo 'Verificando credenciales...'
    try {
        $test = Test-HabiticaConnection
        Write-HabiticaOk ("Conectado como {0} (nivel {1})." -f $test.Name, $test.Level)
    }
    catch {
        Write-HabiticaError ("No se pudo verificar la conexion: {0}" -f $_.Exception.Message)
    }

    Write-HabiticaBlank
    Write-HabiticaInfo ("Configuracion guardada en {0}" -f (Get-HabiticaConfigPath))
    Write-HabiticaInfo 'Prueba ahora:  h today   |   h ui   |   h help'
    Write-HabiticaBlank
}
