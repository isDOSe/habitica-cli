# =============================================================================
#  Habitica CLI - Render visual ASCII
# =============================================================================

$script:TagNameCache = $null
$script:TagNameCacheAt = [DateTime]::MinValue

$script:BannerLines = @(
    '  _   _    _    ____ ___ _____ ___ ____    _    '
    ' | | | |  / \  | __ )_ _|_   _|_ _/ ___|  / \   '
    ' | |_| | / _ \ |  _ \| |  | |  | | |     / _ \  '
    ' |  _  |/ ___ \| |_) | |  | |  | | |___ / ___ \ '
    ' |_| |_/_/   \_\____/___| |_| |___\____/_/   \_\'
    ''
    '      C E N T R O   D E   M A N D O   D E L   H E R O E'
)

function Get-HabiticaBannerLines {
    param([int]$Width = 86)

    if ($Width -lt 62) {
        return @(
            "~gold~+~/~~gray~$('-' * ($Width - 2))~/~~gold~+~/~",
            ("~gold~|~/~  ~gold~H A B I T I C A~/~  ~gray~C L I~/~" + (' ' * [Math]::Max(0, $Width - 25)) + "~gold~|~/~"),
            "~gold~+~/~~gray~$('-' * ($Width - 2))~/~~gold~+~/~"
        )
    }

    $lines = @()
    foreach ($line in $script:BannerLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { $lines += ''; continue }
        $padding = [int][Math]::Max(0, [Math]::Floor(($Width - $line.Length) / 2))
        $lines += ((' ' * $padding) + "~gold~" + $line + "~/~")
    }
    return $lines
}

function Get-HabiticaPanelLines {
    param(
        [Parameter(Mandatory)][string]$Title,
        [AllowEmptyCollection()][string[]]$Lines = @(),
        [int]$Width = 86,
        [string]$Color = 'cyan'
    )

    if ($Width -lt 30) { $Width = 30 }
    $safeTitle = $Title
    $maxTitle = $Width - 12
    if ((Get-HabiticaVisibleLength $safeTitle) -gt $maxTitle) {
        $safeTitle = Truncate-HabiticaText $safeTitle $maxTitle
    }

    $titleWidth = Get-HabiticaVisibleLength $safeTitle
    $dashCount = $Width - 8 - $titleWidth
    if ($dashCount -lt 0) { $dashCount = 0 }
    $result = @()
    $result += ("~${Color}~+--[ ~gold~$safeTitle~${Color}~ ]" + ("-" * $dashCount) + "~/~~${Color}~+~/~")

    $inner = $Width - 4
    foreach ($line in $Lines) {
        if ($null -eq $line) { $line = '' }
        $result += ("~${Color}~|~/~ " + (Pad-HabiticaText -Text $line -Width $inner) + " ~${Color}~|~/~")
    }

    $result += ("~${Color}~+" + ("-" * ($Width - 2)) + "+~/~")
    return $result
}

function Write-HabiticaPanel {
    param(
        [Parameter(Mandatory)][string]$Title,
        [AllowEmptyCollection()][string[]]$Lines = @(),
        [int]$Width = 0,
        [string]$Color = 'cyan'
    )

    if ($Width -le 0) { $Width = Get-TerminalWidth }
    foreach ($line in (Get-HabiticaPanelLines -Title $Title -Lines $Lines -Width $Width -Color $Color)) {
        Write-HabiticaLine $line
    }
}

function Get-HabiticaTagMap {
    param([switch]$Refresh)

    if (-not $Refresh -and $null -ne $script:TagNameCache -and ((Get-Date) - $script:TagNameCacheAt).TotalSeconds -lt 90) {
        return $script:TagNameCache
    }

    $map = @{}
    try {
        foreach ($tag in @(Get-HabiticaTag)) { $map[$tag.Id] = $tag.Name }
    }
    catch { }
    $script:TagNameCache = $map
    $script:TagNameCacheAt = Get-Date
    return $map
}

function Get-HabiticaTaskDueDisplay {
    param([Parameter(Mandatory)]$Task)

    if ($Task.Type -eq 'todo') {
        if (-not $Task.DueDate) { return '-' }
        return $Task.DueDateText
    }
    if ($Task.Type -eq 'daily') {
        if ($Task.IsDueToday) { return 'hoy' }
        switch ($Task.Frequency) {
            'daily' { return 'diaria' }
            'weekly' { return 'semanal' }
            'monthly' { return 'mensual' }
            'yearly' { return 'anual' }
            default { return '-' }
        }
    }
    return '-'
}

function Get-HabiticaTaskInfoDisplay {
    param([Parameter(Mandatory)]$Task)

    $parts = @()
    if ($Task.ChecklistTotal -gt 0) { $parts += ('[{0}/{1}]' -f $Task.ChecklistDone, $Task.ChecklistTotal) }
    if ($Task.Type -eq 'daily' -and [double]$Task.Streak -gt 0) { $parts += ('x{0}' -f $Task.Streak) }
    if ($Task.Type -eq 'habit') { $parts += ('+{0}/-{1}' -f $Task.CounterUp, $Task.CounterDown) }
    if ($Task.Type -eq 'reward') { $parts += ('{0}g' -f (Format-HabiticaNumber $Task.Value 0)) }
    if ($Task.ChallengeId) { $parts += '*' }
    if ($parts.Count -eq 0) { return '-' }
    return ($parts -join ' ')
}

