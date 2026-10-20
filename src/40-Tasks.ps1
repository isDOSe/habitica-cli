# =============================================================================
#  Habitica CLI - Tareas, habitos, diarias, recompensas y checklists
# =============================================================================

$script:PriorityLabels = @{
    0.1 = 'Trivial'
    1   = 'Facil'
    1.5 = 'Media'
    2   = 'Dificil'
}

$script:PriorityFromLabel = @{
    'trivial' = 0.1
    'facil'   = 1
    'easy'    = 1
    'media'   = 1.5
    'medio'   = 1.5
    'medium'  = 1.5
    'dificil' = 2
    'hard'    = 2
}

$script:TaskTypeLabels = @{
    todo    = 'Tarea'
    daily   = 'Diaria'
    habit   = 'Habito'
    reward  = 'Recompensa'
}

$script:TaskTypeMarkers = @{
    todo   = 'T'
    daily  = 'D'
    habit  = 'H'
    reward = 'R'
}

$script:TaskTypePlural = @{
    All           = ''
    Todo          = 'todos'
    Daily         = 'dailys'
    Habit         = 'habits'
    Reward        = 'rewards'
    CompletedTodo = 'completedTodos'
}

function Get-HabiticaTaskTypeLabel {
    param([string]$Type)
    if ($script:TaskTypeLabels.ContainsKey($Type)) { return $script:TaskTypeLabels[$Type] }
    return $Type
}

function Get-HabiticaTaskTypeMarker {
    param([string]$Type)
    if ($script:TaskTypeMarkers.ContainsKey($Type)) { return $script:TaskTypeMarkers[$Type] }
    return '?'
}

function Get-HabiticaPriorityLabel {
    param([AllowNull()]$Priority)
    try {
        $number = [double]$Priority
        if ($script:PriorityLabels.ContainsKey($number)) { return $script:PriorityLabels[$number] }
    }
    catch { }
    return 'Facil'
}

function Get-HabiticaPriorityMark {
    param([AllowNull()]$Priority)
    try {
        $number = [double]$Priority
        switch ($number) {
            0.1 { return '.' }
            1 { return '!' }
            1.5 { return '!!' }
            2 { return '!!!' }
        }
    }
    catch { }
    return '!'
}

function Test-HabiticaDailyDueToday {
    param([Parameter(Mandatory)]$Task)

    if ([bool](Get-HabiticaObjectValue $Task 'completed' $false)) { return $false }

    $today = (Get-Date).Date

    $start = ConvertTo-HabiticaDate (Get-HabiticaObjectValue $Task 'startDate' $null)
    if ($start -and $start -gt $today) { return $false }

    # Si la API ya calculo nextDue, es la fuente mas fiable.
    $nextDue = Get-HabiticaObjectValue $Task 'nextDue' $null
    if ($nextDue) {
        $dates = @(ConvertTo-HabiticaArray $nextDue | ForEach-Object { ConvertTo-HabiticaDate $_ } | Where-Object { $_ })
        if ($dates.Count -gt 0) {
            return ($dates | Where-Object { $_ -eq $today } | Select-Object -First 1) -ne $null
        }
    }

    $frequency = [string](Get-HabiticaObjectValue $Task 'frequency' 'weekly')
    $everyX = 1
    try { $everyX = [int](Get-HabiticaObjectValue $Task 'everyX' 1) } catch { $everyX = 1 }
    if ($everyX -lt 1) { $everyX = 1 }

    if (-not $start) { $start = $today }

    switch ($frequency.ToLowerInvariant()) {
        'daily' {
            $days = [int]($today - $start).TotalDays
            if ($days -lt 0) { return $false }
            return (($days % $everyX) -eq 0)
        }
        'weekly' {
            $repeat = Get-HabiticaObjectValue $Task 'repeat' $null
            if ($repeat) {
                $keys = @('su', 'm', 't', 'w', 'th', 'f', 's')
                $key = $keys[[int]$today.DayOfWeek]
                $enabled = [bool](Get-HabiticaObjectValue $repeat $key $true)
                if (-not $enabled) { return $false }
            }
            $startWeek = $start.AddDays(-1 * ([int]$start.DayOfWeek))
            $todayWeek = $today.AddDays(-1 * ([int]$today.DayOfWeek))
            $weeks = [int](($todayWeek - $startWeek).TotalDays / 7)
            if ($weeks -lt 0) { return $false }
            return (($weeks % $everyX) -eq 0)
        }
        'monthly' {
            $daysOfMonth = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $Task 'daysOfMonth' $null))
            if ($daysOfMonth.Count -gt 0) {
                return ($daysOfMonth -contains $today.Day)
            }
            $weeksOfMonth = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $Task 'weeksOfMonth' $null))
            if ($weeksOfMonth.Count -gt 0) {
                $week = [int][Math]::Ceiling($today.Day / 7)
                return ($weeksOfMonth -contains $week)
            }
            return $true
        }
        'yearly' {
            return ($today.Month -eq $start.Month -and $today.Day -eq $start.Day)
        }
        default { return $true }
    }
}

