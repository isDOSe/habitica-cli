# =============================================================================
#  Habitica CLI - Party, grupos, chat, miembros y quests
# =============================================================================

$script:MemberNameCache = @{}

function Get-HabiticaGroup {
    <#
    .SYNOPSIS
      Obtiene un grupo por id. Acepta 'party' y 'habitrpg'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    return (Invoke-HabiticaApi -Method GET -Path ('groups/{0}' -f [uri]::EscapeDataString($Id)))
}

function Get-HabiticaGroups {
    <#
    .SYNOPSIS
      Lista los grupos del usuario.
    .PARAMETER Type
      Party, Guilds, Tavern o All.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Party', 'Guilds', 'Tavern', 'All')]
        [string]$Type = 'All'
    )

    if ($Type -eq 'Tavern') {
        return @(Get-HabiticaGroup -Id 'habitrpg')
    }
    if ($Type -eq 'All') {
        $data = Invoke-HabiticaApi -Method GET -Path 'groups'
        return @(ConvertTo-HabiticaArray $data)
    }

    $queryType = $Type.ToLowerInvariant()
    $data = Invoke-HabiticaApi -Method GET -Path 'groups' -Query @{ type = $queryType }
    return @(ConvertTo-HabiticaArray $data)
}

function Get-HabiticaParty {
    <#
    .SYNOPSIS
      Devuelve la party del usuario, o $null si no tiene.
    #>
    [CmdletBinding()]
    param()

    $groups = @(Get-HabiticaGroups -Type Party)
    if ($groups.Count -eq 0) { return $null }
    return $groups[0]
}

function Get-HabiticaMember {
    <#
    .SYNOPSIS
      Obtiene el perfil publico de un miembro.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MemberId)

    if ($script:MemberNameCache.ContainsKey($MemberId)) { return $script:MemberNameCache[$MemberId] }

    $data = Invoke-HabiticaApi -Method GET -Path ('members/{0}' -f [uri]::EscapeDataString($MemberId))
    $profile = Get-HabiticaObjectValue $data 'profile' $null
    $stats = Get-HabiticaObjectValue $data 'stats' $null

    $member = [pscustomobject]@{
        PSTypeName = 'HabiticaCli.Member'
        Id         = [string](Get-HabiticaObjectValue $data '_id' $MemberId)
        Name       = [string](Get-HabiticaObjectValue $profile 'name' 'Heroe')
        Class      = [string](Get-HabiticaObjectValue $stats 'class' '')
        ClassLabel = Get-HabiticaClassLabel ([string](Get-HabiticaObjectValue $stats 'class' ''))
        Level      = Get-HabiticaObjectValue $stats 'lvl' 1
        HP         = Get-HabiticaObjectValue $stats 'hp' 0
        MaxHP      = Get-HabiticaObjectValue $stats 'maxHealth' 50
        Raw        = $data
    }
    $script:MemberNameCache[$MemberId] = $member
    return $member
}

function Get-HabiticaMemberName {
    param([Parameter(Mandatory)][string]$MemberId)

    if ($script:MemberNameCache.ContainsKey($MemberId)) { return $script:MemberNameCache[$MemberId].Name }
    try { return (Get-HabiticaMember -MemberId $MemberId).Name }
    catch { return $MemberId.Substring(0, [Math]::Min(8, $MemberId.Length)) }
}