function Get-HabiticaTaskTableLines {
    param(
        [AllowEmptyCollection()][object[]]$Tasks = @(),
        [int]$SelectedIndex = -1,
        [int]$ContentWidth = 82,
        [int]$StartIndex = 1,
        [int]$MaxRows = 0,
        [switch]$NoHeader
    )

    $markerWidth = 1
    $indexWidth = 3
    $typeWidth = 1
    $priorityWidth = 3
    $dueWidth = 10
    $infoWidth = 8
    $fixed = $markerWidth + 1 + $indexWidth + 1 + $typeWidth + 1 + $priorityWidth + 1 + $dueWidth + 1 + $infoWidth + 1
    $textWidth = $ContentWidth - $fixed
    if ($textWidth -lt 12) {
        $textWidth = 12
        $infoWidth = 6
        $dueWidth = 8
    }

    $lines = @()
    if (-not $NoHeader) {
        $header = (' ' * ($markerWidth + 1)) + (Pad-HabiticaText '#' $indexWidth 'Right') + ' ' +
            (Pad-HabiticaText 'T' $typeWidth) + ' ' +
            (Pad-HabiticaText 'P' $priorityWidth) + ' ' +
            (Pad-HabiticaText 'VENCE' $dueWidth) + ' ' +
            (Pad-HabiticaText 'INFO' $infoWidth) + ' ' +
            'TAREA'
        $lines += "~gray~$header~/~"
    }

    if ($null -eq $Tasks -or $Tasks.Count -eq 0) {
        $lines += "~gray~  (sin tareas)~/~"
        return $lines
    }

    $limit = $Tasks.Count
    if ($MaxRows -gt 0 -and $limit -gt $MaxRows) { $limit = $MaxRows }

    for ($i = 0; $i -lt $limit; $i++) {
        $task = $Tasks[$i]
        $number = $StartIndex + $i
        $selected = ($SelectedIndex -eq $i)
        $marker = if ($selected) { '~gold~>~/~' } else { ' ' }

        $typeColor = switch ($task.Type) {
            'todo' { 'cyan' }
            'daily' { 'magenta' }
            'habit' { 'green' }
            'reward' { 'gold' }
            default { 'white' }
        }
        $priorityColor = switch ($task.Priority) {
            0.1 { 'gray' }
            1 { 'green' }
            1.5 { 'gold' }
            2 { 'red' }
            default { 'white' }
        }

        $dueColor = 'gray'
        if ($task.IsOverdue) { $dueColor = 'red' }
        elseif ($task.IsDueToday) { $dueColor = 'gold' }

        $textColor = 'white'
        if ($task.Completed) { $textColor = 'gray' }
        if ($selected) { $textColor = 'gold' }

        $text = $task.Text
        if ($task.Completed) { $text = '[x] ' + $text }

        $line = $marker + ' ' +
            "~gray~" + (Pad-HabiticaText ([string]$number) $indexWidth 'Right') + "~/~" + ' ' +
            "~${typeColor}~" + (Pad-HabiticaText $task.Marker $typeWidth) + "~/~" + ' ' +
            "~${priorityColor}~" + (Pad-HabiticaText $task.PriorityMark $priorityWidth) + "~/~" + ' ' +
            "~${dueColor}~" + (Pad-HabiticaText (Get-HabiticaTaskDueDisplay -Task $task) $dueWidth) + "~/~" + ' ' +
            "~gray~" + (Pad-HabiticaText (Get-HabiticaTaskInfoDisplay -Task $task) $infoWidth) + "~/~" + ' ' +
            "~${textColor}~" + (Truncate-HabiticaText $text $textWidth) + "~/~"

        $lines += $line
    }

    if ($MaxRows -gt 0 -and $Tasks.Count -gt $MaxRows) {
        $lines += ("~gray~  ... y {0} mas. Usa -Max o filtra con -Search.~/~" -f ($Tasks.Count - $MaxRows))
    }

    return $lines
}

function Get-HabiticaTaskDetailLines {
    param(
        [Parameter(Mandatory)]$Task,
        [int]$ContentWidth = 82
    )

    $tagMap = Get-HabiticaTagMap
    $tagNames = @()
    foreach ($tagId in @($Task.Tags)) {
        if ($tagMap.ContainsKey($tagId)) { $tagNames += '#' + $tagMap[$tagId] }
        else { $tagNames += '#' + ([string]$tagId).Substring(0, [Math]::Min(6, ([string]$tagId).Length)) }
    }

    $lines = @()
    $lines += "~gold~$($Task.Text)~/~"
    $lines += ("~gray~Tipo:~/~ ~white~{0}~/~   ~gray~Prioridad:~/~ ~gold~{1}~/~   ~gray~Vence:~/~ ~white~{2}~/~   ~gray~Atributo:~/~ ~white~{3}~/~" -f $Task.TypeLabel, $Task.PriorityLabel, (Get-HabiticaTaskDueDisplay -Task $Task), $Task.Attribute.ToUpperInvariant())

    if ($Task.Notes) {
        $lines += ''
        foreach ($wrapped in (Wrap-HabiticaText -Text $Task.Notes -Width ($ContentWidth - 2))) {
            $lines += "~gray~$wrapped~/~"
        }
    }

    $meta = @()
    if ($tagNames.Count -gt 0) { $meta += ('~gray~Etiquetas:~/~ ~cyan~' + ($tagNames -join ' ') + '~/~') }
    if ($Task.ChecklistTotal -gt 0) { $meta += ('~gray~Checklist:~/~ ~white~{0}/{1}~/~' -f $Task.ChecklistDone, $Task.ChecklistTotal) }
    if ($Task.Streak -and [double]$Task.Streak -gt 0) { $meta += ('~gray~Racha:~/~ ~gold~{0}{1}~/~' -f $Task.Streak, $(if ($Task.Type -eq 'daily') { ' dias' } else { '' })) }
    if ($Task.Alias) { $meta += ('~gray~Alias:~/~ ~white~{0}~/~' -f $Task.Alias) }
    if ($Task.ChallengeId) { $meta += ('~gray~Reto:~/~ ~magenta~{0}~/~' -f $Task.ChallengeId.Substring(0, [Math]::Min(8, $Task.ChallengeId.Length))) }
    if ($meta.Count -gt 0) { $lines += ($meta -join '   ') }

    if ($Task.ChecklistTotal -gt 0) {
        $lines += ''
        foreach ($item in @($Task.Checklist)) {
            $checked = [bool](Get-HabiticaObjectValue $item 'completed' $false)
            $itemText = [string](Get-HabiticaObjectValue $item 'text' '')
            if ($checked) { $lines += "  ~green~[x]~/~ ~gray~$itemText~/~" }
            else { $lines += "  ~gray~[ ]~/~ $itemText" }
        }
    }

    $lines += ''
    $lines += ("~gray~ID:~/~ ~gray~{0}~/~" -f $Task.Id)
    return $lines
}