function ConvertTo-HabiticaTask {
    param([Parameter(Mandatory)]$Task)

    $type = [string](Get-HabiticaObjectValue $Task 'type' 'todo')
    $id = [string](Get-HabiticaObjectValue $Task 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { $id = [string](Get-HabiticaObjectValue $Task '_id' '') }

    $priority = Get-HabiticaObjectValue $Task 'priority' 1
    $date = ConvertTo-HabiticaDate (Get-HabiticaObjectValue $Task 'date' $null)
    $checklist = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $Task 'checklist' $null))
    $checklistDone = @($checklist | Where-Object { [bool](Get-HabiticaObjectValue $_ 'completed' $false) }).Count
    $tags = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $Task 'tags' $null) | Where-Object { $_ })

    $isDueToday = $false
    $isOverdue = $false
    if ($type -eq 'todo' -and $date) {
        $isDueToday = ($date -eq (Get-Date).Date)
        $isOverdue = ($date -lt (Get-Date).Date -and -not [bool](Get-HabiticaObjectValue $Task 'completed' $false))
    }
    elseif ($type -eq 'daily') {
        $isDueToday = Test-HabiticaDailyDueToday -Task $Task
        $isOverdue = $false
    }

    $challenge = Get-HabiticaObjectValue $Task 'challenge' $null
    $group = Get-HabiticaObjectValue $Task 'group' $null

    [pscustomobject]@{
        PSTypeName    = 'HabiticaCli.Task'
        Id            = $id
        Type          = $type
        TypeLabel     = Get-HabiticaTaskTypeLabel $type
        Marker        = Get-HabiticaTaskTypeMarker $type
        Text          = [string](Get-HabiticaObjectValue $Task 'text' '')
        Notes         = [string](Get-HabiticaObjectValue $Task 'notes' '')
        Completed     = [bool](Get-HabiticaObjectValue $Task 'completed' $false)
        Priority      = [double]$priority
        PriorityLabel = Get-HabiticaPriorityLabel $priority
        PriorityMark  = Get-HabiticaPriorityMark $priority
        Attribute     = [string](Get-HabiticaObjectValue $Task 'attribute' 'str')
        Value         = Get-HabiticaObjectValue $Task 'value' 0
        DueDate       = $date
        DueDateText   = Format-HabiticaDateHuman $date
        IsDueToday    = $isDueToday
        IsOverdue     = $isOverdue
        Tags          = $tags
        Checklist     = $checklist
        ChecklistDone = $checklistDone
        ChecklistTotal = $checklist.Count
        Frequency     = [string](Get-HabiticaObjectValue $Task 'frequency' '')
        EveryX        = Get-HabiticaObjectValue $Task 'everyX' 1
        Repeat        = Get-HabiticaObjectValue $Task 'repeat' $null
        StartDate     = ConvertTo-HabiticaDate (Get-HabiticaObjectValue $Task 'startDate' $null)
        Streak        = Get-HabiticaObjectValue $Task 'streak' 0
        CounterUp     = Get-HabiticaObjectValue $Task 'counterUp' 0
        CounterDown   = Get-HabiticaObjectValue $Task 'counterDown' 0
        Up            = [bool](Get-HabiticaObjectValue $Task 'up' $false)
        Down          = [bool](Get-HabiticaObjectValue $Task 'down' $false)
        Alias         = [string](Get-HabiticaObjectValue $Task 'alias' '')
        ChallengeId   = [string](Get-HabiticaObjectValue $challenge 'id' '')
        GroupId       = [string](Get-HabiticaObjectValue $group 'id' (Get-HabiticaObjectValue $group '_id' ''))
        Raw           = $Task
    }
}

