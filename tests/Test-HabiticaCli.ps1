$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$port = 18765
$serverScript = Join-Path $PSScriptRoot 'Mock-HabiticaServer.ps1'
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ('habitica-cli-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempHome -Force | Out-Null

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:Passed++
        Write-Host ("  PASS  {0}" -f $Message) -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host ("  FAIL  {0}" -f $Message) -ForegroundColor Red
    }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    Assert-True -Condition ($Text -match [regex]::Escape($Pattern)) -Message $Message
}

function Get-HostOutput {
    param([scriptblock]$Script)
    return (& $Script 6>&1 2>&1 | Out-String)
}

$server = $null
$imported = $false

try {
    $server = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $serverScript, '-Port', "$port") -PassThru -WindowStyle Hidden

    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect('127.0.0.1', $port)
            $client.Close()
            $ready = $true
            break
        }
        catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $ready) { throw 'El servidor mock no arranco.' }

    $env:HABITICA_USER_ID = 'user-1'
    $env:HABITICA_API_TOKEN = 'test-token'
    $env:HABITICA_CLIENT_ID = 'user-1-habitica-cli'
    $env:HABITICA_BASE_URL = "http://127.0.0.1:$port/api/v3"
    $env:HABITICA_CLI_HOME = $tempHome
    $env:NO_COLOR = '1'
    $env:HABITICA_CLI_NO_COLOR = '1'

    Get-Module habitica-cli | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $root 'habitica-cli.psd1') -Force
    $imported = $true

    Write-Host "`n== API y configuracion ==" -ForegroundColor Cyan
    $status = Invoke-HabiticaApi -Method GET -Path 'status'
    Assert-True ($status.status -eq 'up') 'GET status responde'
    $config = Get-HabiticaConfig
    Assert-True ($config.UserId -eq 'user-1') 'UserId desde el entorno'
    Assert-True ($config.ApiToken -match '\*\*\*\*' -and $config.ApiToken -ne 'test-token') 'Token enmascarado'
    Assert-True (Test-HabiticaConnection -Quiet) 'Test-HabiticaConnection'

    Write-Host "`n== Tareas ==" -ForegroundColor Cyan
    $todos = @(Get-HabiticaTask -Type Todo)
    Assert-True ($todos.Count -eq 3) "Get-HabiticaTask Todo devuelve 3 (obtenido $($todos.Count))"
    Assert-True (@(Get-HabiticaTask -Type Daily).Count -eq 2) 'Get-HabiticaTask Daily devuelve 2'
    Assert-True (@(Get-HabiticaTask -Type Habit).Count -eq 2) 'Get-HabiticaTask Habit devuelve 2'
    Assert-True (@(Get-HabiticaTask -Type Reward).Count -eq 1) 'Get-HabiticaTask Reward devuelve 1'
    Assert-True (@(Get-HabiticaTask -DueToday).Count -ge 1) 'Filtro DueToday devuelve tareas'
    Assert-True (@(Get-HabiticaTask -Search 'leche').Count -eq 1) 'Busqueda por texto'

    $dashboard = Get-HostOutput { Show-HabiticaDashboard }
    Assert-Match $dashboard 'TestHero' 'Dashboard muestra el nombre'
    Assert-Match $dashboard 'Comprar leche' 'Dashboard muestra tarea de hoy'
    Assert-Match $dashboard 'MISIONES DE HOY' 'Dashboard muestra el panel de misiones'
    Assert-True (-not $dashboard.Contains('~/~')) 'Dashboard no filtra markup literal'

    $todoOutput = Get-HostOutput { Show-HabiticaTaskList -Type Todo }
    Assert-Match $todoOutput 'Comprar leche' 'Lista de tareas muestra el texto'
    Assert-Match $todoOutput 'h done <n>' 'Lista de tareas muestra ayuda'

    # h done usa el indice de la ultima lista mostrada.
    $doneOutput = Get-HostOutput { h done 1 }
    Assert-Match $doneOutput 'Comprar leche' 'h done completa la tarea #1'
    $completedTask = Get-HabiticaTask -Id '11111111-1111-1111-1111-111111111111'
    Assert-True ($completedTask.Completed) 'La tarea #1 quedo completada'

    $whichOutput = Get-HostOutput { h which 2 }
    Assert-Match $whichOutput 'Pagar la luz' 'h which muestra la tarea #2'
    Assert-Match $whichOutput '22222222-2222-2222-2222-222222222222' 'h which muestra el id'

    $dryRunOutput = Get-HostOutput { h done 2 --dry-run }
    Assert-Match $dryRunOutput 'Pagar la luz' 'h done --dry-run muestra la tarea sin completarla'
    Assert-True (-not (Get-HabiticaTask -Id '22222222-2222-2222-2222-222222222222').Completed) 'h done --dry-run no modifica la tarea'

    # UUID malo muestra error claro en lugar de coincidir por texto.
    $badIdOutput = Get-HostOutput { h done '00000000-0000-0000-0000-000000000000' }
    Assert-Match $badIdOutput 'No se encontro la tarea con id' 'UUID inexistente da error claro'

    # El orden guardado para 'h list' debe coincidir con el orden agrupado en pantalla.
    $module = Get-Module habitica-cli
    $mixed = @(
        [pscustomobject]@{ Type = 'reward'; Text = 'R1' }
        [pscustomobject]@{ Type = 'habit'; Text = 'H1' }
        [pscustomobject]@{ Type = 'todo'; Text = 'T1' }
        [pscustomobject]@{ Type = 'daily'; Text = 'D1' }
        [pscustomobject]@{ Type = 'todo'; Text = 'T2' }
    )
    $ordered = & $module { param($items) Get-HabiticaTaskDisplayOrder -Tasks $items } $mixed
    $orderedText = (@($ordered | ForEach-Object { $_.Text }) -join ',')
    Assert-True ($orderedText -eq 'T1,T2,D1,H1,R1') "h list guarda el orden agrupado (obtenido $orderedText)"

    # El estado que deja 'h list' debe seguir el mismo orden que la pantalla.
    $null = Get-HostOutput { Show-HabiticaAllTasks }
    $statePath = Join-Path $tempHome 'state.json'
    $savedState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $savedTypes = @($savedState.lists.all.items | ForEach-Object { $_.type })
    $typeOrder = @('todo', 'daily', 'habit', 'reward')
    $lastRank = -1
    $isOrdered = $true
    foreach ($savedType in $savedTypes) {
        $rank = [array]::IndexOf($typeOrder, $savedType)
        if ($rank -lt $lastRank) { $isOrdered = $false; break }
        $lastRank = $rank
    }
    Assert-True ($savedTypes.Count -gt 0) "h list guarda items en el estado (obtenido $($savedTypes.Count))"
    Assert-True $isOrdered "h list persiste el orden agrupado (obtenido $($savedTypes -join ','))"

    # h dailies muestra solo las que tocan hoy; --all incluye las demas.
    $dailiesOutput = Get-HostOutput { h dailies }
    Assert-Match $dailiesOutput 'Ejercicio' 'h dailies muestra la diaria activa'
    Assert-True (-not $dailiesOutput.Contains('Leer 10 paginas')) 'h dailies oculta la diaria que no toca hoy'
    Assert-Match $dailiesOutput 'no toca' 'h dailies avisa de las diarias ocultas'

    $allDailiesOutput = Get-HostOutput { h dailies --all }
    Assert-Match $allDailiesOutput 'Ejercicio' 'h dailies --all muestra la diaria activa'
    Assert-Match $allDailiesOutput 'Leer 10 paginas' 'h dailies --all muestra la diaria inactiva'

    $lsOutput = Get-HostOutput { h ls }
    Assert-True (-not $lsOutput.Contains('Leer 10 paginas')) 'h ls oculta la diaria que no toca hoy'
    Assert-Match $lsOutput 'no toca' 'h ls avisa de las diarias ocultas'

    $lsAllOutput = Get-HostOutput { h ls --all }
    Assert-Match $lsAllOutput 'Leer 10 paginas' 'h ls --all muestra la diaria inactiva'

    # Regresion: el estado debe actualizarse aunque state.json ya exista.
    # (File.Replace con $null fallaba en silencio y dejaba listas viejas.)
    $null = Get-HostOutput { Show-HabiticaTaskList -Type Todo }
    $beforeState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-True ($beforeState.lastKey -eq 'todos') 'El estado guarda la lista todos'
    $null = Get-HostOutput { Show-HabiticaAllTasks }
    $afterState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-True ($afterState.lastKey -eq 'all') 'El estado se actualiza cuando state.json ya existia'
    Assert-True (@($afterState.lists.all.items).Count -gt 0) 'La lista all se guarda cuando state.json ya existia'

    # Azucar de creacion.
    $addOutput = Get-HostOutput { h add "Comprar pan" --due manana --priority alta --tag casa }
    Assert-Match $addOutput 'Tarea creada' 'h add crea una tarea'
    $bread = @(Get-HabiticaTask -Type Todo | Where-Object { $_.Text -eq 'Comprar pan' }) | Select-Object -First 1
    Assert-True ($null -ne $bread) 'La tarea creada existe'
    Assert-True ($bread.Priority -eq 2) 'La prioridad alta se aplica'
    Assert-True ($bread.DueDate -eq (Get-Date).Date.AddDays(1)) 'La fecha manana se aplica'

    $editOutput = Get-HostOutput { h edit $bread.Id --text "Comprar pan integral" --notes "Sin semillas" }
    Assert-Match $editOutput 'Actualizada' 'h edit actualiza la tarea'
    $bread = Get-HabiticaTask -Id $bread.Id
    Assert-True ($bread.Text -eq 'Comprar pan integral') 'El texto editado persiste'
    Assert-True ($bread.Notes -eq 'Sin semillas') 'Las notas editadas persisten'

    $dailyOutput = Get-HostOutput { h add "Caminar" --daily --frequency weekly --days lun,mie,vie }
    Assert-Match $dailyOutput 'Diaria creada' 'h add crea una diaria'
    $walk = @(Get-HabiticaTask -Type Daily | Where-Object { $_.Text -eq 'Caminar' }) | Select-Object -First 1
    Assert-True ($null -ne $walk) 'La diaria existe'
    Assert-True ($walk.Repeat.m -and $walk.Repeat.w -and $walk.Repeat.f) 'Los dias de la diaria se aplican'

    $habitOutput = Get-HostOutput { h add "Estirar" --habit --up }
    Assert-Match $habitOutput 'Habito creado' 'h add crea un habito'
    $rewardOutput = Get-HostOutput { h add "Cafe especial" --reward --cost 15 }
    Assert-Match $rewardOutput 'Recompensa creada' 'h add crea una recompensa'

    $tempAdd = Get-HostOutput { h add "Tarea temporal" --priority facil }
    Assert-Match $tempAdd 'Tarea creada' 'h add crea tarea temporal'
    $temp = @(Get-HabiticaTask -Type Todo | Where-Object { $_.Text -eq 'Tarea temporal' }) | Select-Object -First 1
    $tempDone = Get-HostOutput { h done "Tarea temporal" }
    Assert-Match $tempDone 'Tarea temporal' 'h done acepta texto'
    Assert-True ((Get-HabiticaTask -Id $temp.Id).Completed) 'h done por texto completa'
    $tempUndo = Get-HostOutput { h undo "Tarea temporal" }
    Assert-Match $tempUndo 'Tarea temporal' 'h undo acepta texto'
    Assert-True (-not (Get-HabiticaTask -Id $temp.Id).Completed) 'h undo deshace'
    $moveOutput = Get-HostOutput { h move "Tarea temporal" 0 }
    Assert-Match $moveOutput 'movida' 'h move reordena'
    $reward = @(Get-HabiticaTask -Type Reward | Where-Object { $_.Text -eq 'Cafe especial' }) | Select-Object -First 1
    $buyOutput = Get-HostOutput { h buy $reward.Id }
    Assert-Match $buyOutput 'Cafe especial' 'h buy compra recompensa'

    Write-Host "`n== Checklist y etiquetas ==" -ForegroundColor Cyan
    $checkAdd = Get-HostOutput { h check add $bread.Id "Comprar en la panaderia" }
    Assert-Match $checkAdd 'Checklist' 'h check add agrega un item'
    $checklist = @(Get-HabiticaChecklistItem -TaskId $bread.Id)
    Assert-True ($checklist.Count -eq 1) 'La checklist tiene 1 item'
    $tickOutput = Get-HostOutput { h tick $bread.Id 1 }
    Assert-Match $tickOutput 'Checklist actualizada' 'h tick alterna el item'
    $checklist = @(Get-HabiticaChecklistItem -TaskId $bread.Id)
    Assert-True ($checklist[0].Completed) 'El item quedo completado'
    $checkAdd2 = Get-HostOutput { h check add $bread.Id "Segundo paso" }
    Assert-Match $checkAdd2 'Checklist' 'h check add agrega un segundo item'
    $checkEdit = Get-HostOutput { h check edit $bread.Id 2 "Segundo paso editado" }
    Assert-Match $checkEdit 'Checklist actualizada' 'h check edit actualiza un item'
    $checklist = @(Get-HabiticaChecklistItem -TaskId $bread.Id)
    Assert-True ($checklist[1].Text -eq 'Segundo paso editado') 'El texto del item se edito'
    $checkRemove = Get-HostOutput { h check rm $bread.Id 2 }
    Assert-Match $checkRemove 'eliminado' 'h check rm elimina un item'
    Assert-True (@(Get-HabiticaChecklistItem -TaskId $bread.Id).Count -eq 1) 'Queda 1 item de checklist'

    $tagOutput = Get-HostOutput { h tag add "proyecto" }
    Assert-Match $tagOutput 'Etiqueta creada' 'h tag add crea etiqueta'
    $tag = @(Get-HabiticaTag | Where-Object { $_.Name -eq 'proyecto' }) | Select-Object -First 1
    Assert-True ($null -ne $tag) 'La etiqueta existe'
    $attachOutput = Get-HostOutput { h tag attach $bread.Id "proyecto" }
    Assert-Match $attachOutput 'Etiqueta asociada' 'h tag attach asocia la etiqueta'
    $bread = Get-HabiticaTask -Id $bread.Id
    Assert-True (@($bread.Tags) -contains $tag.Id) 'La tarea contiene la etiqueta'
    $renameOutput = Get-HostOutput { h tag rename "proyecto" "proyecto-2" }
    Assert-Match $renameOutput 'renombrada' 'h tag rename renombra'
    $renamed = @(Get-HabiticaTag | Where-Object { $_.Name -eq 'proyecto-2' }) | Select-Object -First 1
    Assert-True ($null -ne $renamed) 'La etiqueta renombrada existe'
    $detachOutput = Get-HostOutput { h tag detach $bread.Id "proyecto-2" }
    Assert-Match $detachOutput 'quitada' 'h tag detach quita la etiqueta'
    $bread = Get-HabiticaTask -Id $bread.Id
    Assert-True (-not (@($bread.Tags) -contains $renamed.Id)) 'La tarea ya no tiene la etiqueta'
    $tagRemove = Get-HostOutput { h tag rm "proyecto-2" --yes }
    Assert-Match $tagRemove 'eliminada' 'h tag rm elimina la etiqueta'
    Assert-True (@(Get-HabiticaTag | Where-Object { $_.Name -eq 'proyecto-2' }).Count -eq 0) 'La etiqueta fue eliminada'

    Write-Host "`n== Party, chat y quest ==" -ForegroundColor Cyan
    $partyOutput = Get-HostOutput { Show-HabiticaParty }
    Assert-Match $partyOutput 'Test Party' 'Party muestra el nombre'
    Assert-Match $partyOutput 'Luna' 'Party muestra miembros'
    Assert-Match $partyOutput 'El Caballero Dorado' 'Party muestra la quest'

    $chatOutput = Get-HostOutput { Show-HabiticaChat }
    Assert-Match $chatOutput 'Hola party!' 'Chat muestra mensajes'
    $sendOutput = Get-HostOutput { h chat "Mensaje de prueba" }
    Assert-Match $sendOutput 'Mensaje enviado' 'h chat envia mensaje'
    $chat = @(Get-HabiticaChat)
    Assert-True (@($chat | Where-Object { $_.RawText -eq 'Mensaje de prueba' }).Count -eq 1) 'El mensaje aparece en el chat'
    $likeOutput = Get-HostOutput { h chat like 1 }
    Assert-Match $likeOutput 'Me gusta' 'h chat like funciona'
    $seenOutput = Get-HostOutput { h chat seen }
    Assert-Match $seenOutput 'marcado como leido' 'h chat seen funciona'
    $chatBefore = @(Get-HabiticaChat).Count
    $chatRemove = Get-HostOutput { h chat rm 1 --yes }
    Assert-Match $chatRemove 'Mensaje eliminado' 'h chat rm elimina un mensaje'
    Assert-True (@(Get-HabiticaChat).Count -eq ($chatBefore - 1)) 'El chat tiene un mensaje menos'

    $questOutput = Get-HostOutput { Show-HabiticaQuest }
    Assert-Match $questOutput 'El Caballero Dorado' 'Quest muestra el nombre'
    $questListOutput = Get-HostOutput { Show-HabiticaQuestList }
    Assert-Match $questListOutput 'goldenknight' 'Quest list muestra claves'
    $abortOutput = Get-HostOutput { h quest abort --yes }
    Assert-Match $abortOutput 'abort' 'h quest abort funciona'
    $quest = Get-HabiticaQuest
    Assert-True (-not $quest.Active) 'La quest quedo inactiva'
    $startOutput = Get-HostOutput { h quest start }
    Assert-Match $startOutput 'start' 'h quest start funciona'
    Assert-True ((Get-HabiticaQuest).Active) 'La quest volvio a estar activa'

    Write-Host "`n== Retos ==" -ForegroundColor Cyan
    $challengeOutput = Get-HostOutput { Show-HabiticaChallengeList -Member }
    Assert-Match $challengeOutput 'Reto de lectura' 'Lista de retos muestra resultados'
    $joinOutput = Get-HostOutput { h challenge join 1 }
    Assert-Match $joinOutput 'unido al reto' 'h challenge join funciona'
    $challengeDetail = Get-HostOutput { Show-HabiticaChallengeDetail -Reference 'challenge-1' }
    Assert-Match $challengeDetail 'Un reto de prueba' 'Detalle del reto muestra descripcion'
    $csv = Export-HabiticaChallenge -Id 'challenge-1'
    Assert-True ($csv -match 'name,value') 'Exportar reto devuelve CSV'
    $membersOutput = Get-HostOutput { h challenge members 1 }
    Assert-Match $membersOutput 'Luna' 'Participantes del reto'
    $cloneOutput = Get-HostOutput { h challenge clone 1 }
    Assert-Match $cloneOutput 'clonado' 'h challenge clone funciona'
    $challengeLeave = Get-HostOutput { h challenge leave 1 --yes }
    Assert-Match $challengeLeave 'abandonado' 'h challenge leave funciona'

    Write-Host "`n== Buzon y notificaciones ==" -ForegroundColor Cyan
    $inboxOutput = Get-HostOutput { Show-HabiticaInbox }
    Assert-Match $inboxOutput 'Te apuntas a la quest' 'Buzon muestra mensajes'
    $notifyOutput = Get-HostOutput { Show-HabiticaNotifications }
    Assert-Match $notifyOutput 'TEST_NOTIFICATION' 'Notificaciones visibles'
    $notifySee = Get-HostOutput { h notify see }
    Assert-Match $notifySee 'Notificaciones marcadas' 'h notify see funciona'
    $notifyRead = Get-HostOutput { h notify read --all }
    Assert-Match $notifyRead 'Notificaciones marcadas' 'h notify read funciona'
    $inboxSend = Get-HostOutput { h inbox send user-2 "Hola desde el CLI" }
    Assert-Match $inboxSend 'Mensaje privado enviado' 'h inbox send funciona'

    Write-Host "`n== API generica y errores ==" -ForegroundColor Cyan
    $rawTasks = @(Invoke-HabiticaApi -Method GET -Path 'tasks/user' -Query @{ type = 'todos' })
    Assert-True ($rawTasks.Count -ge 1) 'API generica devuelve datos'
    $apiOutput = Get-HostOutput { h api GET status }
    Assert-Match $apiOutput 'up' 'h api imprime JSON'

    $errorCaught = $false
    try { Invoke-HabiticaApi -Method GET -Path 'no-existe' | Out-Null }
    catch { $errorCaught = $true; Assert-Match $_.Exception.Message 'No encontrado' 'Error 404 traducido' }
    Assert-True $errorCaught 'Error 404 lanza excepcion'

    $apiPost = Get-HostOutput { h api POST tasks/user '{"text":"Creada por API","type":"todo"}' }
    Assert-Match $apiPost 'Creada por API' 'h api POST crea una tarea'
    $apiTask = @(Get-HabiticaTask -Type Todo | Where-Object { $_.Text -eq 'Creada por API' }) | Select-Object -First 1
    Assert-True ($null -ne $apiTask) 'La tarea de la API existe'
    $apiTaskDone = Get-HostOutput { h done $apiTask.Id }
    Assert-Match $apiTaskDone 'Creada por API' 'h done completa la tarea de la API'
    $clearOutput = Get-HostOutput { h clear --yes }
    Assert-Match $clearOutput 'eliminados' 'h clear limpia completados'
    Assert-True (@(Get-HabiticaTask -Type Todo | Where-Object { $_.Text -eq 'Creada por API' }).Count -eq 0) 'La tarea completada fue limpiada'

    Write-Host "`n== Ayuda y configuracion ==" -ForegroundColor Cyan
    $helpOutput = Get-HostOutput { h help }
    Assert-Match $helpOutput 'TAREAS' 'Ayuda general'
    Assert-True (-not $helpOutput.Contains('~/~')) 'Ayuda no muestra markup literal'
    $configOutput = Get-HostOutput { h config }
    Assert-Match $configOutput 'CONFIGURACION' 'h config muestra panel'
    Assert-True (-not $configOutput.Contains('test-token')) 'h config no revela el token'

    # Persistencia real del archivo de configuracion (token cifrado con DPAPI).
    Remove-Item Env:HABITICA_USER_ID, Env:HABITICA_API_TOKEN, Env:HABITICA_CLIENT_ID, Env:HABITICA_BASE_URL -ErrorAction SilentlyContinue
    Set-HabiticaConfig -UserId 'user-1' -ApiToken 'persist-token' -ClientId 'user-1-habitica-cli' -BaseUrl "http://127.0.0.1:$port/api/v3" | Out-Null
    Get-Module habitica-cli | Remove-Module -Force
    Import-Module (Join-Path $root 'habitica-cli.psd1') -Force
    $persisted = Get-HabiticaConfig
    Assert-True ($persisted.UserId -eq 'user-1') 'Configuracion persistida: UserId'
    Assert-True ($persisted.ApiToken -match '\*\*\*\*') 'Configuracion persistida: token cifrado y enmascarado'
    Assert-True (Test-HabiticaConnection -Quiet) 'Conexion con credenciales persistidas'


    Write-Host "`n== Resultado ==" -ForegroundColor Cyan
    Write-Host ("  Pruebas superadas: {0}" -f $script:Passed) -ForegroundColor Green
    if ($script:Failed -gt 0) {
        Write-Host ("  Pruebas fallidas: {0}" -f $script:Failed) -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host ("`nERROR FATAL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
finally {
    if ($imported) { Get-Module habitica-cli | Remove-Module -Force -ErrorAction SilentlyContinue }
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:HABITICA_USER_ID -ErrorAction SilentlyContinue
    Remove-Item Env:HABITICA_API_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:HABITICA_CLIENT_ID -ErrorAction SilentlyContinue
    Remove-Item Env:HABITICA_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:HABITICA_CLI_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
    Remove-Item Env:HABITICA_CLI_NO_COLOR -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