function Get-HabiticaStatsPanelLines {
    param(
        [Parameter(Mandatory)]$Stats,
        [int]$ContentWidth = 82,
        [switch]$Compact
    )

    $barWidth = 16
    if ($ContentWidth -lt 70) { $barWidth = 10 }

    $hpRatio = 0
    if ($Stats.MaxHP -gt 0) { $hpRatio = $Stats.HP / $Stats.MaxHP }
    $hpColor = 'green'
    if ($hpRatio -le 0.25) { $hpColor = 'red' }
    elseif ($hpRatio -le 0.5) { $hpColor = 'gold' }

    $hpBar = New-HabiticaProgressBar -Current $Stats.HP -Maximum $Stats.MaxHP -Width $barWidth -Color $hpColor
    $xpBar = New-HabiticaProgressBar -Current $Stats.XP -Maximum $Stats.MaxXP -Width $barWidth -Color 'gold'
    $mpBar = New-HabiticaProgressBar -Current $Stats.MP -Maximum $Stats.MaxMP -Width $barWidth -Color 'cyan'

    $lines = @()
    if ($Compact) {
        $lines += ("~gray~LVL~/~ ~gold~{0}~/~ ~white~{1}~/~   ~red~HP~/~ {2} {3}/{4}   ~cyan~MP~/~ {5} {6}/{7}   ~gold~GP~/~ {8}" -f $Stats.Level, $Stats.ClassLabel, $hpBar, [Math]::Round($Stats.HP), [Math]::Round($Stats.MaxHP), $mpBar, [Math]::Round($Stats.MP), [Math]::Round($Stats.MaxMP), (Format-HabiticaNumber $Stats.Gold 2))
        return $lines
    }

    $lines += ("~gray~NIVEL~/~ ~gold~{0}~/~    ~gray~CLASE~/~ ~white~{1}~/~    ~gray~PUNTOS~/~ ~white~{2}~/~" -f $Stats.Level, $Stats.ClassLabel, $Stats.Points)
    $lines += ("~red~HP~/~  {0} {1}/{2}      ~cyan~MP~/~  {3} {4}/{5}" -f $hpBar, [Math]::Round($Stats.HP), [Math]::Round($Stats.MaxHP), $mpBar, [Math]::Round($Stats.MP), [Math]::Round($Stats.MaxMP))
    $lines += ("~gold~XP~/~  {0} {1}/{2}      ~gold~ORO~/~ {3} GP" -f $xpBar, [Math]::Round($Stats.XP), [Math]::Round($Stats.MaxXP), (Format-HabiticaNumber $Stats.Gold 2))
    $lines += ("~gray~FUE~/~ ~white~{0}~/~   ~gray~INT~/~ ~white~{1}~/~   ~gray~PER~/~ ~white~{2}~/~   ~gray~CON~/~ ~white~{3}~/~   ~gray~RACHA~/~ ~gold~{4}~/~" -f $Stats.Strength, $Stats.Intelligence, $Stats.Perception, $Stats.Constitution, (Get-HabiticaObjectValue (Get-HabiticaObjectValue $Stats.Raw 'stats' $null) 'streak' 0))
    return $lines
}

function Get-HabiticaTodayTasks {
    param([int]$MaxItems = 20)

    $all = @(Get-HabiticaTask -Type All)
    $today = (Get-Date).Date

    $urgent = @()
    $dailies = @()
    foreach ($task in $all) {
        if ($task.Completed) { continue }
        if ($task.Type -eq 'todo') {
            if ($task.DueDate -and $task.DueDate -le $today) { $urgent += $task }
        }
        elseif ($task.Type -eq 'daily') {
            if ($task.IsDueToday) { $dailies += $task }
        }
    }

    $urgent = @($urgent | Sort-Object DueDate)
    $result = @($urgent) + @($dailies)
    if ($MaxItems -gt 0 -and $result.Count -gt $MaxItems) { $result = @($result[0..($MaxItems - 1)]) }
    return $result
}