function Get-HabiticaTask {
    <#
    .SYNOPSIS
      Obtiene tareas del usuario.
    .PARAMETER Type
      All, Todo, Daily, Habit, Reward o CompletedTodo.
    .PARAMETER Id
      UUID de una tarea concreta.
    .PARAMETER DueToday
      Filtra tareas pendientes para hoy.
    .PARAMETER Tag
      Filtra por nombre de etiqueta.
    .PARAMETER Search
      Busca texto en el titulo o las notas.
    .PARAMETER IncludeCompleted
      Incluye To-Dos completados.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('All', 'Todo', 'Daily', 'Habit', 'Reward', 'CompletedTodo')]
        [string]$Type = 'All',

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'List')]
        [switch]$DueToday,

        [Parameter(ParameterSetName = 'List')]
        [string]$Tag,

        [Parameter(ParameterSetName = 'List')]
        [string]$Search,

        [Parameter(ParameterSetName = 'List')]
        [switch]$IncludeCompleted
    )

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $data = Invoke-HabiticaApi -Method GET -Path ('tasks/{0}' -f [uri]::EscapeDataString($Id))
        if ($null -eq $data) { throw "No existe la tarea '$Id'." }
        return (ConvertTo-HabiticaTask -Task $data)
    }

    $query = @{}
    $plural = $script:TaskTypePlural[$Type]
    if (-not [string]::IsNullOrWhiteSpace($plural)) { $query.type = $plural }

    $data = Invoke-HabiticaApi -Method GET -Path 'tasks/user' -Query $query
    $tasks = @(ConvertTo-HabiticaArray $data)

    if ($Type -eq 'Todo' -and -not $IncludeCompleted) {
        $tasks = @($tasks | Where-Object { -not [bool](Get-HabiticaObjectValue $_ 'completed' $false) })
    }

    if ($Type -eq 'All' -and $IncludeCompleted) {
        $completed = Invoke-HabiticaApi -Method GET -Path 'tasks/user' -Query @{ type = 'completedTodos' }
        $tasks = @($tasks) + @(ConvertTo-HabiticaArray $completed)
    }

    if ($Tag) {
        $tagObject = Get-HabiticaTag | Where-Object { $_.Name -eq $Tag } | Select-Object -First 1
        if (-not $tagObject) { throw "No existe la etiqueta '$Tag'." }
        $tasks = @($tasks | Where-Object {
            $ids = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $_ 'tags' $null))
            $ids -contains $tagObject.Id
        })
    }

    if ($DueToday) {
        $tasks = @($tasks | Where-Object {
            $taskType = [string](Get-HabiticaObjectValue $_ 'type' '')
            if ($taskType -eq 'daily') { return (Test-HabiticaDailyDueToday -Task $_) }
            if ($taskType -eq 'todo') {
                $due = ConvertTo-HabiticaDate (Get-HabiticaObjectValue $_ 'date' $null)
                return ($due -and $due -le (Get-Date).Date -and -not [bool](Get-HabiticaObjectValue $_ 'completed' $false))
            }
            return $false
        })
    }

    if ($Search) {
        $needle = $Search.ToLowerInvariant()
        $tasks = @($tasks | Where-Object {
            $text = [string](Get-HabiticaObjectValue $_ 'text' '')
            $notes = [string](Get-HabiticaObjectValue $_ 'notes' '')
            $alias = [string](Get-HabiticaObjectValue $_ 'alias' '')
            return ($text.ToLowerInvariant().Contains($needle) -or $notes.ToLowerInvariant().Contains($needle) -or $alias.ToLowerInvariant().Contains($needle))
        })
    }

    return @($tasks | ForEach-Object { ConvertTo-HabiticaTask -Task $_ })
}

