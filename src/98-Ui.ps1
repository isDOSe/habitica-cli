# =============================================================================
#  Habitica CLI - Panel interactivo (TUI)
# =============================================================================

$script:UiDataCache = @{}
$script:UiTabs = @(
    @{ Key = 'today'; Title = 'Hoy' },
    @{ Key = 'todo'; Title = 'Tareas' },
    @{ Key = 'daily'; Title = 'Diarias' },
    @{ Key = 'habit'; Title = 'Habitos' },
    @{ Key = 'reward'; Title = 'Premios' },
    @{ Key = 'party'; Title = 'Party' },
    @{ Key = 'chat'; Title = 'Chat' },
    @{ Key = 'quest'; Title = 'Quest' },
    @{ Key = 'challenge'; Title = 'Retos' },
    @{ Key = 'profile'; Title = 'Perfil' },
    @{ Key = 'skill'; Title = 'Poderes' }
)

function Get-HabiticaUiTabIndex {
    param([Parameter(Mandatory)][string]$Key)

    for ($i = 0; $i -lt $script:UiTabs.Count; $i++) {
        if ($script:UiTabs[$i].Key -eq $Key) { return $i }
    }
    return -1
}

function Reset-HabiticaUiData {
    $script:UiDataCache = @{}
}

function Get-HabiticaUiData {
    param(
        [Parameter(Mandatory)][string]$Key,
        [switch]$Force
    )

    if (-not $Force -and $script:UiDataCache.ContainsKey($Key)) {
        return $script:UiDataCache[$Key]
    }

    $value = $null
    switch ($Key) {
        'today' { $value = @(Get-HabiticaTodayTasks -MaxItems 100) }
        'todo' { $value = @(Get-HabiticaTask -Type Todo) }
        'daily' { $value = @(Get-HabiticaTask -Type Daily) }
        'habit' { $value = @(Get-HabiticaTask -Type Habit) }
        'reward' { $value = @(Get-HabiticaTask -Type Reward) }
        'party' { $value = Get-HabiticaParty }
        'partymembers' {
            $party = Get-HabiticaUiData -Key 'party'
            if ($party) { $value = @(Get-HabiticaPartyMembers -GroupId ([string](Get-HabiticaObjectValue $party '_id' 'party'))) }
            else { $value = @() }
        }
        'chat' { $value = @(Get-HabiticaChat -Limit 30) }
        'quest' { $value = Get-HabiticaQuest }
        'challenge' { $value = @(Get-HabiticaChallengeList -Member -Page 0) }
        'stats' { $value = Get-HabiticaStats }
        'skill' { $value = @(Get-HabiticaSkill) }
        default { $value = $null }
    }

    $script:UiDataCache[$Key] = $value
    return $value
}

function Read-HabiticaUiInput {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$Secure
    )

    Set-HabiticaCursorVisible $true
    Write-Host ''
    if ($Secure) {
        $secureValue = Read-Host ('  ' + $Prompt) -AsSecureString
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
            $value = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }
    else {
        $value = Read-Host ('  ' + $Prompt)
    }
    Set-HabiticaCursorVisible $false
    return $value
}

function Read-HabiticaUiKey {
    return [Console]::ReadKey($true)
}

function Clear-HabiticaUiScreen {
    try {
        if ($script:UseColor) {
            [Console]::Write("$($script:Esc)[2J$($script:Esc)[H")
        }
        else {
            [Console]::Clear()
        }
        [Console]::SetCursorPosition(0, 0)
    }
    catch {
        try { Clear-Host } catch { }
    }
}

function Enter-HabiticaUiScreen {
    $script:UiAltScreenActive = $false
    if (-not $script:UseColor) { return }
    try {
        [Console]::Write("$($script:Esc)[?1049h")
        [Console]::Write("$($script:Esc)[2J$($script:Esc)[H")
        $script:UiAltScreenActive = $true
    }
    catch { }
}

function Exit-HabiticaUiScreen {
    if (-not $script:UiAltScreenActive) { return }
    try {
        [Console]::Write("$($script:Esc)[?1049l")
    }
    catch { }
    $script:UiAltScreenActive = $false
}

function Show-HabiticaUiOverlay {
    param(
        [Parameter(Mandatory)][string]$Title,
        [AllowEmptyCollection()][string[]]$Lines = @(),
        [int]$Width = 86
    )

    Clear-HabiticaUiScreen
    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaBannerLines -Width $Width)) { Write-HabiticaLine $line }
    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaPanelLines -Title $Title -Lines $Lines -Width $Width -Color 'gold')) {
        Write-HabiticaLine $line
    }
    Write-HabiticaBlank
    Write-HabiticaLine '  ~gray~Pulsa cualquier tecla para volver.~/~'
    [void](Read-HabiticaUiKey)
}

function Set-HabiticaUiTaskScore {
    param(
        [Parameter(Mandatory)]$Task,
        [Parameter(Mandatory)][ValidateSet('Up', 'Down')][string]$Direction
    )

    if ($Direction -eq 'Up' -and $Task.Type -eq 'reward') {
        throw ("'{0}' es una recompensa. Usa la tecla de compra (b) o 'h buy'." -f $Task.Text)
    }

    $response = Invoke-HabiticaApi -Method POST -Path ('tasks/{0}/score/{1}' -f [uri]::EscapeDataString($Task.Id), $Direction.ToLowerInvariant()) -Full
    Update-HabiticaStatsCacheFromScore -ScoreData $response.data

    $delta = Get-HabiticaObjectValue (Get-HabiticaObjectValue $response 'data' $null) 'delta' $null
    $suffix = ''
    if ($delta) {
        $xp = Get-HabiticaObjectValue $delta 'exp' $null
        $gp = Get-HabiticaObjectValue $delta 'gp' $null
        if ($null -ne $xp) { $suffix += $(if ([double]$xp -ge 0) { ' +{0} XP' -f [Math]::Round([double]$xp) } else { ' {0} XP' -f [Math]::Round([double]$xp) }) }
        if ($null -ne $gp) { $suffix += $(if ([double]$gp -ge 0) { ' +{0} GP' -f [Math]::Round([double]$gp, 2) } else { ' {0} GP' -f [Math]::Round([double]$gp, 2) }) }
    }

    foreach ($key in @('today', 'todo', 'daily', 'habit', 'reward', 'stats')) {
        if ($script:UiDataCache.ContainsKey($key)) { $script:UiDataCache.Remove($key) }
    }
    return ("{0}: {1}{2}" -f $(if ($Direction -eq 'Up') { 'Completada' } else { 'Deshecha' }), $Task.Text, $suffix)
}

