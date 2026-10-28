# =============================================================================
#  Habitica CLI - Poderes de clase
# =============================================================================

$script:HabiticaClassSkills = @{
    warrior = @(
        [pscustomobject]@{
            Key = 'smash'; Name = 'Golpe Brutal'; Cost = 10; Level = 11; Target = 'task'
            Description = 'Vuelve una tarea menos roja y provoca dano adicional a los Jefes. (FUE)'
            Aliases = @('smash', 'golpe', 'brutal', 'golpe brutal')
        }
        [pscustomobject]@{
            Key = 'defensiveStance'; Name = 'Postura defensiva'; Cost = 25; Level = 12; Target = 'self'
            Description = 'Te agachas bien bajo y potencias tu Constitucion. (CON sin potenciar)'
            Aliases = @('defensiveStance', 'postura', 'defensiva', 'postura defensiva')
        }
        [pscustomobject]@{
            Key = 'valorousPresence'; Name = 'Presencia Valerosa'; Cost = 20; Level = 13; Target = 'party'
            Description = 'Tu audacia potencia la Fuerza de todo tu Equipo. (FUE sin potenciar)'
            Aliases = @('valorousPresence', 'presencia', 'valerosa', 'presencia valerosa')
        }
        [pscustomobject]@{
            Key = 'intimidate'; Name = 'Mirada intimidante'; Cost = 15; Level = 14; Target = 'party'
            Description = 'Tu fiera mirada incrementa la Constitucion de tu Equipo. (CON sin potenciar)'
            Aliases = @('intimidate', 'mirada', 'intimidante', 'mirada intimidante')
        }
    )
    rogue = @(
        [pscustomobject]@{
            Key = 'pickPocket'; Name = 'Hurtar'; Cost = 10; Level = 11; Target = 'task'
            Description = 'Le robas a una tarea despistada obteniendo oro. (PER)'
            Aliases = @('pickPocket', 'hurtar', 'robar', 'robo')
        }
        [pscustomobject]@{
            Key = 'backStab'; Name = 'Punalada'; Cost = 15; Level = 12; Target = 'task'
            Description = 'Traicionas a una necia tarea obteniendo oro y experiencia. (FUE)'
            Aliases = @('backStab', 'punalada', 'backstab', 'apunalar')
        }
        [pscustomobject]@{
            Key = 'toolsOfTrade'; Name = 'Herramientas del Oficio'; Cost = 25; Level = 13; Target = 'party'
            Description = 'Tu talento para el engano incrementa la Percepcion de tu Equipo. (PER sin potenciar)'
            Aliases = @('toolsOfTrade', 'herramientas', 'oficio', 'herramientas del oficio')
        }
        [pscustomobject]@{
            Key = 'stealth'; Name = 'Sigilo'; Cost = 45; Level = 14; Target = 'self'
            Description = 'Algunas de tus diarias no te causaran dano esta noche. Sus rachas no cambian. (PER)'
            Aliases = @('stealth', 'sigilo', 'esconderse')
        }
    )
    wizard = @(
        [pscustomobject]@{
            Key = 'fireball'; Name = 'Estallido de llamas'; Cost = 10; Level = 11; Target = 'task'
            Description = 'Invocas Experiencia y danas furiosamente a los Jefes. (INT)'
            Aliases = @('fireball', 'estallido', 'llamas', 'bola de fuego')
        }
        [pscustomobject]@{
            Key = 'mpheal'; Name = 'Corriente eterea'; Cost = 30; Level = 12; Target = 'party'
            Description = 'Sacrificas Mana para que el resto del Equipo, excepto los Magos, gane PM. (INT)'
            Aliases = @('mpheal', 'corriente', 'eterea', 'corriente eterea')
        }
        [pscustomobject]@{
            Key = 'earth'; Name = 'Terremoto'; Cost = 35; Level = 13; Target = 'party'
            Description = 'Haces temblar la tierra potenciando la Inteligencia de tu Equipo. (INT sin potenciar)'
            Aliases = @('earth', 'terremoto', 'temblor')
        }
        [pscustomobject]@{
            Key = 'frost'; Name = 'Frio escalofriante'; Cost = 40; Level = 14; Target = 'self'
            Description = 'Congela todas tus rachas para que no bajen a cero manana.'
            Aliases = @('frost', 'frio', 'escalofriante', 'frio escalofriante')
        }
    )
    healer = @(
        [pscustomobject]@{
            Key = 'heal'; Name = 'Luz Sanadora'; Cost = 15; Level = 11; Target = 'self'
            Description = 'Una brillante luz restaura tu salud. (INT y CON)'
            Aliases = @('heal', 'luz', 'sanadora', 'curar', 'luz sanadora')
        }
        [pscustomobject]@{
            Key = 'brightness'; Name = 'Claridad Abrasadora'; Cost = 15; Level = 12; Target = 'tasks'
            Description = 'Una explosion de luz vuelve todas tus tareas menos rojas. (INT)'
            Aliases = @('brightness', 'claridad', 'abrasadora', 'claridad abrasadora')
        }
        [pscustomobject]@{
            Key = 'protectAura'; Name = 'Aura Protectora'; Cost = 30; Level = 13; Target = 'party'
            Description = 'Proteges a tu Equipo potenciando su Constitucion. (CON sin potenciar)'
            Aliases = @('protectAura', 'aura', 'protectora', 'aura protectora')
        }
        [pscustomobject]@{
            Key = 'healAll'; Name = 'Bendicion'; Cost = 25; Level = 14; Target = 'party'
            Description = 'Tu hechizo relajante recupera la salud de todo tu Equipo. (CON e INT)'
            Aliases = @('healAll', 'bendicion', 'sanacion', 'curar equipo')
        }
    )
}