function Resolve-HabiticaTaskReference {
    <#
    .SYNOPSIS
      Convierte un indice, id, alias o fragmento de texto en una tarea real.
    #>
    param(
        [Parameter(Mandatory)][string]$Reference,
        [switch]$AllowCompleted
    )

    $reference = $Reference.Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($reference)) { throw 'Indica una tarea por numero, id, alias o texto.' }

    if ($reference -match '^[0-9a-fA-F-]{8,36}$') {
        try {
            return (Get-HabiticaTask -Id $reference)
        }
        catch {
            # Puede ser un prefijo o un texto con aspecto hexadecimal.
        }
    }

    if ($reference -match '^\d+$') {
        $index = [int]$reference
        $list = Get-HabiticaLastList
        if (-not $list -or -not $list.PSObject.Properties['items']) {
            throw ("No hay una lista reciente. Ejecuta 'h today' o 'h ls' y usa el numero que aparece.")
        }

        $item = @($list.items | Where-Object { [int]$_.index -eq $index }) | Select-Object -First 1
        if (-not $item) {
            throw ("El indice {0} no existe en la ultima lista mostrada." -f $index)
        }
        return (Get-HabiticaTask -Id $item.id)
    }

    $tasks = @(Get-HabiticaTask -Type All -IncludeCompleted)
    $needle = $reference.ToLowerInvariant()

    $matches = @($tasks | Where-Object { $_.Alias -and $_.Alias.ToLowerInvariant() -eq $needle })
    if ($matches.Count -eq 1) { return $matches[0] }

    $matches = @($tasks | Where-Object { $_.Text.ToLowerInvariant() -eq $needle })
    if ($matches.Count -eq 1) { return $matches[0] }

    $matches = @($tasks | Where-Object { $_.Text.ToLowerInvariant().Contains($needle) })
    if ($matches.Count -eq 1) { return $matches[0] }

    if ($matches.Count -gt 1) {
        $options = ($matches | Select-Object -First 5 | ForEach-Object { $_.Text }) -join ' | '
        throw ("'{0}' coincide con varias tareas: {1}. Usa el numero de la lista o el id." -f $reference, $options)
    }

    throw ("No se encontro ninguna tarea que coincida con '{0}'." -f $reference)
}

function New-HabiticaTask {
    <#
    .SYNOPSIS
      Crea una tarea en Habitica.
    .EXAMPLE
      New-HabiticaTask -Type Todo -Text 'Comprar leche' -Priority Media -DueDate (Get-Date).AddDays(1)
    .EXAMPLE
      New-HabiticaTask -Type Daily -Text 'Ejercicio' -Frequency Weekly -RepeatDays mon,wed,fri
    .EXAMPLE
      New-HabiticaTask -Type Reward -Text 'Ver una pelicula' -Cost 20
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Todo', 'Daily', 'Habit', 'Reward')]
        [string]$Type = 'Todo',

        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Text,

        [string]$Notes,
        [ValidateSet('Trivial', 'Facil', 'Media', 'Dificil')]
        [string]$Priority,

        [ValidateSet('Str', 'Int', 'Per', 'Con')]
        [string]$Attribute,

        [string[]]$Tag,
        [string]$Alias,
        [datetime]$DueDate,

        [ValidateSet('Daily', 'Weekly', 'Monthly', 'Yearly')]
        [string]$Frequency,

        [ValidateRange(1, 365)]
        [int]$EveryX,

        [string[]]$RepeatDays,
        [datetime]$StartDate,
        [string[]]$Checklist,

        [switch]$Up,
        [switch]$Down,

        [double]$Cost
    )

    $taskType = $Type.ToLowerInvariant()
    $body = [ordered]@{
        text = $Text
        type = $taskType
    }

    if ($PSBoundParameters.ContainsKey('Notes')) { $body.notes = $Notes }
    if ($PSBoundParameters.ContainsKey('Priority')) {
        $key = $Priority.ToLowerInvariant()
        if (-not $script:PriorityFromLabel.ContainsKey($key)) { throw "Prioridad no valida: $Priority" }
        $body.priority = [double]$script:PriorityFromLabel[$key]
    }
    if ($PSBoundParameters.ContainsKey('Attribute')) { $body.attribute = $Attribute.ToLowerInvariant() }
    if ($PSBoundParameters.ContainsKey('Alias')) { $body.alias = $Alias }

    if ($Tag -and $Tag.Count -gt 0) {
        $body.tags = @($Tag | ForEach-Object { Resolve-HabiticaTagId -Reference $_ })
    }

    if ($Checklist -and $Checklist.Count -gt 0) {
        $body.checklist = @($Checklist | ForEach-Object { @{ text = $_ } })
    }

    switch ($taskType) {
        'todo' {
            if ($PSBoundParameters.ContainsKey('DueDate')) { $body.date = $DueDate.ToString('yyyy-MM-dd') }
        }
        'habit' {
            if ($Up -and -not $Down) { $body.up = $true; $body.down = $false }
            elseif ($Down -and -not $Up) { $body.up = $false; $body.down = $true }
            else { $body.up = $true; $body.down = $true }
        }
        'daily' {
            $freq = 'weekly'
            if ($PSBoundParameters.ContainsKey('Frequency')) { $freq = $Frequency.ToLowerInvariant() }
            $body.frequency = $freq
            if ($PSBoundParameters.ContainsKey('EveryX')) { $body.everyX = $EveryX }
            if ($PSBoundParameters.ContainsKey('StartDate')) { $body.startDate = $StartDate.ToString('yyyy-MM-dd') }
            if ($PSBoundParameters.ContainsKey('DueDate')) { $body.startDate = $DueDate.ToString('yyyy-MM-dd') }

            if ($freq -eq 'weekly') {
                $days = @()
                if ($RepeatDays -and $RepeatDays.Count -gt 0) {
                    $days = @(ConvertTo-HabiticaRepeatDays -Days $RepeatDays)
                }
                else {
                    $days = @((Get-Date).DayOfWeek.ToString())
                }
                $repeat = @{ su = $false; m = $false; t = $false; w = $false; th = $false; f = $false; s = $false }
                foreach ($day in $days) {
                    $key = Get-HabiticaRepeatKey -Day $day
                    if ($key) { $repeat[$key] = $true }
                }
                $body.repeat = $repeat
            }
        }
        'reward' {
            if ($PSBoundParameters.ContainsKey('Cost')) { $body.value = $Cost }
        }
    }

    if ($PSCmdlet.ShouldProcess(("{0}: {1}" -f (Get-HabiticaTaskTypeLabel $taskType), $Text), 'Crear en Habitica')) {
        $response = Invoke-HabiticaApi -Method POST -Path 'tasks/user' -Body $body -Full
        $created = ConvertTo-HabiticaTask -Task $response.data
        $gender = if ($created.Type -eq 'habit') { 'creado' } else { 'creada' }
        Write-HabiticaOk ("{0} {1}: {2}" -f $created.TypeLabel, $gender, $created.Text)
        return $created
    }
}

