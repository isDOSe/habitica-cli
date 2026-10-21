# =============================================================================
#  Habitica CLI - Estado local y cache
# =============================================================================

$script:State = $null

function Read-HabiticaState {
    if ($null -ne $script:State) { return $script:State }

    $script:State = @{
        version = 1
        lists   = @{}
        chat    = @{}
        lastKey = ''
    }

    $path = Get-HabiticaStatePath
    if (-not (Test-Path -LiteralPath $path)) { return $script:State }

    try {
        $raw = [System.IO.File]::ReadAllText($path)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $script:State }
        $parsed = $raw | ConvertFrom-Json

        if ($parsed.PSObject.Properties['lists'] -and $parsed.lists) {
            $lists = @{}
            foreach ($property in $parsed.lists.PSObject.Properties) {
                $lists[$property.Name] = $property.Value
            }
            $script:State.lists = $lists
        }
        if ($parsed.PSObject.Properties['chat'] -and $parsed.chat) {
            $chat = @{}
            foreach ($property in $parsed.chat.PSObject.Properties) {
                $chat[$property.Name] = $property.Value
            }
            $script:State.chat = $chat
        }
        if ($parsed.PSObject.Properties['lastKey']) { $script:State.lastKey = [string]$parsed.lastKey }
    }
    catch {
        # Estado corrupto: se reconstruye sin afectar la sesion.
        $script:State = @{ version = 1; lists = @{}; chat = @{}; lastKey = '' }
    }

    return $script:State
}

function Save-HabiticaState {
    $state = Read-HabiticaState
    $path = Get-HabiticaStatePath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    try {
        $json = $state | ConvertTo-Json -Depth 12
        $temporary = '{0}.tmp-{1}' -f $path, [Guid]::NewGuid().ToString('N')
        [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $path) {
            [System.IO.File]::Replace($temporary, $path, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temporary, $path)
        }
    }
    catch {
        # El estado es una comodidad, no un requisito.
    }
}

function Set-HabiticaLastList {
    param(
        [Parameter(Mandatory)][string]$Key,
        [AllowEmptyCollection()][object[]]$Tasks = @()
    )

    $state = Read-HabiticaState
    $items = @()
    $index = 0
    foreach ($task in $Tasks) {
        $index++
        $items += [pscustomobject]@{
            index = $index
            id    = [string](Get-HabiticaObjectValue $task 'Id' '')
            text  = [string](Get-HabiticaObjectValue $task 'Text' '')
            type  = [string](Get-HabiticaObjectValue $task 'Type' '')
        }
    }

    $state.lists[$Key] = [pscustomobject]@{
        updatedAt = [DateTime]::UtcNow.ToString('o')
        items     = $items
    }
    $state.lastKey = $Key
    Save-HabiticaState
}

function Get-HabiticaLastList {
    param([string]$Key)

    $state = Read-HabiticaState
    if ([string]::IsNullOrWhiteSpace($Key)) { $Key = $state.lastKey }
    if ([string]::IsNullOrWhiteSpace($Key)) { return $null }
    if (-not $state.lists.ContainsKey($Key)) { return $null }
    return $state.lists[$Key]
}

function Set-HabiticaLastChat {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [AllowEmptyCollection()][object[]]$Messages = @()
    )

    $state = Read-HabiticaState
    $items = @()
    $index = 0
    foreach ($message in $Messages) {
        $index++
        $items += [pscustomobject]@{
            index     = $index
            id        = [string](Get-HabiticaObjectValue $message 'id' '')
            text      = [string](Get-HabiticaObjectValue $message 'text' '')
            timestamp = Get-HabiticaObjectValue $message 'timestamp' $null
        }
    }

    $state.chat[$GroupId] = [pscustomobject]@{
        updatedAt = [DateTime]::UtcNow.ToString('o')
        items     = $items
    }
    Save-HabiticaState
}

function Get-HabiticaLastChat {
    param([Parameter(Mandatory)][string]$GroupId)

    $state = Read-HabiticaState
    if (-not $state.chat.ContainsKey($GroupId)) { return $null }
    return $state.chat[$GroupId]
}

function Read-HabiticaUserCache {
    param([int]$MaxAgeSeconds = 30)

    $path = Get-HabiticaUserCachePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        $raw = [System.IO.File]::ReadAllText($path)
        $cache = $raw | ConvertFrom-Json
        if (-not $cache.PSObject.Properties['updatedAt'] -or -not $cache.PSObject.Properties['data']) { return $null }

        $updated = [DateTime]::Parse([string]$cache.updatedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if (([DateTime]::UtcNow - $updated.ToUniversalTime()).TotalSeconds -gt $MaxAgeSeconds) { return $null }
        return $cache.data
    }
    catch {
        return $null
    }
}

function Write-HabiticaUserCache {
    param([Parameter(Mandatory)]$Data)

    $path = Get-HabiticaUserCachePath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    try {
        $payload = [pscustomobject]@{
            updatedAt = [DateTime]::UtcNow.ToString('o')
            data      = $Data
        }
        $json = $payload | ConvertTo-Json -Depth 30
        $temporary = '{0}.tmp-{1}' -f $path, [Guid]::NewGuid().ToString('N')
        [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $path) {
            [System.IO.File]::Replace($temporary, $path, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temporary, $path)
        }
    }
    catch { }
}

function Clear-HabiticaLocalCache {
    <#
    .SYNOPSIS
      Borra la cache local de usuario y contenido (no borra credenciales).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    foreach ($path in @((Get-HabiticaUserCachePath), (Get-HabiticaContentCachePath))) {
        if (Test-Path -LiteralPath $path) {
            if ($PSCmdlet.ShouldProcess($path, 'Eliminar cache')) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-HabiticaOk 'Cache local eliminada.'
}

function Read-HabiticaContentCache {
    param([int]$MaxAgeHours = 168)

    $path = Get-HabiticaContentCachePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        $raw = [System.IO.File]::ReadAllText($path)
        $cache = $raw | ConvertFrom-Json
        if (-not $cache.PSObject.Properties['updatedAt'] -or -not $cache.PSObject.Properties['data']) { return $null }
        $updated = [DateTime]::Parse([string]$cache.updatedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if (([DateTime]::UtcNow - $updated.ToUniversalTime()).TotalHours -gt $MaxAgeHours) { return $null }
        return $cache.data
    }
    catch {
        return $null
    }
}

function Write-HabiticaContentCache {
    param([Parameter(Mandatory)]$Data)

    $path = Get-HabiticaContentCachePath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    try {
        $payload = [pscustomobject]@{
            updatedAt = [DateTime]::UtcNow.ToString('o')
            data      = $Data
        }
        $json = $payload | ConvertTo-Json -Depth 30
        $temporary = '{0}.tmp-{1}' -f $path, [Guid]::NewGuid().ToString('N')
        [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $path) {
            [System.IO.File]::Replace($temporary, $path, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temporary, $path)
        }
    }
    catch { }
}
