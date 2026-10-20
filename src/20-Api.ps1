# =============================================================================
#  Habitica CLI - Cliente HTTP para la API v3
# =============================================================================

$script:TlsInitialized = $false

function Initialize-HabiticaTls {
    if ($script:TlsInitialized) { return }
    try {
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        }
    }
    catch { }
    $script:TlsInitialized = $true
}

function Get-HabiticaQueryString {
    param([AllowNull()][hashtable]$Query)

    if ($null -eq $Query -or $Query.Count -eq 0) { return '' }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Query.Keys) {
        $value = $Query[$key]
        if ($null -eq $value) { continue }
        if ($value -is [bool]) { $value = $value.ToString().ToLowerInvariant() }
        if ($value -is [System.Array]) {
            $items = @($value | Where-Object { $null -ne $_ } | ForEach-Object { [uri]::EscapeDataString([string]$_) })
            if ($items.Count -eq 0) { continue }
            $value = ($items -join ',')
        }
        else {
            $value = [uri]::EscapeDataString([string]$value)
        }
        $parts.Add(('{0}={1}' -f [uri]::EscapeDataString([string]$key), $value))
    }
    if ($parts.Count -eq 0) { return '' }
    return ($parts -join '&')
}

function Get-HabiticaHttpErrorText {
    param([Parameter(Mandatory)]$ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    $statusCode = 0
    $bodyText = ''

    if ($response) {
        try {
            $typeName = $response.GetType().FullName
            if ($typeName -eq 'System.Net.Http.HttpResponseMessage') {
                $statusCode = [int]$response.StatusCode
                $bodyText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            elseif ($response -is [System.Net.HttpWebResponse]) {
                $statusCode = [int]$response.StatusCode
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $bodyText = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            }
            else {
                try { $statusCode = [int]$response.StatusCode } catch { }
            }
        }
        catch { }
    }

    if ([string]::IsNullOrWhiteSpace($bodyText) -and $ErrorRecord.ErrorDetails) {
        $bodyText = [string]$ErrorRecord.ErrorDetails.Message
    }
    if ([string]::IsNullOrWhiteSpace($bodyText)) {
        $bodyText = $ErrorRecord.Exception.Message
    }

    $apiMessage = ''
    if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
        try {
            $parsed = $bodyText | ConvertFrom-Json
            if ($parsed.PSObject.Properties['message'] -and $parsed.message) {
                $apiMessage = [string]$parsed.message
            }
            if ($parsed.PSObject.Properties['errors'] -and $parsed.errors) {
                $details = @($parsed.errors | ForEach-Object {
                    if ($_ -is [string]) { $_ }
                    elseif ($_.PSObject.Properties['message']) { [string]$_.message }
                } | Where-Object { $_ })
                if ($details.Count -gt 0) {
                    $apiMessage = ($apiMessage + ' ' + ($details -join ' ')).Trim()
                }
            }
        }
        catch {
            $apiMessage = $bodyText
        }
    }

    return [pscustomobject]@{
        StatusCode = $statusCode
        Body       = $bodyText
        Message    = $apiMessage
    }
}

function New-HabiticaApiError {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$ErrorId = 'HabiticaCli.ApiError',
        [System.Management.Automation.ErrorCategory]$Category = 'NotSpecified',
        [object]$TargetObject = $null
    )

    $exception = New-Object System.InvalidOperationException($Message)
    return (New-Object System.Management.Automation.ErrorRecord($exception, $ErrorId, $Category, $TargetObject))
}