function ConvertTo-HabiticaRepeatDays {
    param([string[]]$Days)

    return @($Days | ForEach-Object {
        $day = $_.Trim().ToLowerInvariant()
        switch ($day) {
            'lun' { 'lunes' }
            'mar' { 'martes' }
            'mie' { 'miercoles' }
            'jue' { 'jueves' }
            'vie' { 'viernes' }
            'sab' { 'sabado' }
            'dom' { 'domingo' }
            default { $day }
        }
    })
}

function Get-HabiticaRepeatKey {
    param([string]$Day)

    switch ($Day.Trim().ToLowerInvariant()) {
        'domingo' { return 'su' }
        'sunday' { return 'su' }
        'dom' { return 'su' }
        'sun' { return 'su' }
        'su' { return 'su' }
        'lunes' { return 'm' }
        'monday' { return 'm' }
        'lun' { return 'm' }
        'mon' { return 'm' }
        'm' { return 'm' }
        'martes' { return 't' }
        'tuesday' { return 't' }
        'mar' { return 't' }
        'tue' { return 't' }
        't' { return 't' }
        'miercoles' { return 'w' }
        'wednesday' { return 'w' }
        'mie' { return 'w' }
        'wed' { return 'w' }
        'w' { return 'w' }
        'jueves' { return 'th' }
        'thursday' { return 'th' }
        'jue' { return 'th' }
        'thu' { return 'th' }
        'th' { return 'th' }
        'viernes' { return 'f' }
        'friday' { return 'f' }
        'vie' { return 'f' }
        'fri' { return 'f' }
        'f' { return 'f' }
        'sabado' { return 's' }
        'saturday' { return 's' }
        'sab' { return 's' }
        'sat' { return 's' }
        's' { return 's' }
        default { return '' }
    }
}

