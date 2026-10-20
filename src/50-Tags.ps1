# =============================================================================
#  Habitica CLI - Etiquetas
# =============================================================================

function Get-HabiticaTag {
    <#
    .SYNOPSIS
      Lista las etiquetas del usuario.
    #>
    [CmdletBinding()]
    param()

    $data = Invoke-HabiticaApi -Method GET -Path 'tags'
    return @(ConvertTo-HabiticaArray $data | ForEach-Object {
        [pscustomobject]@{
            PSTypeName = 'HabiticaCli.Tag'
            Id         = [string](Get-HabiticaObjectValue $_ 'id' (Get-HabiticaObjectValue $_ '_id' ''))
            Name       = [string](Get-HabiticaObjectValue $_ 'name' '')
        }
    })
}

function Resolve-HabiticaTagId {
    <#
    .SYNOPSIS
      Convierte un nombre o id de etiqueta en su UUID.
    #>
    param([Parameter(Mandatory)][string]$Reference)

    $reference = $Reference.Trim().TrimStart('#')
    $tags = @(Get-HabiticaTag)

    $match = $tags | Where-Object { $_.Id -eq $reference } | Select-Object -First 1
    if ($match) { return $match.Id }

    $match = $tags | Where-Object { $_.Name.ToLowerInvariant() -eq $reference.ToLowerInvariant() } | Select-Object -First 1
    if ($match) { return $match.Id }

    throw ("No existe la etiqueta '{0}'. Crea una con: h tag add {0}" -f $reference)
}

function New-HabiticaTag {
    <#
    .SYNOPSIS
      Crea una etiqueta.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)

    if ($PSCmdlet.ShouldProcess("Etiqueta '$Name'", 'Crear')) {
        $data = Invoke-HabiticaApi -Method POST -Path 'tags' -Body @{ name = $Name }
        Write-HabiticaOk ("Etiqueta creada: #{0}" -f $Name)
        return [pscustomobject]@{
            PSTypeName = 'HabiticaCli.Tag'
            Id         = [string](Get-HabiticaObjectValue $data 'id' '')
            Name       = [string](Get-HabiticaObjectValue $data 'name' $Name)
        }
    }
}

function Set-HabiticaTag {
    <#
    .SYNOPSIS
      Renombra una etiqueta.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name
    )

    if ($PSCmdlet.ShouldProcess("Etiqueta '$Id'", ("Renombrar a '{0}'" -f $Name))) {
        $data = Invoke-HabiticaApi -Method PUT -Path ('tags/{0}' -f [uri]::EscapeDataString($Id)) -Body @{ name = $Name }
        Write-HabiticaOk ("Etiqueta renombrada: #{0}" -f $Name)
        return [pscustomobject]@{
            PSTypeName = 'HabiticaCli.Tag'
            Id         = [string](Get-HabiticaObjectValue $data 'id' $Id)
            Name       = [string](Get-HabiticaObjectValue $data 'name' $Name)
        }
    }
}

function Remove-HabiticaTag {
    <#
    .SYNOPSIS
      Elimina una etiqueta.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Force
    )

    $tag = $null
    try { $tag = Get-HabiticaTag | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 } catch { }
    $label = if ($tag) { $tag.Name } else { $Id }

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw ("Operacion destructiva sobre la etiqueta '{0}'. Usa --yes para confirmar." -f $label)
    }
    if (-not (Confirm-HabiticaAction -Message ("Eliminar la etiqueta '#{0}'? Las tareas no se borran." -f $label) -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    if ($PSCmdlet.ShouldProcess("Etiqueta '$label'", 'Eliminar')) {
        Invoke-HabiticaApi -Method DELETE -Path ('tags/{0}' -f [uri]::EscapeDataString($Id)) | Out-Null
        Write-HabiticaOk ("Etiqueta eliminada: #{0}" -f $label)
    }
}

function Move-HabiticaTag {
    <#
    .SYNOPSIS
      Reordena una etiqueta.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][int]$Position
    )

    if ($PSCmdlet.ShouldProcess("Etiqueta '$Id'", ("Mover a {0}" -f $Position))) {
        Invoke-HabiticaApi -Method POST -Path 'reorder-tags' -Body @{ tagId = $Id; to = $Position } | Out-Null
        Write-HabiticaOk 'Etiqueta reordenada.'
    }
}

function Add-HabiticaTaskTag {
    <#
    .SYNOPSIS
      Asocia una etiqueta a una tarea.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$TagId
    )

    if ($PSCmdlet.ShouldProcess("Tarea '$TaskId'", 'Agregar etiqueta')) {
        Invoke-HabiticaApi -Method POST -Path ('tasks/{0}/tags/{1}' -f [uri]::EscapeDataString($TaskId), [uri]::EscapeDataString($TagId)) | Out-Null
        Write-HabiticaOk 'Etiqueta asociada a la tarea.'
    }
}

function Remove-HabiticaTaskTag {
    <#
    .SYNOPSIS
      Quita una etiqueta de una tarea.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$TagId
    )

    if ($PSCmdlet.ShouldProcess("Tarea '$TaskId'", 'Quitar etiqueta')) {
        Invoke-HabiticaApi -Method DELETE -Path ('tasks/{0}/tags/{1}' -f [uri]::EscapeDataString($TaskId), [uri]::EscapeDataString($TagId)) | Out-Null
        Write-HabiticaOk 'Etiqueta quitada de la tarea.'
    }
}