function Get-HabiticaUiTaskDetailShort {
    param([Parameter(Mandatory)]$Task, [int]$Width = 80)

    $tagMap = Get-HabiticaTagMap
    $tagNames = @()
    foreach ($tagId in @($Task.Tags)) {
        if ($tagMap.ContainsKey($tagId)) { $tagNames += '#' + $tagMap[$tagId] }
    }
    $tags = if ($tagNames.Count -gt 0) { ($tagNames -join ' ') } else { 'sin etiquetas' }
    $lines = @()
    $lines += ("~gold~$($Task.Text)~/~")
    $lines += ("~gray~{0}  //  prioridad {1}  //  vence {2}  //  {3}~/~" -f $Task.TypeLabel, $Task.PriorityLabel, (Get-HabiticaTaskDueDisplay -Task $Task), $tags)
    if ($Task.ChecklistTotal -gt 0) {
        $lines += ("~gray~Checklist:~/~ ~white~{0}/{1}~/~   ~gray~Racha:~/~ ~white~{2}~/~" -f $Task.ChecklistDone, $Task.ChecklistTotal, $Task.Streak)
    }
    if ($Task.Notes) {
        $note = ConvertFrom-HabiticaMarkdown $Task.Notes
        $lines += ("~gray~" + (Truncate-HabiticaText $note ($Width - 2)) + "~/~")
    }
    return $lines
}

function Get-HabiticaUiTabLines {
    param([int]$Current, [int]$Width)

    $tokens = @()
    for ($i = 0; $i -lt $script:UiTabs.Count; $i++) {
        $number = if ($i -eq 9) { '0' } else { [string]($i + 1) }
        if ($i -eq $Current) {
            $tokens += ("~gold~[{0} {1}]~/~" -f $number, $script:UiTabs[$i].Title)
        }
        else {
            $tokens += ("~gray~ {0} {1} ~/~" -f $number, $script:UiTabs[$i].Title)
        }
    }

    $lines = @()
    $currentLine = ''
    foreach ($token in $tokens) {
        $candidate = if ($currentLine.Length -eq 0) { $token } else { $currentLine + ' ' + $token }
        if ((Get-HabiticaVisibleLength $candidate) -gt $Width - 2 -and $currentLine.Length -gt 0) {
            $lines += (' ' + $currentLine)
            $currentLine = $token
        }
        else {
            $currentLine = $candidate
        }
    }
    if ($currentLine.Length -gt 0) { $lines += (' ' + $currentLine) }
    return $lines
}