function Show-HabiticaDashboard {
    <#
    .SYNOPSIS
      Panel principal: banner, estadisticas y misiones de hoy.
    .PARAMETER Refresh
      Ignora la cache de usuario.
    .PARAMETER Clear
      Limpia la pantalla antes de dibujar.
    #>
    [CmdletBinding()]
    param(
        [switch]$Refresh,
        [switch]$Clear
    )

    if ($Clear) { Clear-Host }

    $width = Get-TerminalWidth
    $contentWidth = $width - 4
    $height = Get-TerminalHeight

    try {
        $user = Get-HabiticaUser -Refresh:$Refresh
        $stats = Get-HabiticaStats -UserData $user
    }
    catch {
        Write-HabiticaBlank
        foreach ($line in (Get-HabiticaBannerLines -Width $width)) { Write-HabiticaLine $line }
        Write-HabiticaBlank
        Write-HabiticaPanel -Title 'SIN CONEXION' -Lines @(
            '~red~No se pudieron cargar tus datos.~/~',
            '',
            ('~gray~' + $_.Exception.Message + '~/~'),
            '',
            'Ejecuta ~gold~h config init~/~ para configurar tus credenciales,',
            'o revisa tu conexion con ~gold~h config test~/~.'
        ) -Width $width -Color 'red'
        Write-HabiticaBlank
        return
    }

    foreach ($line in (Get-HabiticaBannerLines -Width $width)) { Write-HabiticaLine $line }
    Write-HabiticaBlank

    $statsLines = Get-HabiticaStatsPanelLines -Stats $stats -ContentWidth $contentWidth
    foreach ($line in (Get-HabiticaPanelLines -Title ("{0}  //  {1}" -f $stats.Name.ToUpperInvariant(), $stats.ClassLabel.ToUpperInvariant()) -Lines $statsLines -Width $width -Color 'gold')) {
        Write-HabiticaLine $line
    }

    Write-HabiticaBlank

    $tasks = @()
    $taskError = $null
    try { $tasks = @(Get-HabiticaTodayTasks -MaxItems 50) }
    catch { $taskError = $_.Exception.Message }

    if ($taskError) {
        Write-HabiticaPanel -Title 'MISIONES DE HOY' -Lines @("~red~$taskError~/~") -Width $width -Color 'red'
    }
    else {
        $maxRows = $height - 20
        if ($maxRows -lt 4) { $maxRows = 4 }
        if ($maxRows -gt 12) { $maxRows = 12 }

        Set-HabiticaLastList -Key 'today' -Tasks $tasks
        $overdue = @($tasks | Where-Object { $_.IsOverdue }).Count
        $dueToday = @($tasks | Where-Object { $_.IsDueToday }).Count
        $title = 'MISIONES DE HOY'
        if ($tasks.Count -gt 0) {
            $overdueLabel = if ($overdue -eq 1) { 'vencida' } else { 'vencidas' }
            $title = 'MISIONES DE HOY  ({0} para hoy, {1} {2})' -f $dueToday, $overdue, $overdueLabel
        }

        if ($tasks.Count -eq 0) {
            $panelLines = @(
                '~green~Todo despejado, heroe.~/~',
                '',
                '~gray~No hay tareas para hoy. Aprovecha para crear una:~/~',
                '  ~gold~h add "Mi proxima mision"~/~'
            )
        }
        else {
            $panelLines = Get-HabiticaTaskTableLines -Tasks $tasks -ContentWidth $contentWidth -MaxRows $maxRows
            $panelLines += ''
            $panelLines += '~gray~Completa con:~/~ ~gold~h done <numero>~/~    ~gray~Detalle:~/~ ~gold~h show <numero>~/~'
        }
        foreach ($line in (Get-HabiticaPanelLines -Title $title -Lines $panelLines -Width $width -Color 'cyan')) {
            Write-HabiticaLine $line
        }
    }

    Write-HabiticaBlank

    $party = Get-HabiticaObjectValue $user 'party' $null
    $partyName = Get-HabiticaPropertyText -Object $party -Name 'name' -Default ''
    $notifications = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $user 'notifications' $null)).Count
    $quest = Get-HabiticaObjectValue $party 'quest' $null
    $questKey = Get-HabiticaPropertyText -Object $quest -Name 'key' -Default ''

    $footer = @()
    if ($partyName) { $footer += ('~gray~Party:~/~ ~white~{0}~/~' -f $partyName) }
    if ($questKey) { $footer += ('~gray~Quest:~/~ ~magenta~{0}~/~' -f $questKey) }
    if ($notifications -gt 0) { $footer += ('~gold~{0} notificacion{1}~/~' -f $notifications, $(if ($notifications -eq 1) { '' } else { 'es' })) }
    if ($footer.Count -gt 0) {
        Write-HabiticaLine ("  " + ($footer -join '   '))
        Write-HabiticaBlank
    }

    Write-HabiticaLine ("  ~gray~h help~/~ comandos   ~gray~|~/~   ~gold~h ui~/~ panel interactivo   ~gray~|~/~   ~gold~h add~/~ nueva mision")
    Write-HabiticaBlank
}

function Show-HabiticaTaskList {
    <#
    .SYNOPSIS
      Muestra una lista de tareas con indices.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'Todo', 'Daily', 'Habit', 'Reward', 'CompletedTodo')]
        [string]$Type = 'Todo',

        [string]$Title,
        [string]$Tag,
        [string]$Search,
        [int]$Max = 0
    )

    $width = Get-TerminalWidth
    $contentWidth = $width - 4

    $tasks = @(Get-HabiticaTask -Type $Type -Tag $Tag -Search $Search)

    if (-not $Title) {
        $Title = switch ($Type) {
            'All' { 'TODAS LAS TAREAS' }
            'Todo' { 'TAREAS PENDIENTES' }
            'Daily' { 'DIARIAS' }
            'Habit' { 'HABITOS' }
            'Reward' { 'RECOMPENSAS' }
            'CompletedTodo' { 'TAREAS COMPLETADAS' }
        }
    }
    $Title = '{0}  ({1})' -f $Title, $tasks.Count

    $listKey = switch ($Type) {
        'All' { 'all' }
        'Todo' { 'todos' }
        'Daily' { 'dailies' }
        'Habit' { 'habits' }
        'Reward' { 'rewards' }
        'CompletedTodo' { 'completed' }
    }
    Set-HabiticaLastList -Key $listKey -Tasks $tasks

    Write-HabiticaBlank
    if ($tasks.Count -eq 0) {
        Write-HabiticaPanel -Title $Title -Lines @('~gray~No hay tareas que mostrar.~/~', '', 'Crea una con ~gold~h add "texto"~/~.') -Width $width
        Write-HabiticaBlank
        return @()
    }

    $lines = Get-HabiticaTaskTableLines -Tasks $tasks -ContentWidth $contentWidth -MaxRows $Max
    $lines += ''
    $lines += '~gray~T=Tarea  D=Diaria  H=Habito  R=Recompensa   P=prioridad (! facil, !!! dificil)~/~'
    switch ($Type) {
        'Habit' { $lines += '~gray~Sube:~/~ ~gold~h up <n>~/~   ~gray~Baja:~/~ ~gold~h down <n>~/~   ~gray~Detalle:~/~ ~gold~h show <n>~/~' }
        'Reward' { $lines += '~gray~Compra:~/~ ~gold~h buy <n>~/~   ~gray~Detalle:~/~ ~gold~h show <n>~/~' }
        default { $lines += '~gray~Completa:~/~ ~gold~h done <n>~/~   ~gray~Deshaz:~/~ ~gold~h undo <n>~/~   ~gray~Detalle:~/~ ~gold~h show <n>~/~' }
    }

    Write-HabiticaPanel -Title $Title -Lines $lines -Width $width
    Write-HabiticaBlank
}

function Show-HabiticaTaskDetail {
    <#
    .SYNOPSIS
      Muestra el detalle completo de una tarea.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Reference)

    $task = Resolve-HabiticaTaskReference -Reference $Reference
    $width = Get-TerminalWidth

    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaPanelLines -Title 'DETALLE DE LA MISION' -Lines (Get-HabiticaTaskDetailLines -Task $task -ContentWidth ($width - 4)) -Width $width -Color 'gold')) {
        Write-HabiticaLine $line
    }
    Write-HabiticaBlank
}