function ConvertTo-HabiticaSkillToken {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return ($builder.ToString().ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Get-HabiticaSkillTargetLabel {
    param([string]$Target)

    switch ($Target) {
        'task' { return 'tarea' }
        'tasks' { return 'todas las tareas' }
        'party' { return 'equipo' }
        'self' { return 'ti' }
        'user' { return 'usuario' }
        default { return $Target }
    }
}

function Get-HabiticaSkill {
    <#
    .SYNOPSIS
      Devuelve los poderes de la clase del heroe con su coste y estado.
    .PARAMETER Class
      warrior, rogue, wizard o healer. Por defecto usa la clase del usuario.
    .PARAMETER Refresh
      Ignora la cache local del usuario.
    .EXAMPLE
      Get-HabiticaSkill
    .EXAMPLE
      Get-HabiticaSkill -Class rogue
    #>
    [CmdletBinding()]
    param(
        [string]$Class,
        [object]$UserData,
        [switch]$Refresh
    )

    $stats = $null
    if ($UserData) { $stats = Get-HabiticaStats -UserData $UserData }
    else { $stats = Get-HabiticaStats -Refresh:$Refresh }

    if ([string]::IsNullOrWhiteSpace($Class)) { $Class = [string]$stats.Class }
    $classKey = ([string]$Class).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($classKey) -or -not $script:HabiticaClassSkills.ContainsKey($classKey)) { return @() }

    $level = [int]$stats.Level
    $mp = [double]$stats.MP
    $classLabel = Get-HabiticaClassLabel $classKey
    $result = @()
    $number = 0

    foreach ($definition in $script:HabiticaClassSkills[$classKey]) {
        $number++
        $unlocked = $level -ge [int]$definition.Level
        $affordable = $mp -ge [double]$definition.Cost

        if (-not $unlocked) { $status = ('nivel {0}' -f $definition.Level); $statusKind = 'gray' }
        elseif (-not $affordable) { $status = 'sin PM'; $statusKind = 'red' }
        else { $status = 'listo'; $statusKind = 'green' }

        $result += [pscustomobject]@{
            PSTypeName  = 'HabiticaCli.Skill'
            Number      = $number
            Key         = [string]$definition.Key
            Name        = [string]$definition.Name
            Class       = $classKey
            ClassLabel  = $classLabel
            Cost        = [double]$definition.Cost
            Level       = [int]$definition.Level
            Target      = [string]$definition.Target
            TargetLabel = Get-HabiticaSkillTargetLabel $definition.Target
            Description = [string]$definition.Description
            Aliases     = @($definition.Aliases)
            Unlocked    = $unlocked
            Affordable  = $affordable
            Available   = ($unlocked -and $affordable)
            Status      = $status
            StatusKind  = $statusKind
        }
    }

    return @($result)
}

function Resolve-HabiticaSkillReference {
    <#
    .SYNOPSIS
      Convierte un numero, clave, nombre o alias en un poder de clase.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reference,
        [AllowNull()][string]$Class,
        [AllowNull()][object[]]$Skills
    )

    $referenceText = $Reference.Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($referenceText)) { throw 'Indica un poder por numero, clave, nombre o alias.' }

    if (-not $Skills -or $Skills.Count -eq 0) {
        $Skills = @(Get-HabiticaSkill -Class $Class)
    }
    if (-not $Skills -or $Skills.Count -eq 0) {
        throw 'Tu heroe no tiene clase. Elige una clase en Habitica para usar poderes.'
    }

    if ($referenceText -match '^\d+$') {
        $index = [int]$referenceText
        $skill = @($Skills | Where-Object { $_.Number -eq $index }) | Select-Object -First 1
        if (-not $skill) {
            throw ("El poder {0} no existe. Usa 'h skills' para ver los numeros disponibles." -f $index)
        }
        return $skill
    }

    $needle = ConvertTo-HabiticaSkillToken $referenceText

    $matches = @($Skills | Where-Object { (ConvertTo-HabiticaSkillToken $_.Key) -eq $needle })
    if ($matches.Count -eq 1) { return $matches[0] }

    $matches = @($Skills | Where-Object { (ConvertTo-HabiticaSkillToken $_.Name) -eq $needle })
    if ($matches.Count -eq 1) { return $matches[0] }

    $matches = @($Skills | Where-Object {
        foreach ($alias in @($_.Aliases)) {
            if ((ConvertTo-HabiticaSkillToken $alias) -eq $needle) { return $true }
        }
        return $false
    })
    if ($matches.Count -eq 1) { return $matches[0] }

    $matches = @($Skills | Where-Object {
        if ((ConvertTo-HabiticaSkillToken $_.Name).Contains($needle)) { return $true }
        foreach ($alias in @($_.Aliases)) {
            if ((ConvertTo-HabiticaSkillToken $alias).Contains($needle)) { return $true }
        }
        return $false
    })

    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) {
        $options = ($matches | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Number }) -join ' | '
        throw ("'{0}' coincide con varios poderes: {1}. Usa el numero de 'h skills'." -f $Reference, $options)
    }

    throw ("No existe el poder '{0}' para tu clase. Usa 'h skills' para ver los disponibles." -f $Reference)
}

