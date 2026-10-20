# =============================================================================
#  Habitica CLI - Usuario, estadisticas, notificaciones y correo
# =============================================================================

$script:ClassLabels = @{
    warrior = 'Guerrero'
    rogue   = 'Picaro'
    wizard  = 'Mago'
    healer  = 'Sanador'
    ''      = 'Sin clase'
}

$script:DefaultUserFields = 'stats,profile,party,notifications,preferences,items.gear.equipped'

function Get-HabiticaXPToNextLevel {
    param([Parameter(Mandatory)][int]$Level)

    if ($Level -lt 5) { return (25 * $Level) }
    if ($Level -eq 5) { return 150 }

    $value = ((($Level * $Level) * 0.25) + (10 * $Level) + 139.75) / 10
    return ([int]([Math]::Floor($value + 0.5)) * 10)
}

function Get-HabiticaComputedMaxMP {
    param([AllowNull()]$UserData)

    $stats = Get-HabiticaObjectValue $UserData 'stats' $null
    if (-not $stats) { return 0 }

    $level = [int](Get-HabiticaObjectValue $stats 'lvl' 1)
    $capLevel = [Math]::Min($level, 100)
    $levelBonus = [int][Math]::Floor($capLevel / 2)

    $baseInt = [double](Get-HabiticaObjectValue $stats 'int' 0)
    $buffs = Get-HabiticaObjectValue $stats 'buffs' $null
    $buffInt = [double](Get-HabiticaObjectValue $buffs 'int' 0)

    $gearBonus = 0.0
    $classBonus = 0.0

    try {
        $items = Get-HabiticaObjectValue $UserData 'items' $null
        $gear = Get-HabiticaObjectValue $items 'gear' $null
        $equipped = Get-HabiticaObjectValue $gear 'equipped' $null

        if ($equipped) {
            $content = Get-HabiticaContent
            $gearFlat = Get-HabiticaObjectValue $content 'gear' $null
            $gearFlat = Get-HabiticaObjectValue $gearFlat 'flat' $null
            $class = [string](Get-HabiticaObjectValue $stats 'class' '')

            foreach ($property in $equipped.PSObject.Properties) {
                $key = [string]$property.Value
                if ([string]::IsNullOrWhiteSpace($key)) { continue }
                $item = Get-HabiticaObjectValue $gearFlat $key $null
                if (-not $item) { continue }

                $value = [double](Get-HabiticaObjectValue $item 'int' 0)
                if ($value -eq 0) { continue }
                $gearBonus += $value
                $itemClass = [string](Get-HabiticaObjectValue $item 'klass' '')
                $specialClass = [string](Get-HabiticaObjectValue $item 'specialClass' '')
                if ($itemClass -eq $class -or $specialClass -eq $class) { $classBonus += $value }
            }
        }
    }
    catch { }

    $totalInt = $baseInt + $buffInt + $gearBonus + $classBonus + $levelBonus
    return [double]($totalInt * 2 + 30)
}

function Get-HabiticaClassLabel {
    param([AllowNull()][string]$Class)
    if ($null -eq $Class) { return 'Sin clase' }
    $key = $Class.ToLowerInvariant()
    if ($script:ClassLabels.ContainsKey($key)) { return $script:ClassLabels[$key] }
    return $Class
}

function Get-HabiticaUser {
    <#
    .SYNOPSIS
      Obtiene el perfil del usuario autenticado.
    .PARAMETER UserFields
      Campos separados por coma (stats, profile, party, notifications, preferences...).
    .PARAMETER Refresh
      Ignora la cache local.
    #>
    [CmdletBinding()]
    param(
        [string]$UserFields = $script:DefaultUserFields,
        [switch]$Refresh
    )

    $useCache = (-not $Refresh -and $UserFields -eq $script:DefaultUserFields)
    if ($useCache) {
        $cached = Read-HabiticaUserCache -MaxAgeSeconds 25
        if ($cached -and (Get-HabiticaObjectValue $cached 'items' $null)) { return $cached }
    }

    $data = Invoke-HabiticaApi -Method GET -Path 'user' -Query @{ userFields = $UserFields }
    if ($useCache) { Write-HabiticaUserCache -Data $data }
    return $data
}