function Set-HabiticaTask {
    <#
    .SYNOPSIS
      Actualiza los campos de una tarea existente.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('TaskId')]
        [string]$Id,

        [string]$Text,
        [string]$Notes,

        [ValidateSet('Trivial', 'Facil', 'Media', 'Dificil')]
        [string]$Priority,

        [ValidateSet('Str', 'Int', 'Per', 'Con')]
        [string]$Attribute,

        [datetime]$DueDate,
        [switch]$ClearDueDate,
        [switch]$Completed,
        [switch]$Reopen,
        [double]$Cost,

        [ValidateSet('Daily', 'Weekly', 'Monthly', 'Yearly')]
        [string]$Frequency,

        [ValidateRange(1, 365)]
        [int]$EveryX,

        [string[]]$RepeatDays,
        [datetime]$StartDate,

        [switch]$Up,
        [switch]$Down
    )

    process {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Text')) { $body.text = $Text }
        if ($PSBoundParameters.ContainsKey('Notes')) { $body.notes = $Notes }
        if ($PSBoundParameters.ContainsKey('Priority')) {
            $key = $Priority.ToLowerInvariant()
            $body.priority = [double]$script:PriorityFromLabel[$key]
        }
        if ($PSBoundParameters.ContainsKey('Attribute')) { $body.attribute = $Attribute.ToLowerInvariant() }
        if ($PSBoundParameters.ContainsKey('DueDate')) { $body.date = $DueDate.ToString('yyyy-MM-dd') }
        if ($ClearDueDate) { $body.date = $null }
        if ($Completed) { $body.completed = $true }
        if ($Reopen) { $body.completed = $false }
        if ($PSBoundParameters.ContainsKey('Cost')) { $body.value = $Cost }
        if ($PSBoundParameters.ContainsKey('Frequency')) { $body.frequency = $Frequency.ToLowerInvariant() }
        if ($PSBoundParameters.ContainsKey('EveryX')) { $body.everyX = $EveryX }
        if ($PSBoundParameters.ContainsKey('StartDate')) { $body.startDate = $StartDate.ToString('yyyy-MM-dd') }

        if ($RepeatDays -and $RepeatDays.Count -gt 0) {
            $repeat = @{ su = $false; m = $false; t = $false; w = $false; th = $false; f = $false; s = $false }
            foreach ($day in (ConvertTo-HabiticaRepeatDays -Days $RepeatDays)) {
                $key = Get-HabiticaRepeatKey -Day $day
                if ($key) { $repeat[$key] = $true }
            }
            $body.repeat = $repeat
        }

        if ($Up -and -not $Down) { $body.up = $true; $body.down = $false }
        elseif ($Down -and -not $Up) { $body.up = $false; $body.down = $true }
        elseif ($Up -and $Down) { $body.up = $true; $body.down = $true }

        if ($body.Count -eq 0) { throw 'Indica al menos un campo para actualizar.' }

        if ($PSCmdlet.ShouldProcess("Tarea '$Id'", 'Actualizar')) {
            $response = Invoke-HabiticaApi -Method PUT -Path ('tasks/{0}' -f [uri]::EscapeDataString($Id)) -Body $body -Full
            $updated = ConvertTo-HabiticaTask -Task $response.data
            Write-HabiticaOk ("Actualizada: {0}" -f $updated.Text)
            return $updated
        }
    }
}

function Remove-HabiticaTask {
    <#
    .SYNOPSIS
      Elimina una tarea de forma permanente.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('TaskId')]
        [string]$Id,

        [switch]$Force
    )

    process {
        $task = $null
        try { $task = Get-HabiticaTask -Id $Id } catch { }
        $label = if ($task) { $task.Text } else { $Id }

        if (-not $Force -and -not (Test-InteractiveHost)) {
            throw ("Operacion destructiva sobre '{0}'. Usa --yes para confirmar." -f $label)
        }
        if (-not (Confirm-HabiticaAction -Message ("Eliminar definitivamente '{0}'?" -f $label) -Force:$Force)) {
            Write-HabiticaWarn 'Cancelado.'
            return
        }

        if ($PSCmdlet.ShouldProcess("Tarea '$label'", 'Eliminar')) {
            Invoke-HabiticaApi -Method DELETE -Path ('tasks/{0}' -f [uri]::EscapeDataString($Id)) | Out-Null
            Write-HabiticaOk ("Eliminada: {0}" -f $label)
            return [pscustomobject]@{ PSTypeName = 'HabiticaCli.DeletedTask'; Id = $Id; Text = $label; Deleted = $true }
        }
    }
}