function Get-HabiticaFriendlyApiMessage {
    param(
        [int]$StatusCode,
        [string]$ApiMessage
    )

    if ([string]::IsNullOrWhiteSpace($ApiMessage)) { $ApiMessage = 'La API no devolvio detalles.' }

    switch ($StatusCode) {
        400 { return ('Solicitud invalida: {0}' -f $ApiMessage) }
        401 { return ('Credenciales invalidas o sesion rechazada. Revisa "h config". Detalle: {0}' -f $ApiMessage) }
        403 { return ('Accion no permitida para tu cuenta. Detalle: {0}' -f $ApiMessage) }
        404 { return ('No encontrado: {0}' -f $ApiMessage) }
        422 { return ('Datos no validos: {0}' -f $ApiMessage) }
        429 { return ('Demasiadas peticiones a Habitica. Espera unos segundos e intentalo de nuevo. Detalle: {0}' -f $ApiMessage) }
        500 { return ('Error interno de Habitica. Intenta de nuevo mas tarde. Detalle: {0}' -f $ApiMessage) }
        502 { return ('Habitica no esta disponible (502). Intenta de nuevo en unos minutos.') }
        503 { return ('Habitica esta en mantenimiento o no disponible (503).') }
        default {
            if ($StatusCode -ge 500) { return ('Error del servidor de Habitica ({0}): {1}' -f $StatusCode, $ApiMessage) }
            return ('Error de Habitica ({0}): {1}' -f $StatusCode, $ApiMessage)
        }
    }
}

