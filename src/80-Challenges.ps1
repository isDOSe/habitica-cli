# =============================================================================
#  Habitica CLI - Retos (challenges)
# =============================================================================

function ConvertTo-HabiticaChallenge {
    param([Parameter(Mandatory)]$Challenge)

    $id = [string](Get-HabiticaObjectValue $Challenge 'id' (Get-HabiticaObjectValue $Challenge '_id' ''))
    $group = Get-HabiticaObjectValue $Challenge 'group' $null
    $leader = Get-HabiticaObjectValue $Challenge 'leader' $null

    $groupName = ''
    if ($group -is [string]) { $groupName = $group }
    else { $groupName = [string](Get-HabiticaObjectValue $group 'name' '') }

    $leaderName = ''
    if ($leader -is [string]) { $leaderName = $leader }
    else {
        $leaderProfile = Get-HabiticaObjectValue $leader 'profile' $null
        $leaderName = [string](Get-HabiticaObjectValue $leaderProfile 'name' '')
    }

    [pscustomobject]@{
        PSTypeName  = 'HabiticaCli.Challenge'
        Id          = $id
        Name        = [string](Get-HabiticaObjectValue $Challenge 'name' '')
        ShortName   = [string](Get-HabiticaObjectValue $Challenge 'shortName' '')
        Summary     = [string](Get-HabiticaObjectValue $Challenge 'summary' '')
        Description = [string](Get-HabiticaObjectValue $Challenge 'description' '')
        Prize       = Get-HabiticaObjectValue $Challenge 'prize' 0
        MemberCount = Get-HabiticaObjectValue $Challenge 'memberCount' 0
        Official    = [bool](Get-HabiticaObjectValue $Challenge 'official' $false)
        GroupId     = if ($group -is [string]) { $group } else { [string](Get-HabiticaObjectValue $group '_id' (Get-HabiticaObjectValue $group 'id' '')) }
        GroupName   = $groupName
        LeaderId    = if ($leader -is [string]) { $leader } else { [string](Get-HabiticaObjectValue $leader '_id' '') }
        LeaderName  = $leaderName
        Categories  = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $Challenge 'categories' $null))
        Raw         = $Challenge
    }
}

function Get-HabiticaChallengeList {
    <#
    .SYNOPSIS
      Lista retos visibles para el usuario (10 por pagina).
    .PARAMETER Member
      Solo retos en los que participas o que posees.
    .PARAMETER Owned
      Solo retos que tu creaste.
    #>
    [CmdletBinding()]
    param(
        [int]$Page = 0,
        [switch]$Member,
        [switch]$Owned,
        [string]$Search
    )

    $query = @{ page = $Page }
    if ($Member) { $query.member = 'true' }
    if ($Owned) { $query.owned = 'owned' }
    if ($Search) { $query.search = $Search }

    $data = Invoke-HabiticaApi -Method GET -Path 'challenges/user' -Query $query
    $items = @(Get-HabiticaDataCollection $data)

    $result = @($items | ForEach-Object { ConvertTo-HabiticaChallenge -Challenge $_ })
    Set-HabiticaLastList -Key 'challenges' -Tasks @($result | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Text = $_.Name; Type = 'challenge' }
    })
    return $result
}

function Get-HabiticaChallenge {
    <#
    .SYNOPSIS
      Obtiene el detalle de un reto.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    $data = Invoke-HabiticaApi -Method GET -Path ('challenges/{0}' -f [uri]::EscapeDataString($Id))
    return (ConvertTo-HabiticaChallenge -Challenge $data)
}

function Resolve-HabiticaChallengeReference {
    param([Parameter(Mandatory)][string]$Reference)

    $reference = $Reference.Trim()
    if ($reference -notmatch '\s' -and $reference.Length -ge 6) {
        try { return (Get-HabiticaChallenge -Id $reference) } catch { }
    }

    if ($reference -match '^\d+$') {
        $index = [int]$reference
        $list = Get-HabiticaLastList -Key 'challenges'
        if (-not $list) { throw "No hay una lista de retos reciente. Ejecuta 'h challenges'." }
        $item = @($list.items | Where-Object { [int]$_.index -eq $index }) | Select-Object -First 1
        if (-not $item) { throw ("El indice {0} no existe en la ultima lista de retos." -f $index) }
        return (Get-HabiticaChallenge -Id $item.id)
    }

    $challenges = @(Get-HabiticaChallengeList)
    $needle = $reference.ToLowerInvariant()
    $matches = @($challenges | Where-Object { $_.Name.ToLowerInvariant().Contains($needle) })
    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -eq 0) { throw ("No se encontro el reto '{0}'." -f $Reference) }
    throw ("'{0}' coincide con varios retos. Usa el numero de la lista o el id." -f $Reference)
}

function New-HabiticaChallenge {
    <#
    .SYNOPSIS
      Crea un reto en una party o guild.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$Name,
        [string]$ShortName,
        [string]$Summary,
        [string]$Description,
        [int]$Prize = 0
    )

    if ([string]::IsNullOrWhiteSpace($ShortName)) {
        $ShortName = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        if ([string]::IsNullOrWhiteSpace($ShortName)) { $ShortName = 'reto' }
    }

    $challengeBody = @{
        group     = $GroupId
        name      = $Name
        shortName = $ShortName
        prize     = $Prize
    }
    if (-not [string]::IsNullOrWhiteSpace($Summary)) { $challengeBody.summary = $Summary }
    if (-not [string]::IsNullOrWhiteSpace($Description)) { $challengeBody.description = $Description }
    $body = @{ challenge = $challengeBody }

    if ($PSCmdlet.ShouldProcess("Reto '$Name'", 'Crear')) {
        $data = Invoke-HabiticaApi -Method POST -Path 'challenges' -Body $body
        Write-HabiticaOk ("Reto creado: {0}" -f $Name)
        return (ConvertTo-HabiticaChallenge -Challenge $data)
    }
}