function Show-HabiticaAllTasks {
    <#
    .SYNOPSIS
      Muestra todas las tareas agrupadas por tipo.
    #>
    [CmdletBinding()]
    param(
        [string]$Tag,
        [string]$Search
    )

    $width = Get-TerminalWidth
    $contentWidth = $width - 4
    $tasks = @(Get-HabiticaTask -Type All -Tag $Tag -Search $Search)
    Set-HabiticaLastList -Key 'all' -Tasks $tasks

    Write-HabiticaBlank
    if ($tasks.Count -eq 0) {
        Write-HabiticaPanel -Title 'TODAS LAS TAREAS' -Lines @('~gray~No tienes tareas todavia.~/~', '', 'Crea la primera con ~gold~h add "texto"~/~.') -Width $width
        Write-HabiticaBlank
        return
    }

    $groups = @(
        @{ Type = 'todo'; Title = 'TAREAS' },
        @{ Type = 'daily'; Title = 'DIARIAS' },
        @{ Type = 'habit'; Title = 'HABITOS' },
        @{ Type = 'reward'; Title = 'RECOMPENSAS' }
    )

    $offset = 0
    $total = $tasks.Count
    foreach ($group in $groups) {
        $subset = @($tasks | Where-Object { $_.Type -eq $group.Type })
        if ($subset.Count -eq 0) { continue }
        $lines = Get-HabiticaTaskTableLines -Tasks $subset -ContentWidth $contentWidth -StartIndex ($offset + 1) -NoHeader
        foreach ($line in (Get-HabiticaPanelLines -Title ("{0}  ({1})" -f $group.Title, $subset.Count) -Lines $lines -Width $width -Color 'cyan')) {
            Write-HabiticaLine $line
        }
        Write-HabiticaBlank
        $offset += $subset.Count
    }

    Write-HabiticaLine ("  ~gray~Total: ~white~{0}~/~ tareas. Usa ~gold~h show <n>~/~ para ver el detalle." -f $total)
    Write-HabiticaBlank
}

function Show-HabiticaParty {
    <#
    .SYNOPSIS
      Muestra la party con sus miembros y estado de la quest.
    #>
    [CmdletBinding()]
    param([switch]$IncludeChat)

    $width = Get-TerminalWidth
    $contentWidth = $width - 4

    try {
        $party = Get-HabiticaParty
    }
    catch {
        Write-HabiticaError $_.Exception.Message
        return
    }

    Write-HabiticaBlank
    if (-not $party) {
        Write-HabiticaPanel -Title 'PARTY' -Lines @(
            '~gold~No perteneces a ninguna party.~/~',
            '',
            'Crea una con ~gold~h party create "Nombre"~/~',
            'o pide a un amigo que te invite.'
        ) -Width $width
        Write-HabiticaBlank
        return
    }

    $name = Get-HabiticaPropertyText -Object $party -Name 'name' -Default 'Mi party'
    $description = Get-HabiticaPropertyText -Object $party -Name 'description' -Default ''
    $memberCount = Get-HabiticaObjectValue $party -Name 'memberCount' -Default $null
    if ($null -eq $memberCount) {
        $membersRaw = Get-HabiticaObjectValue $party 'members' $null
        if ($membersRaw) { $memberCount = @(ConvertTo-HabiticaArray $membersRaw).Count }
    }

    $headerLines = @()
    $headerLines += ("~gold~$name~/~")
    if ($description) { $headerLines += ("~gray~$description~/~") }
    $headerLines += ("~gray~Miembros:~/~ ~white~{0}~/~   ~gray~ID:~/~ ~gray~{1}~/~" -f $memberCount, (Get-HabiticaObjectValue $party '_id' ''))

    foreach ($line in (Get-HabiticaPanelLines -Title 'PARTY' -Lines $headerLines -Width $width -Color 'magenta')) {
        Write-HabiticaLine $line
    }

    Write-HabiticaBlank
    try {
        $members = @(Get-HabiticaPartyMembers -GroupId ([string](Get-HabiticaObjectValue $party '_id' 'party')))
        $lines = @()
        if ($members.Count -eq 0) {
            $lines += '~gray~No se pudieron cargar los miembros.~/~'
        }
        else {
            $lines += '~gray~  #  NIVEL  CLASE       NOMBRE                     HP~/~'
            $index = 0
            foreach ($member in $members) {
                $index++
                $hpRatio = 0
                if ([double]$member.MaxHP -gt 0) { $hpRatio = [double]$member.HP / [double]$member.MaxHP }
                $hpColor = if ($hpRatio -le 0.3) { 'red' } elseif ($hpRatio -le 0.6) { 'gold' } else { 'green' }
                $hpBar = New-HabiticaProgressBar -Current $member.HP -Maximum $member.MaxHP -Width 10 -Color $hpColor
                $lines += ("~gray~{0,3}~/~  ~white~{1,5}~/~  ~cyan~{2,-10}~/~  ~white~{3,-24}~/~  {4}" -f $index, $member.Level, $member.ClassLabel, (Truncate-HabiticaText $member.Name 24), $hpBar)
            }
        }
        foreach ($line in (Get-HabiticaPanelLines -Title ("MIEMBROS  ({0})" -f $members.Count) -Lines $lines -Width $width -Color 'cyan')) {
            Write-HabiticaLine $line
        }
    }
    catch {
        Write-HabiticaWarn $_.Exception.Message
    }

    Write-HabiticaBlank
    try {
        $quest = Get-HabiticaQuest
        if ($quest -and $quest.Key) {
            $questLines = Get-HabiticaQuestLines -Quest $quest -ContentWidth $contentWidth
            foreach ($line in (Get-HabiticaPanelLines -Title 'QUEST' -Lines $questLines -Width $width -Color 'gold')) {
                Write-HabiticaLine $line
            }
        }
        else {
            Write-HabiticaPanel -Title 'QUEST' -Lines @('~gray~Sin quest activa ni pendiente.~/~', '', 'Invita una con ~gold~h quest invite <clave>~/~.') -Width $width -Color 'gold'
        }
    }
    catch {
        Write-HabiticaWarn $_.Exception.Message
    }

    if ($IncludeChat) {
        Write-HabiticaBlank
        Show-HabiticaChat -Limit 10
    }

    Write-HabiticaBlank
}