function Get-HabiticaStats {
    <#
    .SYNOPSIS
      Devuelve las estadisticas del personaje.
    #>
    [CmdletBinding()]
    param(
        [switch]$Refresh,
        [object]$UserData
    )

    if ($UserData) { $user = $UserData }
    else { $user = Get-HabiticaUser -Refresh:$Refresh }
    $stats = Get-HabiticaObjectValue $user 'stats' $null
    $profile = Get-HabiticaObjectValue $user 'profile' $null
    $level = [int](Get-HabiticaObjectValue $stats 'lvl' 1)

    $maxHp = [double](Get-HabiticaObjectValue $stats 'maxHealth' 0)
    if ($maxHp -le 0) { $maxHp = 50 }

    $maxXp = [double](Get-HabiticaObjectValue $stats 'toNextLevel' 0)
    if ($maxXp -le 0) { $maxXp = [double](Get-HabiticaXPToNextLevel -Level $level) }

    $maxMp = [double](Get-HabiticaObjectValue $stats 'maxMP' 0)
    if ($maxMp -le 0) { $maxMp = [double](Get-HabiticaComputedMaxMP -UserData $user) }

    [pscustomobject]@{
        PSTypeName  = 'HabiticaCli.Stats'
        Name        = [string](Get-HabiticaObjectValue $profile 'name' 'Heroe')
        Level       = $level
        Class       = [string](Get-HabiticaObjectValue $stats 'class' '')
        ClassLabel  = Get-HabiticaClassLabel ([string](Get-HabiticaObjectValue $stats 'class' ''))
        HP          = [double](Get-HabiticaObjectValue $stats 'hp' 0)
        MaxHP       = $maxHp
        XP          = [double](Get-HabiticaObjectValue $stats 'exp' 0)
        MaxXP       = $maxXp
        MP          = [double](Get-HabiticaObjectValue $stats 'mp' 0)
        MaxMP       = $maxMp
        Gold        = [double](Get-HabiticaObjectValue $stats 'gp' 0)
        Points      = Get-HabiticaObjectValue $stats 'points' 0
        Strength    = Get-HabiticaObjectValue $stats 'str' 0
        Intelligence = Get-HabiticaObjectValue $stats 'int' 0
        Perception  = Get-HabiticaObjectValue $stats 'per' 0
        Constitution = Get-HabiticaObjectValue $stats 'con' 0
        Buffs       = Get-HabiticaObjectValue $stats 'buffs' $null
        Raw         = $user
    }
}

function Update-HabiticaStatsCacheFromScore {
    param([AllowNull()]$ScoreData)

    if ($null -eq $ScoreData) { return }

    $cached = Read-HabiticaUserCache -MaxAgeSeconds 3600
    if (-not $cached) { return }

    $stats = Get-HabiticaObjectValue $cached 'stats' $null
    if (-not $stats) { return }

    foreach ($pair in @(
        @{ From = 'hp'; To = 'hp' },
        @{ From = 'exp'; To = 'exp' },
        @{ From = 'gp'; To = 'gp' },
        @{ From = 'mp'; To = 'mp' },
        @{ From = 'lvl'; To = 'lvl' },
        @{ From = 'toNextLevel'; To = 'toNextLevel' },
        @{ From = 'maxHealth'; To = 'maxHealth' },
        @{ From = 'maxMP'; To = 'maxMP' }
    )) {
        $value = Get-HabiticaObjectValue $ScoreData $pair.From $null
        if ($null -ne $value) {
            $stats | Add-Member -NotePropertyName $pair.To -NotePropertyValue $value -Force
        }
    }

    Write-HabiticaUserCache -Data $cached
}