function Get-HabiticaPartyMembers {
    <#
    .SYNOPSIS
      Lista los miembros de la party.
    #>
    [CmdletBinding()]
    param(
        [string]$GroupId = 'party',
        [int]$Limit = 60
    )

    $data = Invoke-HabiticaApi -Method GET -Path ('groups/{0}/members' -f [uri]::EscapeDataString($GroupId)) -Query @{ limit = $Limit }
    $items = @(ConvertTo-HabiticaArray $data)
    $result = @()
    foreach ($item in $items) {
        $profile = Get-HabiticaObjectValue $item 'profile' $null
        $stats = Get-HabiticaObjectValue $item 'stats' $null
        $auth = Get-HabiticaObjectValue $item 'auth' $null
        $timestamps = Get-HabiticaObjectValue $auth 'timestamps' $null
        $lastLogin = Get-HabiticaObjectValue $timestamps 'lastLoggedIn' $null
        $id = [string](Get-HabiticaObjectValue $item '_id' (Get-HabiticaObjectValue $item 'id' ''))

        $member = [pscustomobject]@{
            PSTypeName = 'HabiticaCli.Member'
            Id         = $id
            Name       = [string](Get-HabiticaObjectValue $profile 'name' 'Heroe')
            Class      = [string](Get-HabiticaObjectValue $stats 'class' '')
            ClassLabel = Get-HabiticaClassLabel ([string](Get-HabiticaObjectValue $stats 'class' ''))
            Level      = Get-HabiticaObjectValue $stats 'lvl' 1
            HP         = Get-HabiticaObjectValue $stats 'hp' 0
            MaxHP      = Get-HabiticaObjectValue $stats 'maxHealth' 50
            LastLogin  = $lastLogin
            Raw        = $item
        }
        if ($id) { $script:MemberNameCache[$id] = $member }
        $result += $member
    }
    return $result
}

function New-HabiticaParty {
    <#
    .SYNOPSIS
      Crea una party privada.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)

    if ($PSCmdlet.ShouldProcess("Party '$Name'", 'Crear')) {
        $data = Invoke-HabiticaApi -Method POST -Path 'groups' -Body @{ name = $Name; type = 'party'; privacy = 'private' }
        Write-HabiticaOk ("Party creada: {0}" -f $Name)
        return $data
    }
}

function Join-HabiticaGroup {
    <#
    .SYNOPSIS
      Une al usuario a un grupo.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$GroupId)

    if ($PSCmdlet.ShouldProcess("Grupo '$GroupId'", 'Unirse')) {
        $data = Invoke-HabiticaApi -Method POST -Path ('groups/{0}/join' -f [uri]::EscapeDataString($GroupId))
        Write-HabiticaOk 'Te has unido al grupo.'
        return $data
    }
}

function Exit-HabiticaGroup {
    <#
    .SYNOPSIS
      Abandona un grupo. En una party se puede conservar o eliminar el historial de tareas.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$GroupId = 'party',
        [ValidateSet('keep-all', 'remove-all')]
        [string]$Keep = 'keep-all',
        [switch]$Force
    )

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw 'Operacion destructiva. Usa --yes para confirmar.'
    }
    if (-not (Confirm-HabiticaAction -Message ("Abandonar el grupo '{0}'?" -f $GroupId) -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    if ($PSCmdlet.ShouldProcess("Grupo '$GroupId'", 'Abandonar')) {
        Invoke-HabiticaApi -Method POST -Path ('groups/{0}/leave' -f [uri]::EscapeDataString($GroupId)) -Query @{ keep = $Keep } | Out-Null
        Write-HabiticaOk 'Has abandonado el grupo.'
    }
}

function Send-HabiticaPartyInvite {
    <#
    .SYNOPSIS
      Invita usuarios a la party por UUID.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$GroupId = 'party',
        [Parameter(Mandatory)][string[]]$UserId
    )

    if ($PSCmdlet.ShouldProcess("Party '$GroupId'", ("Invitar a {0}" -f ($UserId -join ', ')))) {
        $data = Invoke-HabiticaApi -Method POST -Path ('groups/{0}/invite' -f [uri]::EscapeDataString($GroupId)) -Body @{ uuids = @($UserId) }
        Write-HabiticaOk 'Invitacion enviada.'
        return $data
    }
}