function Start-HabiticaUi {
    <#
    .SYNOPSIS
      Abre el panel interactivo de Habitica CLI.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-InteractiveHost)) {
        Write-HabiticaWarn 'El panel interactivo necesita una consola interactiva. Mostrando el dashboard.'
        Show-HabiticaDashboard
        return
    }

    try {
        Assert-HabiticaConfigured
    }
    catch {
        Write-HabiticaBlank
        Write-HabiticaError $_.Exception.Message
        Write-HabiticaInfo 'Ejecuta: h config init'
        return
    }

    Initialize-HabiticaConsole
    Reset-HabiticaUiData

    $width = Get-TerminalWidth
    $height = Get-TerminalHeight
    $currentTab = 0
    $selected = 0
    $scroll = 0
    $chatSelected = 0
    $filter = ''
    $status = ''
    $statusKind = 'info'
    $forceRefresh = $true
    $running = $true
    $lastListSignature = ''
    $originalTitle = $null
    try { $originalTitle = $Host.UI.RawUI.WindowTitle } catch { }

    try {
        Set-HabiticaCursorVisible $false
        Enter-HabiticaUiScreen
        try { $Host.UI.RawUI.WindowTitle = 'Habitica CLI' } catch { }

        while ($running) {
            $width = Get-TerminalWidth
            $height = Get-TerminalHeight
            $tab = $script:UiTabs[$currentTab]
            $tabKey = $tab.Key
            $tabLines = @(Get-HabiticaUiTabLines -Current $currentTab -Width $width)

            # Presupuesto vertical: nunca dibujar mas lineas que la ventana.
            # Se deja una linea libre para que el ultimo salto de linea no
            # provoque scroll en la consola.
            $maxFrameLines = [Math]::Max(10, $height - 2)
            $fixedLines = 8 + $tabLines.Count
            $panelBudget = [Math]::Max(3, $maxFrameLines - $fixedLines)
            $hasDetailPanel = $tabKey -in @('today', 'todo', 'daily', 'habit', 'reward', 'chat', 'challenge', 'skill')
            $reserveDetail = 0
            if ($hasDetailPanel -and $panelBudget -ge 12) { $reserveDetail = 6 }
            $listHeight = [Math]::Max(1, $panelBudget - 2 - $reserveDetail)

            Clear-HabiticaUiScreen

            # ---- Cabecera -------------------------------------------------
            try {
                $stats = Get-HabiticaUiData -Key 'stats' -Force:$forceRefresh
                $hpBar = New-HabiticaProgressBar -Current $stats.HP -Maximum $stats.MaxHP -Width 10 -Color 'red'
                $mpBar = New-HabiticaProgressBar -Current $stats.MP -Maximum $stats.MaxMP -Width 10 -Color 'cyan'
                $xpBar = New-HabiticaProgressBar -Current $stats.XP -Maximum $stats.MaxXP -Width 10 -Color 'gold'
                $headerName = "~gold~H A B I T I C A   C L I~/~  ~gray~v{0}~/~   ~white~{1}~/~  ~gray~LVL~/~ ~gold~{2}~/~  ~cyan~{3}~/~" -f $script:CliVersion, $stats.Name, $stats.Level, $stats.ClassLabel
                $headerStats = "  ~red~HP~/~ {0}  ~cyan~MP~/~ {1}  ~gold~XP~/~ {2}  ~gold~GP~/~ {3}   ~gray~{4}~/~" -f $hpBar, $mpBar, $xpBar, (Format-HabiticaNumber $stats.Gold 2), $(if ($filter) { "filtro: $filter" } else { '' })
                Write-HabiticaLine (Truncate-HabiticaText $headerName $width)
                Write-HabiticaLine (Truncate-HabiticaText $headerStats $width)
            }
            catch {
                Write-HabiticaLine (Truncate-HabiticaText ("~gold~H A B I T I C A   C L I~/~  ~gray~v{0}~/~" -f $script:CliVersion) $width)
                Write-HabiticaLine (Truncate-HabiticaText ("  ~red~Sin conexion:~/~ ~gray~{0}~/~" -f $_.Exception.Message) $width)
            }

            Write-HabiticaLine ("~gray~" + ('-' * ($width - 2)) + "~/~")
            foreach ($tabLine in $tabLines) {
                Write-HabiticaLine $tabLine
            }
            Write-HabiticaLine ("~gray~" + ('-' * ($width - 2)) + "~/~")

            # ---- Contenido ------------------------------------------------
            $tasks = @()
            $skills = @()
            $contentLines = @()
            $detailLines = @()

            try {
                switch ($tabKey) {
                    { $_ -in @('today', 'todo', 'daily', 'habit', 'reward') } {
                        $tasks = @(Get-HabiticaUiData -Key $tabKey -Force:$forceRefresh)
                        if ($filter) {
                            $needle = $filter.ToLowerInvariant()
                            $tasks = @($tasks | Where-Object { $_.Text.ToLowerInvariant().Contains($needle) -or $_.Notes.ToLowerInvariant().Contains($needle) })
                        }

                        $listKey = if ($tabKey -eq 'today') { 'today' } else { ('ui-' + $tabKey) }
                        $signature = '{0}|{1}|{2}' -f $tabKey, $filter, (($tasks | ForEach-Object { $_.Id }) -join ',')
                        if ($signature -ne $lastListSignature) {
                            Set-HabiticaLastList -Key $listKey -Tasks $tasks
                            $lastListSignature = $signature
                        }

                        if ($selected -ge $tasks.Count) { $selected = $tasks.Count - 1 }
                        if ($selected -lt 0) { $selected = 0 }

                        $visible = $listHeight - 1
                        if ($visible -lt 1) { $visible = 1 }
                        if ($selected -lt $scroll) { $scroll = $selected }
                        if ($selected -ge ($scroll + $visible)) { $scroll = $selected - $visible + 1 }
                        $maxScroll = [Math]::Max(0, $tasks.Count - $visible)
                        if ($scroll -gt $maxScroll) { $scroll = $maxScroll }
                        if ($scroll -lt 0) { $scroll = 0 }

                        $visibleTasks = @()
                        if ($tasks.Count -gt 0) {
                            $end = [Math]::Min($tasks.Count - 1, $scroll + $visible - 1)
                            $visibleTasks = @($tasks[$scroll..$end])
                        }

                        $tableLines = Get-HabiticaTaskTableLines -Tasks $visibleTasks -SelectedIndex ($selected - $scroll) -ContentWidth ($width - 4) -StartIndex ($scroll + 1) -MaxRows $visible
                        $contentLines = $tableLines

                        if ($tasks.Count -gt 0) {
                            $detailLines = Get-HabiticaUiTaskDetailShort -Task $tasks[$selected] -Width ($width - 4)
                        }
                    }

                    'party' {
                        $party = Get-HabiticaUiData -Key 'party' -Force:$forceRefresh
                        if (-not $party) {
                            $contentLines = @('~gray~No perteneces a ninguna party.~/~', '', 'Usa ~gold~h party create "Nombre"~/~ o pide una invitacion.')
                        }
                        else {
                            $name = Get-HabiticaPropertyText -Object $party -Name 'name' -Default 'Mi party'
                            $members = @(Get-HabiticaUiData -Key 'partymembers' -Force:$forceRefresh)
                            $contentLines = @()
                            $contentLines += ("~gold~$name~/~   ~gray~miembros:~/~ ~white~{0}~/~" -f $members.Count)
                            $contentLines += ''
                            $contentLines += '~gray~  #  NIVEL  CLASE       NOMBRE                     HP~/~'
                            $index = 0
                            foreach ($member in $members) {
                                $index++
                                $hpColor = 'green'
                                if ([double]$member.MaxHP -gt 0 -and ([double]$member.HP / [double]$member.MaxHP) -le 0.35) { $hpColor = 'red' }
                                $bar = New-HabiticaProgressBar -Current $member.HP -Maximum $member.MaxHP -Width 10 -Color $hpColor
                                $contentLines += ("~gray~{0,3}~/~  ~white~{1,5}~/~  ~cyan~{2,-10}~/~  ~white~{3,-24}~/~  {4}" -f $index, $member.Level, $member.ClassLabel, (Truncate-HabiticaText $member.Name 24), $bar)
                            }
                            $quest = Get-HabiticaUiData -Key 'quest' -Force:$forceRefresh
                            if ($quest -and $quest.Key) {
                                $activeText = if ($quest.Active) { 'si' } else { 'no' }
                                $contentLines += ''
                                $contentLines += ("~gold~Quest:~/~ ~white~{0}~/~   ~gray~activa:~/~ {1}" -f $quest.Name, $activeText)
                            }
                        }
                    }

                    'chat' {
                        $messages = @(Get-HabiticaUiData -Key 'chat' -Force:$forceRefresh)
                        if ($messages.Count -eq 0) {
                            $contentLines = @('~gray~No hay mensajes en el chat.~/~', '', 'Pulsa ~gold~m~/~ para escribir el primero.')
                        }
                        else {
                            if ($chatSelected -ge $messages.Count) { $chatSelected = $messages.Count - 1 }
                            if ($chatSelected -lt 0) { $chatSelected = 0 }

                            $visible = $listHeight - 1
                            if ($visible -lt 1) { $visible = 1 }
                            $chatStart = [Math]::Max(0, $messages.Count - $visible)
                            if ($chatSelected -lt $chatStart) { $chatStart = $chatSelected }
                            if ($chatSelected -ge ($chatStart + $visible)) { $chatStart = $chatSelected - $visible + 1 }
                            $chatStart = [Math]::Max(0, $chatStart)

                            $contentLines = @()
                            for ($i = $chatStart; $i -lt $messages.Count; $i++) {
                                $message = $messages[$i]
                                $selectedMark = if ($i -eq $chatSelected) { '~gold~>~/~' } else { ' ' }
                                $time = Format-HabiticaTimestamp -Timestamp $message.Timestamp -WithTime
                                $likes = if ([int]$message.Likes -gt 0) { (' ~gold~+{0}~/~' -f $message.Likes) } else { '' }
                                if ($message.IsSystem) {
                                    $contentLines += ("$selectedMark ~gray~[{0}] {1}~/~" -f $time, (Truncate-HabiticaText $message.Text ($width - 12)))
                                }
                                else {
                                    $contentLines += ("$selectedMark ~gray~[{0}]~/~ ~cyan~{1}~/~{2}  {3}" -f $time, (Truncate-HabiticaText $message.AuthorName 14), $likes, (Truncate-HabiticaText $message.Text ($width - 32)))
                                }
                            }

                            $selectedMessage = $messages[$chatSelected]
                            $detailLines = @(
                                ("~gold~{0}~/~  ~gray~{1}~/~" -f $selectedMessage.AuthorName, (Format-HabiticaTimestamp -Timestamp $selectedMessage.Timestamp -WithTime)),
                                (Truncate-HabiticaText (ConvertFrom-HabiticaMarkdown $selectedMessage.RawText) ($width - 6))
                            )
                        }
                    }

                    'quest' {
                        $quest = Get-HabiticaUiData -Key 'quest' -Force:$forceRefresh
                        if (-not $quest -or -not $quest.Key) {
                            $contentLines = @(
                                '~gray~No hay quest activa ni pendiente.~/~',
                                '',
                                '~gray~Invita una con:~/~ ~gold~h quest invite <clave>~/~',
                                '~gray~o pulsa~/~ ~gold~i~/~ ~gray~para escribir la clave.~/~'
                            )
                        }
                        else {
                            $contentLines = Get-HabiticaQuestLines -Quest $quest -ContentWidth ($width - 4)
                        }
                    }

                    'challenge' {
                        $challenges = @(Get-HabiticaUiData -Key 'challenge' -Force:$forceRefresh)
                        if ($challenges.Count -eq 0) {
                            $contentLines = @('~gray~No hay retos visibles.~/~', '', 'Prueba ~gold~h challenges --search palabra~/~.')
                        }
                        else {
                            if ($selected -ge $challenges.Count) { $selected = $challenges.Count - 1 }
                            if ($selected -lt 0) { $selected = 0 }

                            $visible = $listHeight - 1
                            if ($visible -lt 1) { $visible = 1 }
                            if ($selected -lt $scroll) { $scroll = $selected }
                            if ($selected -ge ($scroll + $visible)) { $scroll = $selected - $visible + 1 }
                            $scroll = [Math]::Max(0, [Math]::Min($scroll, [Math]::Max(0, $challenges.Count - $visible)))

                            $contentLines = @('~gray~  #  RETO                                     PREMIO  MIEMBROS~/~')
                            $end = [Math]::Min($challenges.Count - 1, $scroll + $visible - 1)
                            for ($i = $scroll; $i -le $end; $i++) {
                                $challenge = $challenges[$i]
                                $mark = if ($i -eq $selected) { '~gold~>~/~' } else { ' ' }
                                $contentLines += ("$mark~gray~{0,3}~/~  ~white~{1,-40}~/~  ~gold~{2,6}~/~  ~cyan~{3,8}~/~" -f ($i + 1), (Truncate-HabiticaText $challenge.Name 40), $challenge.Prize, $challenge.MemberCount)
                            }

                            $challenge = $challenges[$selected]
                            $detailLines = @(
                                ("~gold~{0}~/~" -f $challenge.Name),
                                ("~gray~Grupo:~/~ ~white~{0}~/~   ~gray~Premio:~/~ ~gold~{1} gemas~/~   ~gray~Miembros:~/~ ~white~{2}~/~" -f $challenge.GroupName, $challenge.Prize, $challenge.MemberCount)
                            )
                        }
                    }

                    'profile' {
                        $stats = Get-HabiticaUiData -Key 'stats' -Force:$forceRefresh
                        $contentLines = Get-HabiticaStatsPanelLines -Stats $stats -ContentWidth ($width - 4)
                        $contentLines += ''
                        $contentLines += ("~gray~Nombre:~/~ ~white~{0}~/~   ~gray~Clase:~/~ ~cyan~{1}~/~   ~gray~Nivel:~/~ ~gold~{2}~/~" -f $stats.Name, $stats.ClassLabel, $stats.Level)
                        $contentLines += ("~gray~Atributos:~/~ ~white~FUE {0}  INT {1}  PER {2}  CON {3}~/~" -f $stats.Strength, $stats.Intelligence, $stats.Perception, $stats.Constitution)
                        $contentLines += ("~gray~Puntos sin asignar:~/~ ~gold~{0}~/~" -f $stats.Points)
                    }

                    'skill' {
                        $skills = @(Get-HabiticaUiData -Key 'skill' -Force:$forceRefresh)
                        if ($skills.Count -eq 0) {
                            $contentLines = @(
                                '~gray~Tu heroe no tiene clase todavia.~/~',
                                '',
                                '~gray~Elige Guerrero, Picaro, Mago o Sanador en Habitica.~/~',
                                '~gray~Despues vuelve aqui para lanzar sus poderes.~/~'
                            )
                        }
                        else {
                            if ($selected -ge $skills.Count) { $selected = $skills.Count - 1 }
                            if ($selected -lt 0) { $selected = 0 }

                            $visible = $listHeight - 1
                            if ($visible -lt 1) { $visible = 1 }
                            if ($selected -lt $scroll) { $scroll = $selected }
                            if ($selected -ge ($scroll + $visible)) { $scroll = $selected - $visible + 1 }
                            $scroll = [Math]::Max(0, [Math]::Min($scroll, [Math]::Max(0, $skills.Count - $visible)))

                            $contentLines = @('~gray~  #   NIV   PM  PODER                        OBJETIVO         ESTADO~/~')
                            $end = [Math]::Min($skills.Count - 1, $scroll + $visible - 1)
                            for ($i = $scroll; $i -le $end; $i++) {
                                $skill = $skills[$i]
                                $mark = if ($i -eq $selected) { '~gold~>~/~' } else { ' ' }
                                $contentLines += ("$mark~gray~{0,3}~/~  ~white~{1,4}~/~  ~cyan~{2,3}~/~  ~gold~{3,-27}~/~  ~gray~{4,-15}~/~  ~{5}~{6,-8}~/~" -f $skill.Number, $skill.Level, $skill.Cost, $skill.Name, $skill.TargetLabel, $skill.StatusKind, $skill.Status)
                            }

                            $selectedSkill = $skills[$selected]
                            $detailLines = @(
                                ("~gold~{0}~/~   ~gray~{1} PM  //  objetivo: {2}  //  {3}~/~" -f $selectedSkill.Name, (Format-HabiticaNumber $selectedSkill.Cost 0), $selectedSkill.TargetLabel, $selectedSkill.Status),
                                (Truncate-HabiticaText $selectedSkill.Description ($width - 6))
                            )
                        }
                    }
                }
            }
            catch {
                $contentLines = @(("~red~Error:~/~ " + $_.Exception.Message))
            }

            # Ajuste final al presupuesto vertical: recorta lineas sobrantes y
            # evita que un panel crezca mas que la ventana.
            if ($reserveDetail -eq 0) { $detailLines = @() }
            if ($detailLines.Count -gt 4) { $detailLines = @($detailLines[0..3]) }

            if ($contentLines.Count -gt $listHeight) {
                if ($listHeight -le 1) {
                    $contentLines = @($contentLines[0])
                }
                else {
                    $contentLines = @($contentLines[0..($listHeight - 2)])
                    $contentLines += '~gray~...(contenido recortado)~/~'
                }
            }

            $panelTitle = $tab.Title.ToUpperInvariant()
            if ($tasks.Count -gt 0 -and $tabKey -in @('today', 'todo', 'daily', 'habit', 'reward')) {
                $panelTitle = '{0}  ({1})' -f $panelTitle, $tasks.Count
            }
            if ($skills.Count -gt 0 -and $tabKey -eq 'skill') {
                $panelTitle = '{0}  ({1})' -f $panelTitle, $skills.Count
            }

            foreach ($line in (Get-HabiticaPanelLines -Title $panelTitle -Lines $contentLines -Width $width -Color 'cyan')) {
                Write-HabiticaLine $line
            }

            if ($detailLines.Count -gt 0) {
                foreach ($line in (Get-HabiticaPanelLines -Title 'DETALLE' -Lines $detailLines -Width $width -Color 'gold')) {
                    Write-HabiticaLine $line
                }
            }

            # ---- Estado y ayuda ------------------------------------------
            Write-HabiticaLine ("~gray~" + ('-' * ($width - 2)) + "~/~")
            if ($status) {
                $color = if ($statusKind -eq 'error') { 'red' } elseif ($statusKind -eq 'ok') { 'green' } else { 'gray' }
                Write-HabiticaLine ("  ~${color}~" + (Truncate-HabiticaText $status ($width - 4)) + "~/~")
            }
            else {
                Write-HabiticaLine '  ~gray~Listo.~/~'
            }

            $keys = switch ($tabKey) {
                { $_ -in @('today', 'todo', 'daily', 'habit', 'reward') } { 'Flechas mover  Enter completar  b comprar  x deshacer  a add  e editar  d borrar  c checklist  t tags  m top  v detalle  / buscar  r recargar  q salir' }
                'party' { 'Flechas mover  i invitar  l salir  c chat  r recargar  Tab pestanas  q salir' }
                'chat' { 'Flechas mover  m escribir  l like  s marcar leido  r recargar  Tab pestanas  q salir' }
                'quest' { 'a aceptar  n rechazar  s iniciar  b abortar  c cancelar  l salir  i invitar  r recargar  q salir' }
                'challenge' { 'Flechas mover  Enter/v detalle  j unirse  l salir  c crear  r recargar  q salir' }
                'skill' { 'Flechas mover  Enter lanzar  v detalle  p poderes  r recargar  Tab pestanas  q salir' }
                default { 'r recargar  Tab pestanas  ? ayuda  q salir' }
            }
            Write-HabiticaLine ("  ~gray~{0}~/~" -f (Truncate-HabiticaText $keys ($width - 4)))
            Write-HabiticaLine ("  " + (Truncate-HabiticaText '~gray~? ayuda   p poderes   Tab/Shift+Tab pestanas   1-9,0 ir a pestana~/~' ($width - 2))) -NoNewline

            # ---- Entrada --------------------------------------------------
            $key = Read-HabiticaUiKey
            $forceRefresh = $false
            $status = ''
            $statusKind = 'info'

            if ($key.Key -eq [ConsoleKey]::Escape) { $running = $false; break }
            if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { $running = $false; break }

            try {
                switch ($key.Key) {
                    'UpArrow' {
                        if ($tabKey -eq 'chat') { $chatSelected--; if ($chatSelected -lt 0) { $chatSelected = 0 } }
                        elseif ($tabKey -in @('today', 'todo', 'daily', 'habit', 'reward', 'challenge', 'skill')) { $selected--; if ($selected -lt 0) { $selected = 0 } }
                    }
                    'DownArrow' {
                        if ($tabKey -eq 'chat') { $chatSelected++ }
                        elseif ($tabKey -in @('today', 'todo', 'daily', 'habit', 'reward', 'challenge', 'skill')) { $selected++ }
                    }
                    'PageUp' { if ($tabKey -eq 'chat') { $chatSelected -= 5 } else { $selected -= 5 }; if ($selected -lt 0) { $selected = 0 }; if ($chatSelected -lt 0) { $chatSelected = 0 } }
                    'PageDown' { if ($tabKey -eq 'chat') { $chatSelected += 5 } else { $selected += 5 } }
                    'Tab' {
                        if (($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0) { $currentTab-- } else { $currentTab++ }
                        if ($currentTab -lt 0) { $currentTab = $script:UiTabs.Count - 1 }
                        if ($currentTab -ge $script:UiTabs.Count) { $currentTab = 0 }
                        $selected = 0; $scroll = 0; $filter = ''
                        if ($script:UiTabs[$currentTab].Key -eq 'chat') { $chatSelected = 9999 }
                    }
                    'Enter' {
                        if ($tabKey -in @('today', 'todo', 'daily', 'habit', 'reward')) {
                            if ($tasks.Count -gt 0) {
                                $task = $tasks[$selected]
                                if ($task.Type -eq 'reward') {
                                    $status = Set-HabiticaUiTaskScore -Task $task -Direction Down
                                }
                                else {
                                    $status = Set-HabiticaUiTaskScore -Task $task -Direction Up
                                }
                                $statusKind = 'ok'
                            }
                        }
                        elseif ($tabKey -eq 'skill') {
                            if ($skills.Count -gt 0) {
                                $skill = $skills[$selected]
                                $targetValue = ''
                                if ($skill.Target -in @('task', 'user')) {
                                    $prompt = if ($skill.Target -eq 'task') { 'Tarea objetivo (n de la ultima lista, id o texto):' } else { 'Usuario objetivo (uuid):' }
                                    $targetValue = Read-HabiticaUiInput -Prompt $prompt
                                }

                                if ($skill.Target -in @('task', 'user') -and [string]::IsNullOrWhiteSpace($targetValue)) {
                                    $status = 'Lanzamiento cancelado.'
                                }
                                else {
                                    $cast = Invoke-HabiticaSkillCast -Skill $skill.Key -Target $targetValue -Quiet
                                    $status = ("Poder usado: {0} ({1} PM)" -f $cast.Name, (Format-HabiticaNumber $cast.Cost 0))
                                    $statusKind = 'ok'
                                    $script:UiDataCache.Remove('stats')
                                    $script:UiDataCache.Remove('skill')
                                    $forceRefresh = $true
                                }
                            }
                        }
                        elseif ($tabKey -eq 'challenge') {
                            $challenges = @(Get-HabiticaUiData -Key 'challenge')
                            if ($challenges.Count -gt 0) {
                                $challenge = $challenges[$selected]
                                $lines = @("~gold~$($challenge.Name)~/~", '', ("~gray~Grupo:~/~ {0}" -f $challenge.GroupName), ("~gray~Premio:~/~ {0} gemas" -f $challenge.Prize), ("~gray~Miembros:~/~ {0}" -f $challenge.MemberCount), '', ("~gray~ID:~/~ {0}" -f $challenge.Id))
                                if ($challenge.Summary) { $lines += ''; $lines += $challenge.Summary }
                                Show-HabiticaUiOverlay -Title 'RETO' -Lines $lines -Width $width
                            }
                        }
                    }
                    default {
                        $char = [string]$key.KeyChar
                        if ($char -match '^[0-9]$') {
                            $index = if ($char -eq '0') { 9 } else { [int]$char - 1 }
                            if ($index -ge 0 -and $index -lt $script:UiTabs.Count) {
                                $currentTab = $index
                                $selected = 0; $scroll = 0; $filter = ''
                                if ($script:UiTabs[$currentTab].Key -eq 'chat') { $chatSelected = 9999 }
                            }
                        }
                        elseif ($char -eq 'j' -and $tabKey -in @('chat', 'today', 'todo', 'daily', 'habit', 'reward', 'skill')) {
                            if ($tabKey -eq 'chat') { $chatSelected++ }
                            else { $selected++ }
                        }
                        elseif ($char -eq 'k' -and $tabKey -in @('chat', 'today', 'todo', 'daily', 'habit', 'reward', 'skill')) {
                            if ($tabKey -eq 'chat') { $chatSelected--; if ($chatSelected -lt 0) { $chatSelected = 0 } }
                            else { $selected--; if ($selected -lt 0) { $selected = 0 } }
                        }
                        elseif ($char -eq 'r') {
                            Reset-HabiticaUiData
                            $forceRefresh = $true
                            $status = 'Datos recargados.'
                        }
                        elseif ($char -eq '/') {
                            $filter = Read-HabiticaUiInput -Prompt 'Filtrar por texto (vacio = quitar filtro):'
                            $selected = 0; $scroll = 0
                            $status = if ($filter) { "Filtro: $filter" } else { 'Filtro eliminado.' }
                        }
                        elseif ($char -eq '?' -or $char -eq 'h') {
                            Show-HabiticaCliHelp -Topic 'ui'
                            [void](Read-HabiticaUiKey)
                        }
                        elseif ($char -eq 'p') {
                            $skillTab = Get-HabiticaUiTabIndex -Key 'skill'
                            if ($skillTab -ge 0) {
                                $currentTab = $skillTab
                                $selected = 0; $scroll = 0; $filter = ''
                            }
                        }
                        elseif ($tabKey -in @('today', 'todo', 'daily', 'habit', 'reward')) {
                            if ($tasks.Count -eq 0 -and $char -ne 'a') {
                                $status = 'No hay tareas en esta vista.'
                            }
                            else {
                                $task = if ($tasks.Count -gt 0) { $tasks[$selected] } else { $null }
                                switch ($char) {
                                    'a' {
                                        $text = Read-HabiticaUiInput -Prompt 'Texto de la nueva tarea:'
                                        if (-not [string]::IsNullOrWhiteSpace($text)) {
                                            $typeChar = Read-HabiticaUiInput -Prompt 'Tipo [T]area/[D]iaria/[H]abito/[R]ecompensa (Enter=T):'
                                            $params = @{ Text = $text; Type = 'Todo' }
                                            switch ($typeChar.ToLowerInvariant()) {
                                                'd' {
                                                    $params.Type = 'Daily'
                                                    $frequency = Read-HabiticaUiInput -Prompt 'Frecuencia [D]iaria/[S]emanal/[M]ensual/[A]nual (Enter=S):'
                                                    $params.Frequency = switch ($frequency.ToLowerInvariant()) {
                                                        'd' { 'Daily' }
                                                        'm' { 'Monthly' }
                                                        'a' { 'Yearly' }
                                                        default { 'Weekly' }
                                                    }
                                                    if ($params.Frequency -eq 'Weekly') {
                                                        $days = Read-HabiticaUiInput -Prompt 'Dias (lun,mie,vie) (Enter=hoy):'
                                                        if ($days) { $params.RepeatDays = @($days -split ',') }
                                                    }
                                                }
                                                'h' { $params.Type = 'Habit' }
                                                'r' {
                                                    $params.Type = 'Reward'
                                                    $cost = Read-HabiticaUiInput -Prompt 'Coste en oro:'
                                                    $amount = 0.0
                                                    if ([double]::TryParse($cost, [ref]$amount)) { $params.Cost = $amount }
                                                }
                                                default {
                                                    $due = Read-HabiticaUiInput -Prompt 'Vence (hoy, manana, +3d, Enter=sin fecha):'
                                                    if ($due) { $params.DueDate = ConvertTo-HabiticaCliDate $due }
                                                }
                                            }
                                            New-HabiticaTask @params | Out-Null
                                            Reset-HabiticaUiData
                                            $forceRefresh = $true
                                            $status = "Tarea creada: $text"
                                            $statusKind = 'ok'
                                        }
                                    }
                                    'b' {
                                        if ($task -and $task.Type -eq 'reward') {
                                            $status = Set-HabiticaUiTaskScore -Task $task -Direction Down
                                            $statusKind = 'ok'
                                        }
                                        else { $status = 'Solo se pueden comprar recompensas.'; $statusKind = 'error' }
                                    }
                                    'x' {
                                        if ($task) {
                                            $status = Set-HabiticaUiTaskScore -Task $task -Direction Down
                                            $statusKind = 'ok'
                                        }
                                    }
                                    'e' {
                                        if ($task) {
                                            $newText = Read-HabiticaUiInput -Prompt ("Nuevo titulo [{0}]:" -f (Truncate-HabiticaText $task.Text 40))
                                            if (-not [string]::IsNullOrWhiteSpace($newText)) {
                                                Set-HabiticaTask -Id $task.Id -Text $newText | Out-Null
                                                Reset-HabiticaUiData
                                                $forceRefresh = $true
                                                $status = 'Tarea actualizada.'
                                                $statusKind = 'ok'
                                            }
                                        }
                                    }
                                    'd' {
                                        if ($task) {
                                            $answer = Read-HabiticaUiInput -Prompt ("Eliminar '{0}'? [s/N]:" -f (Truncate-HabiticaText $task.Text 40))
                                            if ($answer -match '^(s|si|y|yes)$') {
                                                Remove-HabiticaTask -Id $task.Id -Force | Out-Null
                                                Reset-HabiticaUiData
                                                $forceRefresh = $true
                                                $selected = [Math]::Max(0, $selected - 1)
                                                $status = 'Tarea eliminada.'
                                                $statusKind = 'ok'
                                            }
                                        }
                                    }
                                    'm' {
                                        if ($task) {
                                            Move-HabiticaTask -Id $task.Id -Position 0
                                            Reset-HabiticaUiData
                                            $forceRefresh = $true
                                            $status = 'Tarea movida al principio.'
                                            $statusKind = 'ok'
                                        }
                                    }
                                    'c' {
                                        if ($task) {
                                            $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)
                                            $showChecklist = $true
                                            while ($showChecklist) {
                                                $lines = @()
                                                if ($items.Count -eq 0) { $lines += '~gray~Sin items.~/~' }
                                                else {
                                                    $i = 0
                                                    foreach ($item in $items) {
                                                        $i++
                                                        if ($item.Completed) { $lines += ("  ~green~[x]~/~ ~gray~{0}. {1}~/~" -f $i, $item.Text) }
                                                        else { $lines += ("  ~gray~[ ]~/~ {0}. {1}" -f $i, $item.Text) }
                                                    }
                                                }
                                                $lines += ''
                                                $lines += '~gray~Numero = alternar   a = agregar   d = borrar   Enter = volver~/~'
                                                Clear-HabiticaUiScreen
                                                foreach ($line in (Get-HabiticaPanelLines -Title ("CHECKLIST // {0}" -f $task.Text) -Lines $lines -Width $width -Color 'cyan')) { Write-HabiticaLine $line }
                                                Write-HabiticaLine '  ~gray~Tecla:~/~'
                                                $checkKey = Read-HabiticaUiKey
                                                if ($checkKey.Key -eq [ConsoleKey]::Enter -or $checkKey.Key -eq [ConsoleKey]::Escape) { $showChecklist = $false; break }
                                                $checkChar = [string]$checkKey.KeyChar
                                                if ($checkChar -eq 'a') {
                                                    $itemText = Read-HabiticaUiInput -Prompt 'Texto del item:'
                                                    if ($itemText) {
                                                        Add-HabiticaChecklistItem -TaskId $task.Id -Text $itemText | Out-Null
                                                        $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)
                                                    }
                                                }
                                                elseif ($checkChar -eq 'd') {
                                                    $itemNumber = Read-HabiticaUiInput -Prompt 'Numero de item a borrar:'
                                                    if ($itemNumber -match '^\d+$' -and [int]$itemNumber -ge 1 -and [int]$itemNumber -le $items.Count) {
                                                        Remove-HabiticaChecklistItem -TaskId $task.Id -ItemId $items[[int]$itemNumber - 1].Id | Out-Null
                                                        $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)
                                                    }
                                                }
                                                elseif ($checkChar -match '^[0-9]+$') {
                                                    $itemNumber = [int]$checkChar
                                                    if ($itemNumber -ge 1 -and $itemNumber -le $items.Count) {
                                                        Complete-HabiticaChecklistItem -TaskId $task.Id -ItemId $items[$itemNumber - 1].Id | Out-Null
                                                        $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)
                                                    }
                                                }
                                            }
                                            Reset-HabiticaUiData
                                            $forceRefresh = $true
                                        }
                                    }
                                    't' {
                                        if ($task) {
                                            $tagName = Read-HabiticaUiInput -Prompt 'Etiqueta a asociar (nombre o #, Enter=cancelar):'
                                            if ($tagName) {
                                                $tagId = Resolve-HabiticaTagId -Reference $tagName
                                                Add-HabiticaTaskTag -TaskId $task.Id -TagId $tagId
                                                Reset-HabiticaUiData
                                                $forceRefresh = $true
                                                $status = 'Etiqueta asociada.'
                                                $statusKind = 'ok'
                                            }
                                        }
                                    }
                                    'v' {
                                        if ($task) {
                                            Show-HabiticaUiOverlay -Title 'DETALLE DE LA MISION' -Lines (Get-HabiticaTaskDetailLines -Task $task -ContentWidth ($width - 4)) -Width $width
                                        }
                                    }
                                }
                            }
                        }
                        elseif ($tabKey -eq 'skill') {
                            if ($skills.Count -gt 0 -and $char -eq 'v') {
                                $skill = $skills[$selected]
                                $lines = @(
                                    ("~gold~{0}~/~" -f $skill.Name),
                                    ("~gray~Coste:~/~ ~cyan~{0} PM~/~   ~gray~Nivel:~/~ ~white~{1}~/~   ~gray~Objetivo:~/~ ~white~{2}~/~" -f (Format-HabiticaNumber $skill.Cost 0), $skill.Level, $skill.TargetLabel),
                                    '',
                                    $skill.Description,
                                    '',
                                    ("~gray~Clave:~/~ ~gray~{0}~/~" -f $skill.Key)
                                )
                                Show-HabiticaUiOverlay -Title 'PODER' -Lines $lines -Width $width
                            }
                        }
                        elseif ($tabKey -eq 'party') {
                            switch ($char) {
                                'i' {
                                    $uuid = Read-HabiticaUiInput -Prompt 'UUID del usuario a invitar:'
                                    if ($uuid) {
                                        Send-HabiticaPartyInvite -UserId @($uuid) | Out-Null
                                        Reset-HabiticaUiData
                                        $forceRefresh = $true
                                        $status = 'Invitacion enviada.'
                                        $statusKind = 'ok'
                                    }
                                }
                                'l' {
                                    $answer = Read-HabiticaUiInput -Prompt 'Abandonar la party? [s/N]:'
                                    if ($answer -match '^(s|si|y|yes)$') {
                                        Exit-HabiticaGroup -Force | Out-Null
                                        Reset-HabiticaUiData
                                        $forceRefresh = $true
                                        $status = 'Has abandonado la party.'
                                        $statusKind = 'ok'
                                    }
                                }
                                'c' {
                                    $chatTab = Get-HabiticaUiTabIndex -Key 'chat'
                                    if ($chatTab -ge 0) { $currentTab = $chatTab }
                                    $chatSelected = 0
                                }
                            }
                        }
                        elseif ($tabKey -eq 'chat') {
                            $messages = @(Get-HabiticaUiData -Key 'chat')
                            switch ($char) {
                                'm' {
                                    $text = Read-HabiticaUiInput -Prompt 'Mensaje:'
                                    if ($text) {
                                        Send-HabiticaChatMessage -Message $text | Out-Null
                                        $script:UiDataCache.Remove('chat')
                                        $forceRefresh = $true
                                        $status = 'Mensaje enviado.'
                                        $statusKind = 'ok'
                                    }
                                }
                                'l' {
                                    if ($messages.Count -gt 0) {
                                        Add-HabiticaChatLike -MessageId $messages[$chatSelected].Id
                                        $script:UiDataCache.Remove('chat')
                                        $forceRefresh = $true
                                        $status = 'Me gusta actualizado.'
                                        $statusKind = 'ok'
                                    }
                                }
                                's' {
                                    Set-HabiticaChatSeen | Out-Null
                                    $status = 'Chat marcado como leido.'
                                    $statusKind = 'ok'
                                }
                            }
                        }
                        elseif ($tabKey -eq 'quest') {
                            switch ($char) {
                                'a' { Invoke-HabiticaQuestAction -Action Accept | Out-Null; Reset-HabiticaUiData; $forceRefresh = $true; $status = 'Quest aceptada.'; $statusKind = 'ok' }
                                'n' { Invoke-HabiticaQuestAction -Action Reject | Out-Null; Reset-HabiticaUiData; $forceRefresh = $true; $status = 'Quest rechazada.'; $statusKind = 'ok' }
                                's' { Invoke-HabiticaQuestAction -Action Start | Out-Null; Reset-HabiticaUiData; $forceRefresh = $true; $status = 'Quest iniciada.'; $statusKind = 'ok' }
                                'b' {
                                    $answer = Read-HabiticaUiInput -Prompt 'Abortar la quest activa? [s/N]:'
                                    if ($answer -match '^(s|si|y|yes)$') { Invoke-HabiticaQuestAction -Action Abort | Out-Null; Reset-HabiticaUiData; $forceRefresh = $true; $status = 'Quest abortada.'; $statusKind = 'ok' }
                                }
                                'c' {
                                    $answer = Read-HabiticaUiInput -Prompt 'Cancelar la quest pendiente? [s/N]:'
                                    if ($answer -match '^(s|si|y|yes)$') { Invoke-HabiticaQuestAction -Action Cancel | Out-Null; Reset-HabiticaUiData; $forceRefresh = $true; $status = 'Quest cancelada.'; $statusKind = 'ok' }
                                }
                                'l' {
                                    $answer = Read-HabiticaUiInput -Prompt 'Salir de la quest activa? [s/N]:'
                                    if ($answer -match '^(s|si|y|yes)$') { Invoke-HabiticaQuestAction -Action Leave | Out-Null; Reset-HabiticaUiData; $forceRefresh = $true; $status = 'Has salido de la quest.'; $statusKind = 'ok' }
                                }
                                'i' {
                                    $questKey = Read-HabiticaUiInput -Prompt 'Clave de la quest (ej: goldenknight):'
                                    if ($questKey) {
                                        Invoke-HabiticaQuestAction -Action Invite -QuestKey $questKey | Out-Null
                                        Reset-HabiticaUiData
                                        $forceRefresh = $true
                                        $status = 'Invitacion de quest enviada.'
                                        $statusKind = 'ok'
                                    }
                                }
                            }
                        }
                        elseif ($tabKey -eq 'challenge') {
                            $challenges = @(Get-HabiticaUiData -Key 'challenge')
                            switch ($char) {
                                'j' {
                                    if ($challenges.Count -gt 0) {
                                        Join-HabiticaChallenge -Id $challenges[$selected].Id | Out-Null
                                        $script:UiDataCache.Remove('challenge')
                                        $forceRefresh = $true
                                        $status = 'Te has unido al reto.'
                                        $statusKind = 'ok'
                                    }
                                }
                                'l' {
                                    if ($challenges.Count -gt 0) {
                                        $answer = Read-HabiticaUiInput -Prompt 'Abandonar este reto? [s/N]:'
                                        if ($answer -match '^(s|si|y|yes)$') {
                                            Exit-HabiticaChallenge -Id $challenges[$selected].Id -Force | Out-Null
                                            $script:UiDataCache.Remove('challenge')
                                            $forceRefresh = $true
                                            $status = 'Has abandonado el reto.'
                                            $statusKind = 'ok'
                                        }
                                    }
                                }
                                'c' {
                                    $name = Read-HabiticaUiInput -Prompt 'Nombre del nuevo reto:'
                                    if ($name) {
                                        $prizeText = Read-HabiticaUiInput -Prompt 'Premio en gemas (Enter=0):'
                                        $prize = 0
                                        if ($prizeText -match '^\d+$') { $prize = [int]$prizeText }
                                        $party = Get-HabiticaUiData -Key 'party'
                                        if ($party) {
                                            New-HabiticaChallenge -GroupId ([string](Get-HabiticaObjectValue $party '_id' '')) -Name $name -Prize $prize | Out-Null
                                            $script:UiDataCache.Remove('challenge')
                                            $forceRefresh = $true
                                            $status = 'Reto creado.'
                                            $statusKind = 'ok'
                                        }
                                        else { $status = 'Necesitas una party para crear retos.'; $statusKind = 'error' }
                                    }
                                }
                                'v' {
                                    if ($challenges.Count -gt 0) {
                                        $challenge = $challenges[$selected]
                                        $lines = @("~gold~$($challenge.Name)~/~", '', ("~gray~Grupo:~/~ {0}" -f $challenge.GroupName), ("~gray~Premio:~/~ {0} gemas" -f $challenge.Prize), ("~gray~Miembros:~/~ {0}" -f $challenge.MemberCount), '', $challenge.Summary)
                                        Show-HabiticaUiOverlay -Title 'RETO' -Lines $lines -Width $width
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch {
                $status = $_.Exception.Message
                $statusKind = 'error'
            }

            if ($selected -lt 0) { $selected = 0 }
            if ($selected -gt 5000) { $selected = 5000 }
            if ($chatSelected -lt 0) { $chatSelected = 0 }
        }
    }
    finally {
        $leftAltScreen = [bool]$script:UiAltScreenActive
        Exit-HabiticaUiScreen
        try { Set-HabiticaCursorVisible $true } catch { }
        try {
            if (-not [string]::IsNullOrWhiteSpace($originalTitle)) { $Host.UI.RawUI.WindowTitle = $originalTitle }
            else { $Host.UI.RawUI.WindowTitle = 'PowerShell' }
        }
        catch { }
    }

    if (-not $leftAltScreen) { Clear-HabiticaUiScreen }
    Write-HabiticaBlank
    Write-HabiticaLine '  ~gold~Hasta luego, heroe.~/~'
    Write-HabiticaLine '  ~gray~Tu progreso queda guardado en Habitica.~/~'
    Write-HabiticaBlank
}