function Update-HabiticaUserCacheFromUser {
    param([AllowNull()]$UserData)

    if ($null -eq $UserData) { return }
    $stats = Get-HabiticaObjectValue $UserData 'stats' $null
    if (-not $stats) { return }

    $cached = Read-HabiticaUserCache -MaxAgeSeconds 3600
    if (-not $cached) {
        if (Get-HabiticaObjectValue $UserData 'items' $null) { Write-HabiticaUserCache -Data $UserData }
        return
    }

    $cachedStats = Get-HabiticaObjectValue $cached 'stats' $null
    if (-not $cachedStats) { return }

    foreach ($name in @('hp', 'maxHealth', 'exp', 'toNextLevel', 'mp', 'maxMP', 'gp', 'lvl', 'class', 'points', 'str', 'int', 'per', 'con', 'buffs')) {
        $value = Get-HabiticaObjectValue $stats $name $null
        if ($null -ne $value) {
            $cachedStats | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        }
    }

    $profile = Get-HabiticaObjectValue $UserData 'profile' $null
    if ($profile) {
        $cachedProfile = Get-HabiticaObjectValue $cached 'profile' $null
        if ($cachedProfile) {
            foreach ($name in @('name')) {
                $value = Get-HabiticaObjectValue $profile $name $null
                if ($null -ne $value) {
                    $cachedProfile | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
                }
            }
        }
    }

    Write-HabiticaUserCache -Data $cached
}