function Invoke-HabiticaApi {
    <#
    .SYNOPSIS
      Realiza una peticion autenticada a la API v3 de Habitica.
    .DESCRIPTION
      Es la base de todos los comandos y permite acceder a cualquier endpoint
      documentado, incluso los que no tienen un comando dedicado.
    .PARAMETER Method
      GET, POST, PUT o DELETE.
    .PARAMETER Path
      Ruta relativa a https://habitica.com/api/v3 (ej: tasks/user).
    .PARAMETER Body
      Objeto que se serializa como JSON.
    .PARAMETER Json
      Cuerpo JSON ya serializado.
    .PARAMETER Query
      Hashtable de parametros de consulta.
    .PARAMETER Full
      Devuelve la respuesta completa (success/data/message) en vez de solo data.
    .PARAMETER AsText
      Devuelve el cuerpo sin parsear (util para exportar CSV).
    .EXAMPLE
      Invoke-HabiticaApi -Method GET -Path 'tasks/user' -Query @{ type = 'todos' }
    .EXAMPLE
      Invoke-HabiticaApi -Method POST -Path 'tasks/user' -Body @{ text = 'Nueva'; type = 'todo' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory, Position = 1)]
        [string]$Path,

        [object]$Body,

        [string]$Json,

        [hashtable]$Query,

        [switch]$Full,

        [switch]$AsText,

        [switch]$NoRetry
    )

    Initialize-HabiticaTls
    Assert-HabiticaConfigured

    $relative = [string]$Path
    $relative = $relative.Trim()
    if ($relative.StartsWith('/')) { $relative = $relative.Substring(1) }
    if ($relative.StartsWith('api/v3/')) { $relative = $relative.Substring(7) }

    $queryString = Get-HabiticaQueryString -Query $Query
    $uri = '{0}/{1}' -f ([string]$script:Config.BaseUrl).TrimEnd('/'), $relative
    if (-not [string]::IsNullOrWhiteSpace($queryString)) {
        if ($uri.Contains('?')) { $uri += '&' + $queryString }
        else { $uri += '?' + $queryString }
    }

    $bodyText = $null
    if ($PSBoundParameters.ContainsKey('Json') -and -not [string]::IsNullOrWhiteSpace($Json)) {
        $bodyText = $Json
    }
    elseif ($PSBoundParameters.ContainsKey('Body')) {
        if ($Body -is [string] -and $Body.TrimStart().StartsWith('{')) {
            $bodyText = $Body
        }
        else {
            $bodyText = $Body | ConvertTo-Json -Depth 40 -Compress
        }
    }
    elseif ($Method -in @('POST', 'PUT')) {
        $bodyText = '{}'
    }

    $headers = Get-HabiticaHeaders
    $headers['User-Agent'] = 'HabiticaCLI/1.0 (PowerShell)'

    $attempt = 0
    $maxAttempts = 1
    if (-not $NoRetry -and $Method -eq 'GET') { $maxAttempts = 3 }

    while ($true) {
        $attempt++
        try {
            Write-Verbose ("Habitica {0} {1}" -f $Method, $relative)

            $parameters = @{
                Uri             = $uri
                Method          = $Method
                Headers         = $headers
                TimeoutSec      = [int]$script:Config.TimeoutSec
                ErrorAction     = 'Stop'
            }
            if ($PSVersionTable.PSVersion.Major -lt 6) { $parameters.UseBasicParsing = $true }
            if ($null -ne $bodyText) {
                $parameters.ContentType = 'application/json; charset=utf-8'
                $parameters.Body = $bodyText
            }

            $response = Invoke-WebRequest @parameters
            $content = [string]$response.Content
            $contentType = ''
            try { $contentType = [string]$response.Headers['Content-Type'] } catch { }

            if ($AsText) { return $content }
            if ($contentType -and $contentType -notmatch 'json') {
                return $content
            }
            if ([string]::IsNullOrWhiteSpace($content)) {
                return [pscustomobject]@{ success = $true; data = $null }
            }

            try {
                $parsed = $content | ConvertFrom-Json
            }
            catch {
                return $content
            }

            if ($parsed.PSObject.Properties['success'] -and -not $parsed.success) {
                $message = Get-HabiticaPropertyText -Object $parsed -Name 'message' -Default 'La API rechazo la operacion.'
                throw (New-HabiticaApiError -Message ("Habitica: {0}" -f $message) -ErrorId 'HabiticaCli.ApiRejected' -Category 'OperationStopped')
            }

            if ($Full) { return $parsed }
            if ($parsed.PSObject.Properties['data']) { return $parsed.data }
            return $parsed
        }
        catch {
            $errorInfo = Get-HabiticaHttpErrorText -ErrorRecord $_

            if ($errorInfo.StatusCode -eq 0) {
                # Error de red: no reintentar a ciegas.
                $message = 'No se pudo conectar con Habitica. Revisa tu conexion a Internet.'
                if ($errorInfo.Body) { $message += ' Detalle: ' + $errorInfo.Body }
                throw (New-HabiticaApiError -Message $message -ErrorId 'HabiticaCli.NetworkError' -Category 'ConnectionError')
            }

            $retryable = $errorInfo.StatusCode -in @(429, 500, 502, 503, 504)
            if ($retryable -and $attempt -lt $maxAttempts) {
                $delay = 1.5 * $attempt
                if ($errorInfo.StatusCode -eq 429) { $delay = 3 }
                Write-Verbose ("Reintentando en {0}s (HTTP {1})..." -f $delay, $errorInfo.StatusCode)
                Start-Sleep -Seconds $delay
                continue
            }

            $friendly = Get-HabiticaFriendlyApiMessage -StatusCode $errorInfo.StatusCode -ApiMessage $errorInfo.Message
            $category = [System.Management.Automation.ErrorCategory]::NotSpecified
            switch ($errorInfo.StatusCode) {
                400 { $category = 'InvalidArgument' }
                401 { $category = 'AuthenticationError' }
                403 { $category = 'PermissionDenied' }
                404 { $category = 'ObjectNotFound' }
                429 { $category = 'ResourceUnavailable' }
                default { if ($errorInfo.StatusCode -ge 500) { $category = 'ConnectionError' } }
            }
            throw (New-HabiticaApiError -Message $friendly -ErrorId ('HabiticaCli.Http{0}' -f $errorInfo.StatusCode) -Category $category -TargetObject $relative)
        }
    }
}

function Get-HabiticaDataCollection {
    param([AllowNull()]$Data)

    if ($null -eq $Data) { return @() }
    if ($Data -is [System.Array]) { return @($Data) }

    foreach ($name in @('messages', 'challenges', 'members', 'items', 'tasks', 'data')) {
        $value = Get-HabiticaObjectValue -Object $Data -Name $name -Default $null
        if ($null -ne $value -and $value -is [System.Array]) { return @($value) }
    }
    return @($Data)
}

function ConvertTo-HabiticaJson {
    param([AllowNull()]$Value, [int]$Depth = 20)
    if ($null -eq $Value) { return 'null' }
    return ($Value | ConvertTo-Json -Depth $Depth)
}