function Show-HabiticaScoreFeedback {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$TaskText,
        [Parameter(Mandatory)][string]$Direction
    )

    $data = Get-HabiticaObjectValue $Response 'data' $null
    $delta = Get-HabiticaObjectValue $data 'delta' $null
    $symbol = if ($Direction -eq 'down') { '-' } else { '+' }

    Write-HabiticaBlank
    if ($Direction -eq 'down') {
        Write-HabiticaLine ("  ~gold~{0}~/~  {1}" -f $symbol, $TaskText)
    }
    else {
        Write-HabiticaLine ("  ~green~{0}~/~  {1}" -f $symbol, $TaskText)
    }

    if ($delta) {
        $parts = @()
        $xp = Get-HabiticaObjectValue $delta 'exp' $null
        $gp = Get-HabiticaObjectValue $delta 'gp' $null
        $hp = Get-HabiticaObjectValue $delta 'hp' $null
        $mp = Get-HabiticaObjectValue $delta 'mp' $null

        if ($null -ne $xp) { $parts += ("{0}{1} XP" -f $(if ([double]$xp -ge 0) { '+' } else { '' }), (Format-HabiticaNumber $xp 1)) }
        if ($null -ne $gp) { $parts += ("{0}{1} GP" -f $(if ([double]$gp -ge 0) { '+' } else { '' }), (Format-HabiticaNumber $gp 2)) }
        if ($null -ne $hp) { $parts += ("{0}{1} HP" -f $(if ([double]$hp -ge 0) { '+' } else { '' }), (Format-HabiticaNumber $hp 1)) }
        if ($null -ne $mp) { $parts += ("{0}{1} MP" -f $(if ([double]$mp -ge 0) { '+' } else { '' }), (Format-HabiticaNumber $mp 1)) }

        if ($parts.Count -gt 0) {
            Write-HabiticaLine ("         ~gray~{0}~/~" -f ($parts -join '   '))
        }

        $level = Get-HabiticaObjectValue $data 'lvl' $null
        if ($null -ne $level) {
            Write-HabiticaLine ("         ~gray~Nivel actual: ~gold~{0}~/~" -f $level)
        }
    }
    else {
        $message = Get-HabiticaPropertyText -Object $Response -Name 'message' -Default ''
        if ($message) { Write-HabiticaLine ("         ~gray~{0}~/~" -f $message) }
    }
    Write-HabiticaBlank
}

function Invoke-HabiticaTaskScore {
    <#
    .SYNOPSIS
      Puntua una tarea hacia arriba o hacia abajo.
    .PARAMETER Direction
      Up (completar/ganar) o Down (deshacer/perder).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('TaskId')]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('Up', 'Down')]
        [string]$Direction,

        [string]$Text
    )

    process {
        $directionLower = $Direction.ToLowerInvariant()
        if ($PSCmdlet.ShouldProcess("Tarea '$Id'", ("Puntuar {0}" -f $Direction))) {
            $response = Invoke-HabiticaApi -Method POST -Path ('tasks/{0}/score/{1}' -f [uri]::EscapeDataString($Id), $directionLower) -Full

            if (-not $Text) { $Text = $Id }
            Show-HabiticaScoreFeedback -Response $response -TaskText $Text -Direction $directionLower

            if (Get-Command Update-HabiticaStatsCacheFromScore -ErrorAction SilentlyContinue) {
                Update-HabiticaStatsCacheFromScore -ScoreData $response.data
            }

            return [pscustomobject]@{
                PSTypeName = 'HabiticaCli.ScoreResult'
                Id         = $Id
                Direction  = $Direction
                Data       = $response.data
            }
        }
    }
}

function Complete-HabiticaTask {
    <#
    .SYNOPSIS
      Completa una tarea (score up). Equivale a marcarla como hecha.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('TaskId')]
        [string]$Id,

        [string]$Text
    )

    process {
        if ($Text -and $Text -ne $Id) {
            $task = Get-HabiticaTask -Id $Id
            if ($task.Type -eq 'reward') {
                throw ("'{0}' es una recompensa. Usa 'h buy {1}' para comprarla." -f $task.Text, $Id)
            }
        }
        Invoke-HabiticaTaskScore -Id $Id -Direction Up -Text $Text
    }
}

function Move-HabiticaTask {
    <#
    .SYNOPSIS
      Reordena una tarea dentro de su lista.
    .PARAMETER Position
      Posicion 0-based. Usa -1 para enviarla al final.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][int]$Position
    )

    if ($PSCmdlet.ShouldProcess("Tarea '$Id'", ("Mover a posicion {0}" -f $Position))) {
        Invoke-HabiticaApi -Method POST -Path ('tasks/{0}/move/to/{1}' -f [uri]::EscapeDataString($Id), $Position) | Out-Null
        Write-HabiticaOk ("Tarea movida a la posicion {0}." -f $Position)
    }
}

function Clear-HabiticaCompletedTodo {
    <#
    .SYNOPSIS
      Elimina todos los To-Dos completados.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Force)

    if (-not $Force -and -not (Test-InteractiveHost)) {
        throw 'Operacion destructiva. Usa --yes para confirmar.'
    }
    if (-not (Confirm-HabiticaAction -Message 'Eliminar TODOS los To-Dos completados?' -Force:$Force)) {
        Write-HabiticaWarn 'Cancelado.'
        return
    }

    if ($PSCmdlet.ShouldProcess('To-Dos completados', 'Eliminar')) {
        Invoke-HabiticaApi -Method POST -Path 'tasks/clearCompletedTodos' | Out-Null
        Write-HabiticaOk 'To-Dos completados eliminados.'
    }
}