function Get-HabiticaQuestLines {
    param(
        [Parameter(Mandatory)]$Quest,
        [int]$ContentWidth = 82
    )

    $lines = @()
    $status = if ($Quest.Active) { '~green~ACTIVA~/~' } elseif ($Quest.Key) { '~gold~PENDIENTE~/~' } else { '~gray~NINGUNA~/~' }
    $lines += ("~gold~{0}~/~   {1}" -f $Quest.Name, $status)

    if ($Quest.ProgressHp -ne $null -and [double]$Quest.BossMaxHp -gt 0) {
        $hp = [double]$Quest.ProgressHp
        $bar = New-HabiticaProgressBar -Current $hp -Maximum $Quest.BossMaxHp -Width 24 -Color 'red'
        $lines += ("~red~JEFE~/~ {0} {1}/{2} HP" -f $bar, [Math]::Round($hp), [Math]::Round($Quest.BossMaxHp))
    }

    if ([double]$Quest.RageMax -gt 0) {
        $rageBar = New-HabiticaProgressBar -Current $Quest.Rage -Maximum $Quest.RageMax -Width 24 -Color 'magenta'
        $lines += ("~magenta~RAGE~/~ {0} {1}/{2}" -f $rageBar, [Math]::Round($Quest.Rage), [Math]::Round($Quest.RageMax))
    }

    foreach ($item in @($Quest.Collect)) {
        $bar = New-HabiticaProgressBar -Current $item.Collected -Maximum $item.Total -Width 24 -Color 'cyan'
        $lines += ("~cyan~ITEM~/~ {0} {1}/{2} {3}" -f $bar, $item.Collected, $item.Total, $item.Text)
    }

    $lines += ("~gray~Progreso:~/~ ~white~up {0}~/~ / ~white~down {1}~/~   ~gray~Miembros:~/~ ~white~{2}~/~" -f $Quest.Up, $Quest.Down, $Quest.MemberCount)

    if ($Quest.Description) {
        $lines += ''
        foreach ($wrapped in (Wrap-HabiticaText -Text $Quest.Description -Width ($ContentWidth - 2))) {
            $lines += "~gray~$wrapped~/~"
        }
    }

    if (-not $Quest.Active -and $Quest.Key) {
        $lines += ''
        $lines += '~gray~Acepta con:~/~ ~gold~h quest accept~/~   ~gray~Rechaza:~/~ ~gold~h quest reject~/~'
        $lines += '~gray~Inicia:~/~ ~gold~h quest start~/~   ~gray~Cancela:~/~ ~gold~h quest cancel~/~'
    }
    elseif ($Quest.Active) {
        $lines += ''
        $lines += '~gray~Abortar:~/~ ~gold~h quest abort~/~   ~gray~Salir:~/~ ~gold~h quest leave~/~'
    }

    return $lines
}

function Show-HabiticaQuest {
    <#
    .SYNOPSIS
      Muestra el estado de la quest de la party.
    #>
    [CmdletBinding()]
    param()

    $width = Get-TerminalWidth
    $quest = Get-HabiticaQuest
    Write-HabiticaBlank
    if (-not $quest -or -not $quest.Key) {
        Write-HabiticaPanel -Title 'QUEST' -Lines @(
            '~gray~La party no tiene una quest activa ni pendiente.~/~',
            '',
            'Invita una con ~gold~h quest invite <clave>~/~.',
            'Puedes ver tus quests disponibles con ~gold~h quest list~/~.'
        ) -Width $width -Color 'gold'
        Write-HabiticaBlank
        return
    }

    foreach ($line in (Get-HabiticaPanelLines -Title 'QUEST DE LA PARTY' -Lines (Get-HabiticaQuestLines -Quest $quest -ContentWidth ($width - 4)) -Width $width -Color 'gold')) {
        Write-HabiticaLine $line
    }
    Write-HabiticaBlank
}

function Show-HabiticaQuestList {
    <#
    .SYNOPSIS
      Lista las quests que posees (inventario).
    #>
    [CmdletBinding()]
    param()

    $width = Get-TerminalWidth
    $user = Get-HabiticaUser -UserFields 'items.quests,profile'
    $items = Get-HabiticaObjectValue $user 'items' $null
    $quests = Get-HabiticaObjectValue $items 'quests' $null
    $owned = @()
    if ($quests) {
        foreach ($property in $quests.PSObject.Properties) {
            if ([int]$property.Value -gt 0) {
                $info = Get-HabiticaQuestInfo -Key $property.Name
                $name = if ($info) { Get-HabiticaPropertyText -Object $info -Name 'text' -Default $property.Name } else { $property.Name }
                $owned += [pscustomobject]@{ Key = $property.Name; Name = $name; Count = $property.Value }
            }
        }
    }

    Write-HabiticaBlank
    if ($owned.Count -eq 0) {
        Write-HabiticaPanel -Title 'QUESTS DISPONIBLES' -Lines @('~gray~No tienes pergaminos de quest en tu inventario.~/~') -Width $width -Color 'gold'
        Write-HabiticaBlank
        return
    }

    $lines = @('~gray~CLAVE                         NOMBRE~/~')
    foreach ($item in ($owned | Sort-Object Name)) {
        $lines += ("~gold~{0,-28}~/~  ~white~{1}~/~" -f $item.Key, $item.Name)
    }
    $lines += ''
    $lines += '~gray~Invita con:~/~ ~gold~h quest invite <clave>~/~'
    Write-HabiticaPanel -Title ('QUESTS DISPONIBLES  ({0})' -f $owned.Count) -Lines $lines -Width $width -Color 'gold'
    Write-HabiticaBlank
}