function Show-HabiticaBars {
    param(
        [Parameter(Mandatory)]$Stats,
        [int]$BarWidth = 16
    )

    $hpRatio = 0
    if ($Stats.MaxHP -gt 0) { $hpRatio = $Stats.HP / $Stats.MaxHP }
    $hpColor = 'green'
    if ($hpRatio -le 0.25) { $hpColor = 'red' }
    elseif ($hpRatio -le 0.5) { $hpColor = 'gold' }

    $xpBar = New-HabiticaProgressBar -Current $Stats.XP -Maximum $Stats.MaxXP -Width $BarWidth -Color 'gold'
    $hpBar = New-HabiticaProgressBar -Current $Stats.HP -Maximum $Stats.MaxHP -Width $BarWidth -Color $hpColor
    $mpBar = New-HabiticaProgressBar -Current $Stats.MP -Maximum $Stats.MaxMP -Width $BarWidth -Color 'cyan'

    Write-HabiticaLine ("  ~gray~NIVEL~/~ ~gold~{0,3}~/~   ~gray~CLASE~/~ ~white~{1}~/~" -f $Stats.Level, $Stats.ClassLabel)
    Write-HabiticaLine ("  ~red~HP ~/~ {0} {1}/{2}" -f $hpBar, [Math]::Round($Stats.HP), [Math]::Round($Stats.MaxHP))
    Write-HabiticaLine ("  ~gold~XP ~/~ {0} {1}/{2}   ~gray~ORO~/~ ~gold~{3}~/~" -f $xpBar, [Math]::Round($Stats.XP), [Math]::Round($Stats.MaxXP), (Format-HabiticaNumber $Stats.Gold 2))
    Write-HabiticaLine ("  ~cyan~MP ~/~ {0} {1}/{2}   ~gray~PUNTOS~/~ ~white~{3}~/~" -f $mpBar, [Math]::Round($Stats.MP), [Math]::Round($Stats.MaxMP), $Stats.Points)
}

function Show-HabiticaStats {
    <#
    .SYNOPSIS
      Muestra un panel con HP, XP, MP, oro y atributos.
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    $stats = Get-HabiticaStats -Refresh:$Refresh
    $width = Get-TerminalWidth
    $lines = Get-HabiticaStatsPanelLines -Stats $stats -ContentWidth ($width - 4)
    $lines += ''
    $lines += ("~gray~FUERZA~/~ ~white~{0}~/~   ~gray~INTELIGENCIA~/~ ~white~{1}~/~   ~gray~PERCEPCION~/~ ~white~{2}~/~   ~gray~CONSTITUCION~/~ ~white~{3}~/~" -f $stats.Strength, $stats.Intelligence, $stats.Perception, $stats.Constitution)

    $buffs = $stats.Buffs
    if ($buffs) {
        $active = @()
        foreach ($name in @('str', 'int', 'per', 'con')) {
            $value = Get-HabiticaObjectValue $buffs $name 0
            if ($value -and [double]$value -ne 0) { $active += ("{0} {1}" -f $name.ToUpperInvariant(), $value) }
        }
        if ($active.Count -gt 0) { $lines += ("~magenta~BUFFS~/~ {0}" -f ($active -join '   ')) }
    }

    Write-HabiticaBlank
    Write-HabiticaPanel -Title ("ESTADO DEL HEROE  //  {0}" -f $stats.Name) -Lines $lines -Width $width -Color 'gold'
    Write-HabiticaBlank
}