function Remove-HabiticaPartyMember {
    <#
    .SYNOPSIS
      Expulsa a un miembro de la party.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$GroupId = 'party',
        [Parameter(Mandatory)][string]$MemberId,
        [string]$Message,
        [switch]$Force
    )

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw 'Operacion destructiva. Usa --yes para confirmar.'
    }
    if (-not (Confirm-HabiticaAction -Message ("Expulsar al miembro '{0}'?" -f $MemberId) -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    $query = @{}
    if ($Message) { $query.message = $Message }

    if ($PSCmdlet.ShouldProcess("Miembro '$MemberId'", 'Expulsar de la party')) {
        Invoke-HabiticaApi -Method POST -Path ('groups/{0}/removeMember/{1}' -f [uri]::EscapeDataString($GroupId), [uri]::EscapeDataString($MemberId)) -Query $query | Out-Null
        Write-HabiticaOk 'Miembro expulsado.'
    }
}

# -----------------------------------------------------------------------------
#  Chat
# -----------------------------------------------------------------------------

function Get-HabiticaChat {
    <#
    .SYNOPSIS
      Obtiene los ultimos mensajes del chat de un grupo.
    #>
    [CmdletBinding()]
    param(
        [string]$GroupId = 'party',
        [int]$Limit = 30,
        [switch]$NoNames
    )

    if ($Limit -lt 1) { $Limit = 10 }
    if ($Limit -gt 100) { $Limit = 100 }

    $data = Invoke-HabiticaApi -Method GET -Path ('groups/{0}/chat' -f [uri]::EscapeDataString($GroupId)) -Query @{ limit = $Limit }
    $items = @(ConvertTo-HabiticaArray $data)

    $memberMap = @{}
    if (-not $NoNames) {
        try {
            foreach ($member in @(Get-HabiticaPartyMembers -GroupId $GroupId -Limit 60)) {
                $memberMap[$member.Id] = $member.Name
            }
        }
        catch { }
    }

    $result = @()
    foreach ($item in $items) {
        $authorId = [string](Get-HabiticaObjectValue $item 'uuid' '')
        $authorName = ''
        if ($authorId -and $memberMap.ContainsKey($authorId)) { $authorName = $memberMap[$authorId] }
        if (-not $authorName) { $authorName = Get-HabiticaPropertyText -Object $item -Name 'username' -Default '' }
        if (-not $authorName) { $authorName = 'Sistema' }

        $likes = Get-HabiticaObjectValue $item 'likes' $null
        $likeCount = 0
        if ($likes -is [int] -or $likes -is [long] -or $likes -is [double]) { $likeCount = [int]$likes }
        elseif ($likes) { $likeCount = @($likes.PSObject.Properties).Count }

        $text = [string](Get-HabiticaObjectValue $item 'text' '')
        $isSystem = [string]::IsNullOrWhiteSpace($authorId)

        $result += [pscustomobject]@{
            PSTypeName = 'HabiticaCli.ChatMessage'
            Id         = [string](Get-HabiticaObjectValue $item 'id' (Get-HabiticaObjectValue $item '_id' ''))
            AuthorId   = $authorId
            AuthorName = $authorName
            Text       = ConvertFrom-HabiticaMarkdown $text
            RawText    = $text
            Timestamp  = Get-HabiticaObjectValue $item 'timestamp' 0
            Likes      = $likeCount
            IsSystem   = $isSystem
        }
    }

    $result = @($result | Sort-Object { [double]$_.Timestamp })
    Set-HabiticaLastChat -GroupId $GroupId -Messages $result
    return $result
}

function Send-HabiticaChatMessage {
    <#
    .SYNOPSIS
      Envia un mensaje al chat de la party o de un grupo.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$GroupId = 'party'
    )

    if ($PSCmdlet.ShouldProcess("Chat '$GroupId'", 'Enviar mensaje')) {
        $data = Invoke-HabiticaApi -Method POST -Path ('groups/{0}/chat' -f [uri]::EscapeDataString($GroupId)) -Body @{ message = $Message }
        Write-HabiticaOk 'Mensaje enviado.'
        return $data
    }
}