function Write-HabiticaChatView {
    param(
        [AllowEmptyCollection()][object[]]$Messages = @(),
        [int]$SelectedIndex = -1,
        [int]$ContentWidth = 82,
        [switch]$NoHeader
    )

    if ($Messages.Count -eq 0) {
        Write-HabiticaLine '~gray~  (sin mensajes)~/~'
        return
    }

    $i = 0
    foreach ($message in $Messages) {
        $selected = ($SelectedIndex -eq $i)
        $marker = if ($selected) { '~gold~>~/~' } else { ' ' }
        $time = Format-HabiticaTimestamp -Timestamp $message.Timestamp -WithTime
        $authorColor = if ($message.IsSystem) { 'gray' } else { 'cyan' }
        $likes = ''
        if ([int]$message.Likes -gt 0) { $likes = ('  ~gold~+{0}~/~' -f $message.Likes) }

        if ($message.IsSystem) {
            Write-HabiticaLine ("$marker ~gray~[{0}] {1}~/~" -f $time, (Truncate-HabiticaText $message.Text ($ContentWidth - 14)))
        }
        else {
            Write-HabiticaLine ("$marker ~gray~[{0}]~/~ ~${authorColor}~{1}~/~{2}" -f $time, (Truncate-HabiticaText $message.AuthorName 16), $likes)
            $wrapped = @(Wrap-HabiticaText -Text $message.Text -Width ($ContentWidth - 6))
            foreach ($line in $wrapped) {
                Write-HabiticaLine ("    " + $(if ($selected) { "~gold~$line~/~" } else { $line }))
            }
        }
        $i++
    }
}

function Show-HabiticaChat {
    <#
    .SYNOPSIS
      Muestra los ultimos mensajes del chat de la party.
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 20,
        [string]$GroupId = 'party'
    )

    $width = Get-TerminalWidth
    $contentWidth = $width - 4
    $messages = @(Get-HabiticaChat -GroupId $GroupId -Limit $Limit)
    Write-HabiticaBlank
    if ($messages.Count -eq 0) {
        Write-HabiticaPanel -Title 'CHAT' -Lines @('~gray~No hay mensajes en el chat.~/~', '', 'Escribe con ~gold~h chat "mensaje"~/~.') -Width $width -Color 'cyan'
        Write-HabiticaBlank
        return
    }

    $lines = @()
    foreach ($message in $messages) {
        $time = Format-HabiticaTimestamp -Timestamp $message.Timestamp -WithTime
        $likes = if ([int]$message.Likes -gt 0) { ('  ~gold~+{0}~/~' -f $message.Likes) } else { '' }
        if ($message.IsSystem) {
            $lines += ("~gray~[{0}] {1}~/~" -f $time, (ConvertFrom-HabiticaMarkdown $message.Text))
        }
        else {
            $lines += ("~gray~[{0}]~/~ ~cyan~{1}~/~{2}" -f $time, $message.AuthorName, $likes)
            foreach ($wrapped in (Wrap-HabiticaText -Text $message.Text -Width ($contentWidth - 4))) {
                $lines += ("  " + $wrapped)
            }
        }
    }
    $lines += ''
    $lines += '~gold~h chat "mensaje"~/~ enviar   ~gold~h chat like <n>~/~ me gusta   ~gold~h chat seen~/~ marcar leido'

    Write-HabiticaPanel -Title ('CHAT DE LA PARTY  ({0} mensajes)' -f $messages.Count) -Lines $lines -Width $width -Color 'cyan'
    Write-HabiticaBlank
}

function Show-HabiticaChallengeList {
    <#
    .SYNOPSIS
      Lista retos con indices.
    #>
    [CmdletBinding()]
    param(
        [switch]$Member,
        [switch]$Owned,
        [string]$Search,
        [int]$Page = 0
    )

    $width = Get-TerminalWidth
    $challenges = @(Get-HabiticaChallengeList -Member:$Member -Owned:$Owned -Search $Search -Page $Page)

    $title = 'RETOS'
    if ($Owned) { $title = 'RETOS QUE POSEO' }
    elseif ($Member) { $title = 'RETOS EN LOS QUE PARTICIPO' }
    if ($Search) { $title += "  //  '$Search'" }
    $title += ('  ({0}, pagina {1})' -f $challenges.Count, $Page)

    Write-HabiticaBlank
    if ($challenges.Count -eq 0) {
        Write-HabiticaPanel -Title $title -Lines @('~gray~No hay retos que mostrar.~/~', '', 'Prueba ~gold~h challenges --search palabra~/~ o ~gold~h challenges --page 1~/~.') -Width $width -Color 'magenta'
        Write-HabiticaBlank
        return
    }

    $lines = @()
    $lines += '~gray~  #  RETO                                     PREMIO  MIEMBROS  GRUPO~/~'
    $index = 0
    foreach ($challenge in $challenges) {
        $index++
        $prize = '{0}g' -f (Format-HabiticaNumber $challenge.Prize 0)
        $lines += ("~gray~{0,3}~/~  ~white~{1,-40}~/~  ~gold~{2,6}~/~  ~cyan~{3,8}~/~  ~gray~{4}~/~" -f $index, (Truncate-HabiticaText $challenge.Name 40), $prize, $challenge.MemberCount, (Truncate-HabiticaText $challenge.GroupName 18))
    }
    $lines += ''
    $lines += '~gray~Detalle:~/~ ~gold~h challenge show <n>~/~   ~gray~Unirse:~/~ ~gold~h challenge join <n>~/~   ~gray~Salir:~/~ ~gold~h challenge leave <n>~/~'
    if ($challenges.Count -ge 10) { $lines += ('~gray~Hay mas resultados: usa ~gold~h challenges --page {0}~/~.' -f ($Page + 1)) }

    Write-HabiticaPanel -Title $title -Lines $lines -Width $width -Color 'magenta'
    Write-HabiticaBlank
}

function Show-HabiticaChallengeDetail {
    <#
    .SYNOPSIS
      Muestra el detalle de un reto.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Reference)

    $challenge = Resolve-HabiticaChallengeReference -Reference $Reference
    $width = Get-TerminalWidth
    $contentWidth = $width - 4

    $lines = @()
    $lines += "~gold~$($challenge.Name)~/~"
    $lines += ("~gray~Grupo:~/~ ~white~{0}~/~   ~gray~Premio:~/~ ~gold~{1} gemas~/~   ~gray~Miembros:~/~ ~white~{2}~/~" -f $challenge.GroupName, $challenge.Prize, $challenge.MemberCount)
    if ($challenge.Official) { $lines += '~gold~RETO OFICIAL~/~' }
    if ($challenge.Summary) {
        $lines += ''
        foreach ($wrapped in (Wrap-HabiticaText -Text $challenge.Summary -Width $contentWidth)) { $lines += "~cyan~$wrapped~/~" }
    }
    if ($challenge.Description) {
        $lines += ''
        foreach ($wrapped in (Wrap-HabiticaText -Text $challenge.Description -Width $contentWidth)) { $lines += $wrapped }
    }
    $lines += ''
    $lines += ("~gray~ID:~/~ ~gray~{0}~/~" -f $challenge.Id)

    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaPanelLines -Title 'DETALLE DEL RETO' -Lines $lines -Width $width -Color 'magenta')) {
        Write-HabiticaLine $line
    }
    Write-HabiticaBlank
}