# -----------------------------------------------------------------------------
#  Checklists
# -----------------------------------------------------------------------------

function ConvertTo-HabiticaChecklistItem {
    param([Parameter(Mandatory)]$TaskId, [Parameter(Mandatory)]$Item, [int]$Index = 0)

    [pscustomobject]@{
        PSTypeName = 'HabiticaCli.ChecklistItem'
        Index      = $Index
        TaskId     = $TaskId
        Id         = [string](Get-HabiticaObjectValue $Item 'id' '')
        Text       = [string](Get-HabiticaObjectValue $Item 'text' '')
        Completed  = [bool](Get-HabiticaObjectValue $Item 'completed' $false)
    }
}

function Get-HabiticaChecklistItem {
    <#
    .SYNOPSIS
      Lista los items de checklist de una tarea.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId)

    $task = Get-HabiticaTask -Id $TaskId
    $items = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue $task.Raw 'checklist' $null))
    $index = 0
    return @($items | ForEach-Object {
        $index++
        ConvertTo-HabiticaChecklistItem -TaskId $TaskId -Item $_ -Index $index
    })
}

function Get-HabiticaChecklistItemsFromResponse {
    param([Parameter(Mandatory)]$TaskId, [Parameter(Mandatory)]$Response)

    $items = @(ConvertTo-HabiticaArray (Get-HabiticaObjectValue (Get-HabiticaObjectValue $Response 'data' $null) 'checklist' $null))
    $index = 0
    return @($items | ForEach-Object {
        $index++
        ConvertTo-HabiticaChecklistItem -TaskId $TaskId -Item $_ -Index $index
    })
}

function Add-HabiticaChecklistItem {
    <#
    .SYNOPSIS
      Agrega un item a la checklist de una tarea.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Text
    )

    if ($PSCmdlet.ShouldProcess("Checklist de '$TaskId'", ("Agregar '{0}'" -f $Text))) {
        $response = Invoke-HabiticaApi -Method POST -Path ('tasks/{0}/checklist' -f [uri]::EscapeDataString($TaskId)) -Body @{ text = $Text } -Full
        Write-HabiticaOk ("Checklist: {0}" -f $Text)
        return (Get-HabiticaChecklistItemsFromResponse -TaskId $TaskId -Response $response)
    }
}

function Set-HabiticaChecklistItem {
    <#
    .SYNOPSIS
      Actualiza el texto o el estado de un item de checklist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$Text,
        [switch]$Completed,
        [switch]$Reopen
    )

    $body = @{}
    if ($PSBoundParameters.ContainsKey('Text')) { $body.text = $Text }
    if ($Completed) { $body.completed = $true }
    if ($Reopen) { $body.completed = $false }
    if ($body.Count -eq 0) { throw 'Indica texto, -Completed o -Reopen.' }

    if ($PSCmdlet.ShouldProcess("Item '$ItemId'", 'Actualizar checklist')) {
        $response = Invoke-HabiticaApi -Method PUT -Path ('tasks/{0}/checklist/{1}' -f [uri]::EscapeDataString($TaskId), [uri]::EscapeDataString($ItemId)) -Body $body -Full
        Write-HabiticaOk 'Checklist actualizada.'
        return (Get-HabiticaChecklistItemsFromResponse -TaskId $TaskId -Response $response)
    }
}

function Complete-HabiticaChecklistItem {
    <#
    .SYNOPSIS
      Alterna el estado completado de un item de checklist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ItemId
    )

    if ($PSCmdlet.ShouldProcess("Item '$ItemId'", 'Alternar completado')) {
        $response = Invoke-HabiticaApi -Method POST -Path ('tasks/{0}/checklist/{1}/score' -f [uri]::EscapeDataString($TaskId), [uri]::EscapeDataString($ItemId)) -Full
        Write-HabiticaOk 'Checklist actualizada.'
        return (Get-HabiticaChecklistItemsFromResponse -TaskId $TaskId -Response $response)
    }
}

function Remove-HabiticaChecklistItem {
    <#
    .SYNOPSIS
      Elimina un item de checklist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ItemId
    )

    if ($PSCmdlet.ShouldProcess("Item '$ItemId'", 'Eliminar del checklist')) {
        Invoke-HabiticaApi -Method DELETE -Path ('tasks/{0}/checklist/{1}' -f [uri]::EscapeDataString($TaskId), [uri]::EscapeDataString($ItemId)) | Out-Null
        Write-HabiticaOk 'Item de checklist eliminado.'
    }
}