function Add-HabiticaChatLike {
    <#
    .SYNOPSIS
      Da o quita "me gusta" a un mensaje.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$MessageId,
        [string]$GroupId = 'party'
    )

    if ($PSCmdlet.ShouldProcess("Mensaje '$MessageId'", 'Alternar me gusta')) {
        Invoke-HabiticaApi -Method POST -Path ('groups/{0}/chat/{1}/like' -f [uri]::EscapeDataString($GroupId), [uri]::EscapeDataString($MessageId)) | Out-Null
        Write-HabiticaOk 'Me gusta actualizado.'
    }
}

function Set-HabiticaChatSeen {
    <#
    .SYNOPSIS
      Marca todo el chat como leido.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$GroupId = 'party')

    if ($PSCmdlet.ShouldProcess("Chat '$GroupId'", 'Marcar como leido')) {
        Invoke-HabiticaApi -Method POST -Path ('groups/{0}/chat/seen' -f [uri]::EscapeDataString($GroupId)) | Out-Null
        Write-HabiticaOk 'Chat marcado como leido.'
    }
}

function Remove-HabiticaChatMessage {
    <#
    .SYNOPSIS
      Elimina un mensaje propio del chat.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$MessageId,
        [string]$GroupId = 'party',
        [switch]$Force
    )

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw 'Operacion destructiva. Usa --yes para confirmar.'
    }
    if (-not (Confirm-HabiticaAction -Message 'Eliminar este mensaje del chat?' -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    if ($PSCmdlet.ShouldProcess("Mensaje '$MessageId'", 'Eliminar')) {
        Invoke-HabiticaApi -Method DELETE -Path ('groups/{0}/chat/{1}' -f [uri]::EscapeDataString($GroupId), [uri]::EscapeDataString($MessageId)) | Out-Null
        Write-HabiticaOk 'Mensaje eliminado.'
    }
}

# -----------------------------------------------------------------------------
#  Contenido y quests
# -----------------------------------------------------------------------------

function Get-HabiticaContent {
    <#
    .SYNOPSIS
      Obtiene el catalogo de contenido del juego (cacheado 7 dias).
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    if (-not $Refresh) {
        $cached = Read-HabiticaContentCache -MaxAgeHours 168
        if ($cached) { return $cached }
    }

    $data = Invoke-HabiticaApi -Method GET -Path 'content' -Query @{ language = 'es' }
    Write-HabiticaContentCache -Data $data
    return $data
}

function Get-HabiticaQuestInfo {
    param([Parameter(Mandatory)][string]$Key)

    try {
        $content = Get-HabiticaContent
        $quests = Get-HabiticaObjectValue $content 'quests' $null
        $info = Get-HabiticaObjectValue $quests $Key $null
        return $info
    }
    catch { return $null }
}

function Get-HabiticaQuest {
    <#
    .SYNOPSIS
      Devuelve el estado de la quest de la party.
    #>
    [CmdletBinding()]
    param([string]$PartyId = 'party')

    $group = Get-HabiticaGroup -Id $PartyId
    if (-not $group) { return $null }

    $partyId = [string](Get-HabiticaObjectValue $group '_id' 'party')
    $quest = Get-HabiticaObjectValue $group 'quest' $null
    $key = [string](Get-HabiticaObjectValue $quest 'key' '')
    $active = [bool](Get-HabiticaObjectValue $quest 'active' $false)
    $progress = Get-HabiticaObjectValue $quest 'progress' $null

    $name = $key
    $description = ''
    $bossHp = 0
    $rageMax = 0
    $collect = @()

    if ($key) {
        $info = Get-HabiticaQuestInfo -Key $key
        if ($info) {
            $name = Get-HabiticaPropertyText -Object $info -Name 'text' -Default $key
            $description = Get-HabiticaPropertyText -Object $info -Name 'notes' -Default ''
            $boss = Get-HabiticaObjectValue $info 'boss' $null
            if ($boss) {
                $bossHp = [double](Get-HabiticaObjectValue $boss 'hp' 0)
                $rage = Get-HabiticaObjectValue $boss 'rage' $null
                if ($rage) { $rageMax = [double](Get-HabiticaObjectValue $rage 'value' 0) }
            }
            $collectInfo = Get-HabiticaObjectValue $info 'collect' $null
            if ($collectInfo) {
                foreach ($property in $collectInfo.PSObject.Properties) {
                    $collect += [pscustomobject]@{
                        Key       = $property.Name
                        Text      = [string](Get-HabiticaObjectValue $property.Value 'text' $property.Name)
                        Total     = [int](Get-HabiticaObjectValue $property.Value 'count' 0)
                        Collected = 0
                    }
                }
            }
        }
    }

    $progressHp = Get-HabiticaObjectValue $progress 'hp' $null
    $progressRage = Get-HabiticaObjectValue $progress 'rage' 0
    $progressCollect = Get-HabiticaObjectValue $progress 'collect' $null
    if ($progressCollect -and $collect.Count -gt 0) {
        foreach ($entry in $collect) {
            $value = Get-HabiticaObjectValue $progressCollect $entry.Key 0
            $entry.Collected = [int]$value
        }
    }

    $memberCount = 0
    $members = Get-HabiticaObjectValue $group 'members' $null
    if ($members) { $memberCount = @(ConvertTo-HabiticaArray $members).Count }

    $leader = Get-HabiticaObjectValue $quest 'leader' ''
    $completed = Get-HabiticaObjectValue $quest 'completed' $null

    return [pscustomobject]@{
        PSTypeName  = 'HabiticaCli.Quest'
        PartyId     = $partyId
        Key         = $key
        Name        = $name
        Description = $description
        Active      = $active
        ProgressHp  = $progressHp
        BossMaxHp   = $bossHp
        Rage        = $progressRage
        RageMax     = $rageMax
        Collect     = $collect
        Up          = Get-HabiticaObjectValue $progress 'up' 0
        Down        = Get-HabiticaObjectValue $progress 'down' 0
        MemberCount = $memberCount
        Leader      = [string]$leader
        Completed   = $completed
        Group       = $group
    }
}

function Invoke-HabiticaQuestAction {
    <#
    .SYNOPSIS
      Ejecuta una accion sobre la quest de la party.
    .PARAMETER Action
      Invite, Accept, Reject, Start, Cancel, Abort o Leave.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Invite', 'Accept', 'Reject', 'Start', 'Cancel', 'Abort', 'Leave')]
        [string]$Action,

        [string]$QuestKey,
        [string]$PartyId = 'party'
    )

    $actionKey = $Action.ToLowerInvariant()
    $path = $null
    switch ($actionKey) {
        'invite' {
            if ([string]::IsNullOrWhiteSpace($QuestKey)) { throw 'Indica la clave de la quest: h quest invite <clave>' }
            $path = 'groups/{0}/quests/invite/{1}' -f [uri]::EscapeDataString($PartyId), [uri]::EscapeDataString($QuestKey)
        }
        'accept' { $path = 'groups/{0}/quests/accept' -f [uri]::EscapeDataString($PartyId) }
        'reject' { $path = 'groups/{0}/quests/reject' -f [uri]::EscapeDataString($PartyId) }
        'start' { $path = 'groups/{0}/quests/force-start' -f [uri]::EscapeDataString($PartyId) }
        'cancel' { $path = 'groups/{0}/quests/cancel' -f [uri]::EscapeDataString($PartyId) }
        'abort' { $path = 'groups/{0}/quests/abort' -f [uri]::EscapeDataString($PartyId) }
        'leave' { $path = 'groups/{0}/quests/leave' -f [uri]::EscapeDataString($PartyId) }
    }

    if ($PSCmdlet.ShouldProcess("Quest '$actionKey'", 'Ejecutar accion')) {
        $data = Invoke-HabiticaApi -Method POST -Path $path
        Write-HabiticaOk ("Quest: {0}" -f $actionKey)
        return $data
    }
}