function Get-HabiticaNotification {
    <#
    .SYNOPSIS
      Lista las notificaciones pendientes.
    #>
    [CmdletBinding()]
    param()

    $user = Invoke-HabiticaApi -Method GET -Path 'user' -Query @{ userFields = 'notifications' }
    $items = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $user 'notifications' $null))
    return @($items | ForEach-Object {
        [pscustomobject]@{
            PSTypeName = 'HabiticaCli.Notification'
            Id         = [string](Get-HabiticaObjectValue $_ 'id' '')
            Type       = [string](Get-HabiticaObjectValue $_ 'type' '')
            Seen       = [bool](Get-HabiticaObjectValue $_ 'seen' $false)
            Data       = Get-HabiticaObjectValue $_ 'data' $null
        }
    })
}

function Set-HabiticaNotificationStatus {
    <#
    .SYNOPSIS
      Marca notificaciones como leidas o vistas.
    .PARAMETER Status
      Read o See.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Read', 'See')]
        [string]$Status = 'Read',

        [string[]]$Id,

        [switch]$All
    )

    $statusPath = $Status.ToLowerInvariant()
    if ($All) {
        $path = 'notifications/{0}' -f $statusPath
        $notifications = @(Get-HabiticaNotification)
        if ($notifications.Count -eq 0) {
            Write-HabiticaInfo 'No hay notificaciones que actualizar.'
            return
        }
        $body = @{ notificationIds = @($notifications | ForEach-Object { $_.Id }) }

        if ($PSCmdlet.ShouldProcess('Todas las notificaciones', ("Marcar como {0}" -f $statusPath))) {
            Invoke-HabiticaApi -Method POST -Path $path -Body $body | Out-Null
            Write-HabiticaOk ("Notificaciones marcadas como {0}." -f $statusPath)
        }
        return
    }

    if (-not $Id -or $Id.Count -eq 0) { throw 'Indica el id de la notificacion o usa --all.' }

    if ($PSCmdlet.ShouldProcess('Notificaciones seleccionadas', ("Marcar como {0}" -f $statusPath))) {
        foreach ($notificationId in $Id) {
            Invoke-HabiticaApi -Method POST -Path ('notifications/{0}/{1}' -f [uri]::EscapeDataString($notificationId), $statusPath) | Out-Null
        }
        Write-HabiticaOk ("Notificaciones marcadas como {0}." -f $statusPath)
    }
}

function Get-HabiticaInbox {
    <#
    .SYNOPSIS
      Lista los mensajes privados del buzon.
    #>
    [CmdletBinding()]
    param(
        [int]$Page = 0,
        [string]$Conversation
    )

    $query = @{ page = $Page }
    if ($Conversation) { $query.conversation = $Conversation }

    $data = Invoke-HabiticaApi -Method GET -Path 'inbox/messages' -Query $query
    $messages = @(Get-HabiticaDataCollection $data)
    return @($messages | ForEach-Object {
        [pscustomobject]@{
            PSTypeName = 'HabiticaCli.InboxMessage'
            Id         = [string](Get-HabiticaObjectValue $_ 'id' (Get-HabiticaObjectValue $_ '_id' ''))
            FromId     = [string](Get-HabiticaObjectValue $_ 'uuid' '')
            Text       = [string](Get-HabiticaObjectValue $_ 'text' '')
            Timestamp  = Get-HabiticaObjectValue $_ 'timestamp' $null
            Sent       = [bool](Get-HabiticaObjectValue $_ 'sent' $false)
            Likes      = Get-HabiticaObjectValue $_ 'likes' $null
            Raw        = $_
        }
    })
}

function Send-HabiticaPrivateMessage {
    <#
    .SYNOPSIS
      Envia un mensaje privado a otro usuario.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ToUserId,
        [Parameter(Mandatory)][string]$Message
    )

    if ($PSCmdlet.ShouldProcess("Usuario '$ToUserId'", 'Enviar mensaje privado')) {
        $data = Invoke-HabiticaApi -Method POST -Path 'members/send-private-message' -Body @{ toUserId = $ToUserId; message = $Message }
        Write-HabiticaOk 'Mensaje privado enviado.'
        return (Get-HabiticaObjectValue $data 'message' $data)
    }
}