function Show-HabiticaTags {
    <#
    .SYNOPSIS
      Lista las etiquetas del usuario.
    #>
    [CmdletBinding()]
    param()

    $width = Get-TerminalWidth
    $tags = @(Get-HabiticaTag)
    Write-HabiticaBlank
    if ($tags.Count -eq 0) {
        Write-HabiticaPanel -Title 'ETIQUETAS' -Lines @('~gray~No tienes etiquetas.~/~', '', 'Crea una con ~gold~h tag add "Trabajo"~/~.') -Width $width -Color 'cyan'
        Write-HabiticaBlank
        return
    }

    $lines = @('~gray~  #  ETIQUETA                            ID~/~')
    $index = 0
    foreach ($tag in $tags) {
        $index++
        $lines += ("~gray~{0,3}~/~  ~cyan~#{1,-35}~/~  ~gray~{2}~/~" -f $index, $tag.Name, $tag.Id)
    }
    $lines += ''
    $lines += '~gray~Asociar:~/~ ~gold~h tag attach <tarea> <etiqueta>~/~   ~gray~Renombrar:~/~ ~gold~h tag rename <n> "Nuevo"~/~'
    Write-HabiticaPanel -Title ('ETIQUETAS  ({0})' -f $tags.Count) -Lines $lines -Width $width -Color 'cyan'
    Write-HabiticaBlank
}

function Show-HabiticaNotifications {
    <#
    .SYNOPSIS
      Lista las notificaciones de Habitica.
    #>
    [CmdletBinding()]
    param()

    $width = Get-TerminalWidth
    $notifications = @(Get-HabiticaNotification)
    Write-HabiticaBlank
    if ($notifications.Count -eq 0) {
        Write-HabiticaPanel -Title 'NOTIFICACIONES' -Lines @('~green~No tienes notificaciones pendientes.~/~') -Width $width -Color 'cyan'
        Write-HabiticaBlank
        return
    }

    $lines = @()
    $index = 0
    foreach ($notification in $notifications) {
        $index++
        $seen = if ($notification.Seen) { '~gray~(vista)~/~' } else { '~gold~(nueva)~/~' }
        $detail = Get-HabiticaPropertyText -Object $notification.Data -Name 'message' -Default ''
        if (-not $detail) { $detail = $notification.Type }
        $lines += ("~gray~{0,3}~/~  ~cyan~{1,-22}~/~ {2}  {3}" -f $index, $notification.Type, (Truncate-HabiticaText $detail 40), $seen)
    }
    $lines += ''
    $lines += '~gray~Marcar leidas:~/~ ~gold~h notify read~/~   ~gray~Marcar vistas:~/~ ~gold~h notify see~/~'
    Write-HabiticaPanel -Title ('NOTIFICACIONES  ({0})' -f $notifications.Count) -Lines $lines -Width $width -Color 'gold'
    Write-HabiticaBlank
}

function Show-HabiticaInbox {
    <#
    .SYNOPSIS
      Muestra el buzon de mensajes privados.
    #>
    [CmdletBinding()]
    param([int]$Page = 0)

    $width = Get-TerminalWidth
    $contentWidth = $width - 4
    $messages = @(Get-HabiticaInbox -Page $Page)
    Write-HabiticaBlank
    if ($messages.Count -eq 0) {
        Write-HabiticaPanel -Title 'BUZON' -Lines @('~gray~No hay mensajes en esta pagina.~/~') -Width $width -Color 'blue'
        Write-HabiticaBlank
        return
    }

    $lines = @()
    foreach ($message in $messages) {
        $from = Get-HabiticaMemberName -MemberId $message.FromId
        $time = Format-HabiticaTimestamp -Timestamp $message.Timestamp -WithTime
        $lines += ("~gray~[{0}]~/~ ~cyan~{1}~/~" -f $time, $from)
        foreach ($wrapped in (Wrap-HabiticaText -Text $message.Text -Width $contentWidth)) { $lines += "  $wrapped" }
        $lines += ''
    }
    $lines += '~gray~Responder:~/~ ~gold~h inbox send <uuid> "mensaje"~/~'
    Write-HabiticaPanel -Title ('BUZON  (pagina {0})' -f $Page) -Lines $lines -Width $width -Color 'blue'
    Write-HabiticaBlank
}

function Show-HabiticaProfile {
    <#
    .SYNOPSIS
      Ficha del heroe con estadisticas y progreso.
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    $width = Get-TerminalWidth
    $stats = Get-HabiticaStats -Refresh:$Refresh
    $user = $stats.Raw
    $profile = Get-HabiticaObjectValue $user 'profile' $null
    $joined = Get-HabiticaObjectValue $profile 'joined' $null

    $lines = Get-HabiticaStatsPanelLines -Stats $stats -ContentWidth ($width - 4)
    $lines += ''
    $lines += ("~gray~Nombre:~/~ ~white~{0}~/~" -f $stats.Name)
    if ($joined) { $lines += ("~gray~Desde:~/~ ~white~{0}~/~" -f (Format-HabiticaTimestamp -Timestamp $joined)) }
    $lines += ("~gray~Atributos:~/~ ~white~FUE {0}  INT {1}  PER {2}  CON {3}~/~" -f $stats.Strength, $stats.Intelligence, $stats.Perception, $stats.Constitution)

    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaPanelLines -Title 'FICHA DEL HEROE' -Lines $lines -Width $width -Color 'gold')) {
        Write-HabiticaLine $line
    }
    Write-HabiticaBlank
}