function Invoke-HabiticaSkillCast {
    <#
    .SYNOPSIS
      Lanza un poder de clase sobre una tarea, el equipo o el propio heroe.
    .PARAMETER Skill
      Numero de 'h skills', clave, nombre o alias.
    .PARAMETER Target
      Tarea objetivo para los poderes que lo necesitan.
    .PARAMETER Quantity
      Numero de lanzamientos consecutivos.
    .PARAMETER Quiet
      No imprime el resultado en pantalla.
    .EXAMPLE
      Invoke-HabiticaSkillCast -Skill smash -Target 3
    .EXAMPLE
      Invoke-HabiticaSkillCast -Skill herramientas
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Skill,
        [string]$Target,
        [ValidateRange(1, 50)][int]$Quantity = 1,
        [switch]$Quiet,
        [switch]$Refresh
    )

    $stats = Get-HabiticaStats -Refresh:$Refresh
    $skills = @(Get-HabiticaSkill -Class $stats.Class -UserData $stats.Raw)
    if ($skills.Count -eq 0) {
        throw 'Tu heroe no tiene clase. Elige una clase en Habitica para usar poderes.'
    }

    $selected = Resolve-HabiticaSkillReference -Reference $Skill -Class $stats.Class -Skills $skills

    if (-not $selected.Unlocked) {
        throw ("{0} se desbloquea en el nivel {1}. Ahora estas en el nivel {2}." -f $selected.Name, $selected.Level, $stats.Level)
    }

    $totalCost = [double]$selected.Cost * $Quantity
    if ([double]$stats.MP -lt $totalCost) {
        throw ("No tienes PM suficientes: {0} cuesta {1} PM y tienes {2}/{3}." -f $selected.Name, (Format-HabiticaNumber $totalCost 0), (Format-HabiticaNumber $stats.MP 0), (Format-HabiticaNumber $stats.MaxMP 0))
    }

    $targetId = ''
    $targetText = ''
    if ($selected.Target -in @('task', 'user')) {
        if ([string]::IsNullOrWhiteSpace($Target)) {
            if ($selected.Target -eq 'task') {
                throw ("{0} necesita una tarea objetivo. Usa --target <n|id|texto>." -f $selected.Name)
            }
            throw ("{0} necesita un usuario objetivo. Usa --target <uuid>." -f $selected.Name)
        }

        if ($selected.Target -eq 'task') {
            $task = Resolve-HabiticaTaskReference -Reference $Target
            $targetId = $task.Id
            $targetText = $task.Text
        }
        else {
            $targetId = $Target.Trim()
            $targetText = $targetId
        }
    }
    elseif ($selected.Target -eq 'tasks') { $targetText = 'todas tus tareas' }
    elseif ($selected.Target -eq 'party') { $targetText = 'tu equipo' }
    else { $targetText = 'ti' }

    $query = @{}
    if ($targetId) { $query.targetId = $targetId }

    $body = @{}
    if ($Quantity -gt 1) { $body.quantity = $Quantity }

    $response = Invoke-HabiticaApi -Method POST -Path ('user/class/cast/{0}' -f [uri]::EscapeDataString($selected.Key)) -Query $query -Body $body -Full
    $data = Get-HabiticaObjectValue $response 'data' $null
    $updatedUser = Get-HabiticaObjectValue $data 'user' $null
    Update-HabiticaUserCacheFromUser -UserData $updatedUser

    $mpAfter = [double]$stats.MP - $totalCost
    $updatedStats = Get-HabiticaObjectValue $updatedUser 'stats' $null
    $reportedMp = Get-HabiticaObjectValue $updatedStats 'mp' $null
    if ($null -ne $reportedMp) { $mpAfter = [double]$reportedMp }

    if (-not $Quiet) {
        Write-HabiticaBlank
        Write-HabiticaLine ("  ~magenta~PODER~/~  ~gold~{0}~/~  ~gray~->~/~  ~white~{1}~/~" -f $selected.Name, $targetText)
        $timesText = if ($Quantity -gt 1) { ' x{0}' -f $Quantity } else { '' }
        Write-HabiticaLine ("         ~gray~Coste:~/~ ~cyan~{0} PM{1}~/~   ~gray~PM restante:~/~ ~white~{2}/{3}~/~" -f (Format-HabiticaNumber $totalCost 0), $timesText, (Format-HabiticaNumber $mpAfter 0), (Format-HabiticaNumber $stats.MaxMP 0))
        Write-HabiticaBlank
    }

    return [pscustomobject]@{
        PSTypeName = 'HabiticaCli.SkillCast'
        Skill      = $selected.Key
        Name       = $selected.Name
        Class      = $selected.Class
        Target     = $targetText
        TargetId   = $targetId
        Cost       = $totalCost
        Quantity   = $Quantity
        MPBefore   = [double]$stats.MP
        MPAfter    = $mpAfter
        Data       = $data
    }
}