function Set-HabiticaChallenge {
    <#
    .SYNOPSIS
      Actualiza nombre, resumen o descripcion de un reto.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Name,
        [string]$Summary,
        [string]$Description
    )

    $challenge = @{}
    if ($PSBoundParameters.ContainsKey('Name')) { $challenge.name = $Name }
    if ($PSBoundParameters.ContainsKey('Summary')) { $challenge.summary = $Summary }
    if ($PSBoundParameters.ContainsKey('Description')) { $challenge.description = $Description }
    if ($challenge.Count -eq 0) { throw 'Indica --name, --summary o --description.' }

    if ($PSCmdlet.ShouldProcess("Reto '$Id'", 'Actualizar')) {
        $data = Invoke-HabiticaApi -Method PUT -Path ('challenges/{0}' -f [uri]::EscapeDataString($Id)) -Body @{ challenge = $challenge }
        Write-HabiticaOk 'Reto actualizado.'
        return (ConvertTo-HabiticaChallenge -Challenge $data)
    }
}

function Join-HabiticaChallenge {
    <#
    .SYNOPSIS
      Unirse a un reto.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)

    if ($PSCmdlet.ShouldProcess("Reto '$Id'", 'Unirse')) {
        $data = Invoke-HabiticaApi -Method POST -Path ('challenges/{0}/join' -f [uri]::EscapeDataString($Id))
        Write-HabiticaOk 'Te has unido al reto.'
        return $data
    }
}

function Exit-HabiticaChallenge {
    <#
    .SYNOPSIS
      Abandonar un reto.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('keep-all', 'remove-all')]
        [string]$Keep = 'keep-all',
        [switch]$Force
    )

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw 'Operacion destructiva. Usa --yes para confirmar.'
    }
    if (-not (Confirm-HabiticaAction -Message 'Abandonar este reto?' -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    if ($PSCmdlet.ShouldProcess("Reto '$Id'", 'Abandonar')) {
        $data = Invoke-HabiticaApi -Method POST -Path ('challenges/{0}/leave' -f [uri]::EscapeDataString($Id)) -Query @{ keep = $Keep }
        Write-HabiticaOk 'Has abandonado el reto.'
        return $data
    }
}

function Remove-HabiticaChallenge {
    <#
    .SYNOPSIS
      Elimina un reto que posees.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Force
    )

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw 'Operacion destructiva. Usa --yes para confirmar.'
    }
    if (-not (Confirm-HabiticaAction -Message 'Eliminar este reto y todas sus tareas?' -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    if ($PSCmdlet.ShouldProcess("Reto '$Id'", 'Eliminar')) {
        Invoke-HabiticaApi -Method DELETE -Path ('challenges/{0}' -f [uri]::EscapeDataString($Id)) | Out-Null
        Write-HabiticaOk 'Reto eliminado.'
    }
}

function Copy-HabiticaChallenge {
    <#
    .SYNOPSIS
      Clona un reto.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)

    if ($PSCmdlet.ShouldProcess("Reto '$Id'", 'Clonar')) {
        $data = Invoke-HabiticaApi -Method POST -Path ('challenges/{0}/clone' -f [uri]::EscapeDataString($Id))
        Write-HabiticaOk 'Reto clonado.'
        return (ConvertTo-HabiticaChallenge -Challenge $data)
    }
}

function Export-HabiticaChallenge {
    <#
    .SYNOPSIS
      Exporta un reto a CSV.
    .PARAMETER Path
      Archivo de destino. Si se omite, se devuelve el CSV como texto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Path
    )

    $csv = Invoke-HabiticaApi -Method GET -Path ('challenges/{0}/export/csv' -f [uri]::EscapeDataString($Id)) -AsText
    if ($Path) {
        $csv | Set-Content -LiteralPath $Path -Encoding UTF8
        Write-HabiticaOk ("CSV exportado a {0}" -f $Path)
        return (Get-Item -LiteralPath $Path)
    }
    return $csv
}

function Select-HabiticaChallengeWinner {
    <#
    .SYNOPSIS
      Declara ganador de un reto.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$WinnerId
    )

    if ($PSCmdlet.ShouldProcess("Reto '$Id'", ("Declarar ganador {0}" -f $WinnerId))) {
        $data = Invoke-HabiticaApi -Method POST -Path ('challenges/{0}/selectWinner/{1}' -f [uri]::EscapeDataString($Id), [uri]::EscapeDataString($WinnerId))
        Write-HabiticaOk 'Ganador seleccionado.'
        return $data
    }
}

function Get-HabiticaChallengeMembers {
    <#
    .SYNOPSIS
      Lista participantes de un reto.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [int]$Limit = 60
    )

    $data = Invoke-HabiticaApi -Method GET -Path ('challenges/{0}/members' -f [uri]::EscapeDataString($Id)) -Query @{ limit = $Limit }
    $items = @(ConvertTo-HabiticaArray $data)
    return @($items | ForEach-Object {
        $profile = Get-HabiticaObjectValue $_ 'profile' $null
        [pscustomobject]@{
            PSTypeName = 'HabiticaCli.Member'
            Id         = [string](Get-HabiticaObjectValue $_ '_id' (Get-HabiticaObjectValue $_ 'id' ''))
            Name       = [string](Get-HabiticaObjectValue $profile 'name' 'Heroe')
            Raw        = $_
        }
    })
}