function Show-HabiticaSkills {
    <#
    .SYNOPSIS
      Muestra los poderes de tu clase con coste, nivel y objetivo.
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    $stats = Get-HabiticaStats -Refresh:$Refresh
    $width = Get-TerminalWidth

    if ([string]::IsNullOrWhiteSpace($stats.Class)) {
        $lines = @(
            '~gray~Tu heroe no tiene clase todavia.~/~',
            '',
            '~gray~Elige Guerrero, Picaro, Mago o Sanador en Habitica.~/~',
            '~gray~Despues podras lanzar poderes con ~/~ ~gold~h cast <n>~/~.'
        )
        Write-HabiticaBlank
        Write-HabiticaPanel -Title 'PODERES' -Lines $lines -Width $width -Color 'magenta'
        Write-HabiticaBlank
        return
    }

    $skills = @(Get-HabiticaSkill -Class $stats.Class -UserData $stats.Raw)
    $lines = @()
    $lines += ("~gray~Clase:~/~ ~white~{0}~/~   ~gray~Nivel:~/~ ~gold~{1}~/~   ~cyan~MP {2}/{3}~/~" -f $stats.ClassLabel, $stats.Level, (Format-HabiticaNumber $stats.MP 0), (Format-HabiticaNumber $stats.MaxMP 0))
    $lines += ''
    $lines += '~gray~  #   NIV   PM  PODER                        OBJETIVO         ESTADO~/~'

    foreach ($skill in $skills) {
        $lines += ("~gray~{0,3}~/~  ~white~{1,4}~/~  ~cyan~{2,3}~/~  ~gold~{3,-27}~/~  ~gray~{4,-15}~/~  ~{5}~{6,-8}~/~" -f $skill.Number, $skill.Level, $skill.Cost, $skill.Name, $skill.TargetLabel, $skill.StatusKind, $skill.Status)
    }

    $lines += ''
    $lines += '~gray~DESCRIPCIONES~/~'
    foreach ($skill in $skills) {
        $description = '{0}. {1}' -f $skill.Number, $skill.Description
        foreach ($wrapped in (Wrap-HabiticaText -Text $description -Width ($width - 8))) {
            $lines += ('  ~gray~' + $wrapped + '~/~')
        }
    }

    $lines += ''
    $lines += ("~gray~Lanzar:~/~ ~gold~h cast 1~/~   ~gray~Con objetivo:~/~ ~gold~h cast 1 --target 3~/~   ~gray~Por clave:~/~ ~gold~h cast {0}~/~" -f $skills[0].Key)
    $lines += '~gray~--target acepta numero de la ultima lista, id, alias o texto.~/~'

    Write-HabiticaBlank
    Write-HabiticaPanel -Title ("PODERES // " + $stats.Name) -Lines $lines -Width $width -Color 'magenta'
    Write-HabiticaBlank
}
