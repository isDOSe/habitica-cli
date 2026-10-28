# =============================================================================
#  Habitica CLI - Interprete de comandos y ayuda
# =============================================================================

$script:CliVersion = '1.2.0'

$script:BooleanOptions = @(
    'todo', 'daily', 'habit', 'reward', 'yes', 'force', 'read', 'see', 'all',
    'dry-run', 'dryrun', 'mine', 'member', 'owned', 'refresh', 'json', 'no-color', 'include-completed',
    'up', 'down', 'both', 'clear-due', 'completed', 'reopen', 'help', 'version',
    'no-names', 'compact', 'full', 'quiet', 'status'
)

function ConvertTo-HabiticaCliArguments {
    param([AllowNull()][string[]]$Tokens)

    $positionals = New-Object System.Collections.ArrayList
    $options = @{}
    if ($null -eq $Tokens) { return [pscustomobject]@{ Positionals = @(); Options = $options } }

    $i = 0
    $literal = $false
    while ($i -lt $Tokens.Count) {
        $token = [string]$Tokens[$i]

        if ($literal) {
            [void]$positionals.Add($token)
            $i++
            continue
        }
        if ($token -eq '--') { $literal = $true; $i++; continue }

        $name = $null
        $inlineValue = $null
        $hasInlineValue = $false

        if ($token -match '^--([A-Za-z0-9_-]+)(?:=(.*))?$') {
            $name = $matches[1].ToLowerInvariant()
            if ($matches.Count -gt 2 -and $null -ne $matches[2]) { $inlineValue = $matches[2]; $hasInlineValue = $true }
        }
        elseif ($token -match '^-([A-Za-z])(?:=(.*))?$') {
            $short = $matches[1].ToLowerInvariant()
            $shortMap = @{ 'p' = 'priority'; 'n' = 'notes'; 'd' = 'due'; 'y' = 'yes'; 'f' = 'force'; 'm' = 'max'; 't' = 'type' }
            if ($shortMap.ContainsKey($short)) { $name = $shortMap[$short] }
            if ($matches.Count -gt 2 -and $null -ne $matches[2]) { $inlineValue = $matches[2]; $hasInlineValue = $true }
        }

        if ($name) {
            $value = $true
            if ($hasInlineValue) { $value = $inlineValue }
            elseif ($script:BooleanOptions -contains $name) { $value = $true }
            elseif ($i + 1 -lt $Tokens.Count -and -not ([string]$Tokens[$i + 1]).StartsWith('-')) {
                $value = [string]$Tokens[$i + 1]
                $i++
            }

            if ($options.ContainsKey($name)) {
                $existing = @($options[$name])
                $options[$name] = @($existing + $value)
            }
            else {
                $options[$name] = $value
            }
            $i++
            continue
        }

        [void]$positionals.Add($token)
        $i++
    }

    return [pscustomobject]@{
        Positionals = @($positionals.ToArray())
        Options     = $options
    }
}

function Get-HabiticaCliOption {
    param(
        [AllowNull()][hashtable]$Options,
        [string[]]$Names,
        $Default = $null
    )

    if ($null -eq $Options) { return $Default }
    foreach ($name in $Names) {
        if ($Options.ContainsKey($name)) {
            $value = $Options[$name]
            if ($value -is [System.Array]) {
                if ($value.Count -eq 0) { return $Default }
                return $value[$value.Count - 1]
            }
            return $value
        }
    }
    return $Default
}

function Get-HabiticaCliOptionArray {
    param(
        [AllowNull()][hashtable]$Options,
        [string[]]$Names
    )

    $values = @()
    if ($null -eq $Options) { return @() }
    foreach ($name in $Names) {
        if ($Options.ContainsKey($name)) {
            foreach ($value in @($Options[$name])) {
                foreach ($piece in ([string]$value -split ',')) {
                    if (-not [string]::IsNullOrWhiteSpace($piece)) { $values += $piece.Trim() }
                }
            }
        }
    }
    return $values
}

function Test-HabiticaCliFlag {
    param(
        [AllowNull()][hashtable]$Options,
        [string[]]$Names
    )

    if ($null -eq $Options) { return $false }
    foreach ($name in $Names) {
        if ($Options.ContainsKey($name)) { return $true }
    }
    return $false
}

function ConvertTo-HabiticaCliDate {
    param([Parameter(Mandatory)][string]$Text)

    $value = $Text.Trim().ToLowerInvariant()
    $today = (Get-Date).Date

    switch ($value) {
        'hoy' { return $today }
        'today' { return $today }
        'manana' { return $today.AddDays(1) }
        'tomorrow' { return $today.AddDays(1) }
        'ayer' { return $today.AddDays(-1) }
        'yesterday' { return $today.AddDays(-1) }
        'lunes' { return $today.AddDays((8 - [int]$today.DayOfWeek) % 7) }
        'martes' { return $today.AddDays((9 - [int]$today.DayOfWeek) % 7) }
        'miercoles' { return $today.AddDays((10 - [int]$today.DayOfWeek) % 7) }
        'jueves' { return $today.AddDays((11 - [int]$today.DayOfWeek) % 7) }
        'viernes' { return $today.AddDays((12 - [int]$today.DayOfWeek) % 7) }
        'sabado' { return $today.AddDays((13 - [int]$today.DayOfWeek) % 7) }
        'domingo' { return $today.AddDays((14 - [int]$today.DayOfWeek) % 7) }
    }

    if ($value -match '^\+([0-9]+)d$') { return $today.AddDays([int]$matches[1]) }
    if ($value -match '^\+([0-9]+)w$') { return $today.AddDays(7 * [int]$matches[1]) }
    if ($value -match '^\+([0-9]+)m$') { return $today.AddMonths([int]$matches[1]) }

    $parsed = [datetime]::MinValue
    foreach ($format in @('yyyy-MM-dd', 'dd/MM/yyyy', 'dd-MM-yyyy', 'dd/MM', 'dd-MM')) {
        if ([datetime]::TryParseExact($value, $format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            if ($format -eq 'dd/MM' -or $format -eq 'dd-MM') {
                return (New-Object datetime($today.Year, $parsed.Month, $parsed.Day))
            }
            return $parsed.Date
        }
    }

    if ([datetime]::TryParse($value, [ref]$parsed)) { return $parsed.Date }
    throw ("Fecha no valida: '{0}'. Usa hoy, manana, +3d, 2026-12-31 o 31/12." -f $Text)
}

function ConvertTo-HabiticaCliPriority {
    param([Parameter(Mandatory)][string]$Text)

    $value = $Text.Trim().ToLowerInvariant()
    switch ($value) {
        'trivial' { return 'Trivial' }
        '0.1' { return 'Trivial' }
        'facil' { return 'Facil' }
        'easy' { return 'Facil' }
        '1' { return 'Facil' }
        'media' { return 'Media' }
        'medio' { return 'Media' }
        'medium' { return 'Media' }
        '1.5' { return 'Media' }
        'dificil' { return 'Dificil' }
        'hard' { return 'Dificil' }
        '2' { return 'Dificil' }
        'baja' { return 'Facil' }
        'alta' { return 'Dificil' }
        default { throw ("Prioridad no valida: '{0}'. Usa trivial, facil, media o dificil." -f $Text) }
    }
}

function Get-HabiticaCliTaskType {
    param([AllowNull()][hashtable]$Options, [string[]]$Positionals)

    $typeOption = Get-HabiticaCliOption -Options $Options -Names @('type')
    if ($typeOption) {
        switch (([string]$typeOption).ToLowerInvariant()) {
            'todo' { return 'Todo' }
            'tarea' { return 'Todo' }
            'daily' { return 'Daily' }
            'diaria' { return 'Daily' }
            'habit' { return 'Habit' }
            'habito' { return 'Habit' }
            'reward' { return 'Reward' }
            'recompensa' { return 'Reward' }
            default { throw ("Tipo no valido: '{0}'." -f $typeOption) }
        }
    }

    if (Test-HabiticaCliFlag $Options @('daily')) { return 'Daily' }
    if (Test-HabiticaCliFlag $Options @('habit')) { return 'Habit' }
    if (Test-HabiticaCliFlag $Options @('reward')) { return 'Reward' }
    return 'Todo'
}

function Get-HabiticaCliTaskFromPositionals {
    param(
        [AllowNull()][string[]]$Positionals,
        [int]$MinimumIndex = 1
    )

    if ($null -eq $Positionals -or $Positionals.Count -le $MinimumIndex) { return '' }
    $start = $MinimumIndex
    return (($Positionals[$start..($Positionals.Count - 1)]) -join ' ').Trim()
}

function ConvertTo-HabiticaTaskReferenceList {
    <#
    .SYNOPSIS
      Convierte los argumentos de un comando en una lista de referencias.

    .DESCRIPTION
      Acepta indices y UUID separados por comas o por espacios, por ejemplo
      '1,2,3', '1 2 3' o 'uuid1,uuid2'. Si el texto no es una lista de
      indices/UUID se devuelve como una sola referencia para no romper las
      busquedas por titulo con espacios o comas.
    #>
    param(
        [AllowNull()][string[]]$Positionals,
        [int]$MinimumIndex = 0
    )

    if ($null -eq $Positionals -or $Positionals.Count -le $MinimumIndex) { return @() }

    $tokens = @($Positionals[$MinimumIndex..($Positionals.Count - 1)])
    $simplePattern = '^(\d+|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$'

    $pieces = @()
    foreach ($token in $tokens) {
        foreach ($piece in ([string]$token -split ',')) {
            $trimmed = $piece.Trim()
            if ($trimmed) { $pieces += $trimmed }
        }
    }

    if ($pieces.Count -eq 0) { return @() }

    $isSimpleList = -not @($pieces | Where-Object { $_ -notmatch $simplePattern }).Count
    if (-not $isSimpleList) {
        # Texto libre: se conserva tal cual como una unica referencia.
        return @(($tokens -join ' ').Trim())
    }

    $references = @()
    foreach ($piece in $pieces) {
        if ($references -notcontains $piece) { $references += $piece }
    }
    return $references
}

function Show-HabiticaCliHelp {
    <#
    .SYNOPSIS
      Ayuda del cliente de Habitica.
    #>
    [CmdletBinding()]
    param([string]$Topic = '')

    $width = Get-TerminalWidth
    $topicKey = $Topic.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($topicKey)) {
        $lines = @(
            '~gray~USO~/~',
            '  ~gold~h~/~                          Panel de hoy',
            '  ~gold~h <comando> [opciones]~/~     Ejecuta una accion',
            '  ~gold~h <comando> --help~/~         Ayuda del comando',
            '',
            '~gray~TAREAS~/~',
            '  ~gold~h ls~/~                       Todas las tareas (diarias activas)',
            '  ~gold~h ls --all~/~                 Incluye diarias inactivas',
            '  ~gold~h todo~/~                     Tareas pendientes',
            '  ~gold~h dailies~/~                  Diarias activas hoy',
            '  ~gold~h dailies --all~/~            Todas las diarias',
            '  ~gold~h habits~/~                   Habitos',
            '  ~gold~h rewards~/~                  Recompensas',
            '  ~gold~h add "texto"~/~              Crear tarea',
            '  ~gold~h done <n|id|texto>~/~        Completar',
            '  ~gold~h done 1,2,3~/~               Completar varias a la vez',
            '  ~gold~h done <n> --dry-run~/~       Ver cual se completaria',
            '  ~gold~h which <n|id|texto>~/~       Ver a que tarea apunta',
            '  ~gold~h undo <n>~/~                 Deshacer',
            '  ~gold~h show <n>~/~                 Detalle',
            '  ~gold~h edit <n> --text "..."~/~    Editar',
            '  ~gold~h tick <n> <item>~/~          Marcar checklist',
            '  ~gold~h rm <n> --yes~/~             Eliminar',
            '',
            '~gray~SOCIAL~/~',
            '  ~gold~h party~/~                    Tu party y miembros',
            '  ~gold~h chat~/~                     Chat de la party',
            '  ~gold~h chat "mensaje"~/~           Enviar mensaje',
            '  ~gold~h quest~/~                    Estado de la quest',
            '  ~gold~h challenges~/~               Retos',
            '  ~gold~h inbox~/~                    Mensajes privados',
            '',
            '~gray~CUENTA~/~',
            '  ~gold~h stats~/~                    Estadisticas',
            '  ~gold~h profile~/~                  Ficha del heroe',
            '  ~gold~h skills~/~                   Poderes de tu clase',
            '  ~gold~h cast <n|clave>~/~           Lanzar un poder',
            '  ~gold~h notify~/~                   Notificaciones',
            '  ~gold~h config~/~                   Configuracion',
            '  ~gold~h api GET tasks/user~/~       Cualquier endpoint de la API',
            '  ~gold~h ui~/~                       Panel interactivo',
            '',
            '~gray~AYUDA~/~   ~gold~h help tasks~/~  ~gold~h help social~/~  ~gold~h help powers~/~  ~gold~h help api~/~'
        )
    }
    elseif ($topicKey -in @('tasks', 'tareas')) {
        $lines = @(
            '~gold~CREAR~/~',
            '  h add "Comprar leche"',
            '  h add "Ejercicio" --daily --frequency weekly --days lun,mie,vie',
            '  h add "Beber agua" --habit --up',
            '  h add "Ver una pelicula" --reward --cost 20',
            '  Opciones: --notes --priority facil|media|dificil --due manana',
            '            --tag casa --tag compras --check "Paso 1" --alias leche',
            '',
            '~gold~LISTAR Y ACCIONAR~/~',
            '  h ls                 Todas, agrupadas (diarias activas hoy)',
            '  h todo               Pendientes',
            '  h dailies            Diarias activas hoy',
            '  h dailies --all      Todas las diarias',
            '  h habits             Habitos',
            '  h rewards            Recompensas',
            '  h show 3             Detalle de la tarea #3',
            '  h done 3             Completar / score up',
            '  h done 1,2,3         Completar varias de golpe',
            '  h done 3 --dry-run   Ver cual se completaria sin tocarla',
            '  h which 3            Ver a que tarea resuelve el 3',
            '  h undo 3             Deshacer / score down',
            '  h up 3               Subir un habito',
            '  h down 3             Bajar un habito',
            '  h buy 2              Comprar una recompensa',
            '  h edit 3 --text "Nuevo titulo" --due +2d',
            '  h move 3 0           Mover al principio',
            '  h rm 3 --yes         Eliminar',
            '  h clear --yes        Borrar To-Dos completados',
            '',
            '~gold~CHECKLIST~/~',
            '  h check 3                    Ver checklist',
            '  h check add 3 "Revisar"      Agregar item',
            '  h tick 3 2                   Alternar item #2',
            '  h check rm 3 2               Eliminar item',
            '',
            '~gray~Los indices <n> corresponden a la ultima lista mostrada.~/~',
            '~gray~Tambien aceptan id, alias o un fragmento unico del texto.~/~'
        )
    }
    elseif ($topicKey -in @('social', 'party', 'chat', 'quest', 'challenges')) {
        $lines = @(
            '~gold~PARTY~/~',
            '  h party                      Ver party, miembros y quest',
            '  h party create "Nombre"      Crear party',
            '  h party invite <uuid>        Invitar',
            '  h party kick <uuid> --yes    Expulsar',
            '  h party leave --yes          Abandonar',
            '  h groups                     Ver todos tus grupos',
            '',
            '~gold~CHAT~/~',
            '  h chat                       Ultimos mensajes',
            '  h chat "Hola party"          Enviar',
            '  h chat like 2                Me gusta al mensaje #2',
            '  h chat rm 2 --yes            Borrar mensaje',
            '  h chat seen                  Marcar como leido',
            '',
            '~gold~QUESTS~/~',
            '  h quest                      Estado actual',
            '  h quest list                 Pergaminos que posees',
            '  h quest invite <clave>       Invitar a una quest',
            '  h quest accept|reject        Responder invitacion',
            '  h quest start                Forzar inicio',
            '  h quest abort|cancel|leave   Abortar, cancelar o salir',
            '',
            '~gold~RETOS~/~',
            '  h challenges                 Retos visibles',
            '  h challenges --mine          En los que participas',
            '  h challenges --owned         Creados por ti',
            '  h challenges --search "x"    Buscar',
            '  h challenge join <n>         Unirse',
            '  h challenge leave <n> --yes  Salir',
            '  h challenge show <n>         Detalle',
            '  h challenge create --name "Reto" --group <id> --prize 5',
            '',
            '~gold~MENSAJES~/~',
            '  h inbox                      Buzon privado',
            '  h inbox send <uuid> "Hola"   Enviar mensaje privado'
        )
    }
    elseif ($topicKey -in @('powers', 'skills', 'poderes', 'spells', 'cast')) {
        $lines = @(
            '~gold~PODERES DE CLASE~/~',
            '  h skills                     Lista poderes, coste, nivel y estado',
            '  h cast 1                     Lanza el poder #1',
            '  h cast 1 --target 3          Sobre la tarea #3 de la ultima lista',
            '  h cast smash 3               Por clave y tarea',
            '  h cast herramientas          Poder de equipo (sin objetivo)',
            '  h cast 1 --times 2           Repite el lanzamiento',
            '',
            '~gold~OBJETIVOS~/~',
            '  tarea      Numero de la ultima lista, id, alias o texto',
            '  equipo     Se aplica a toda la party',
            '  ti         Solo a tu heroe',
            '',
            'Los poderes gastan PM y se desbloquean entre los niveles 11 y 14.',
            'Tambien puedes lanzarlos desde el panel: pestana ~gold~Poderes~/~ o tecla ~gold~p~/~.'
        )
    }
    elseif ($topicKey -in @('api', 'raw')) {
        $lines = @(
            '~gold~API GENERICA~/~',
            '  h api GET tasks/user',
            '  h api GET "user?userFields=stats,profile"',
            '  h api POST tasks/user "{""text"":""Nueva"",""type"":""todo""}"',
            '  h api PUT tasks/<id> "{""notes"":""....""}"',
            '  h api DELETE tasks/<id>',
            '',
            'Metodos: GET, POST, PUT, DELETE.',
            'La ruta es relativa a https://habitica.com/api/v3.',
            'Usa --full para ver la respuesta completa (success/data/message).',
            '',
            '~gray~Documentacion oficial: https://habitica.com/apidoc~/~'
        )
    }
    elseif ($topicKey -in @('ui', 'tui', 'teclas', 'keys')) {
        $lines = @(
            '~gold~PANEL INTERACTIVO~/~   h ui',
            '',
            '  Flechas / j k       Mover seleccion',
            '  Tab / Shift+Tab     Cambiar pestana',
            '  1..9, 0             Ir a pestana',
            '  Enter               Completar tarea / actuar',
            '  Espacio             Completar (score up)',
            '  x                   Deshacer (score down)',
            '  a                   Agregar tarea',
            '  e                   Editar titulo de la seleccionada',
            '  d                   Eliminar (con confirmacion)',
            '  c                   Ver / agregar checklist',
            '  t                   Etiquetas de la tarea',
            '  m                   Mover al principio',
            '  /                   Buscar',
            '  r                   Recargar',
            '  ?                   Ayuda dentro del panel',
            '  q                   Salir',
            '',
            'En Party: ~gold~i~/~ invitar, ~gold~l~/~ salir, ~gold~r~/~ recargar.',
            'En Chat: ~gold~m~/~ escribir, ~gold~l~/~ like, ~gold~s~/~ marcar leido.',
            'En Quest: ~gold~a~/~ aceptar, ~gold~s~/~ iniciar, ~gold~b~/~ abortar, ~gold~i~/~ invitar.',
            'En Retos: ~gold~j~/~ unirse, ~gold~l~/~ salir, ~gold~Enter~/~ detalle.',
            'En Poderes: ~gold~Enter~/~ lanzar, ~gold~p~/~ ir directo desde cualquier pestana.'
        )
    }
    elseif ($topicKey -in @('config', 'setup', 'inicio')) {
        $lines = @(
            '~gold~CONFIGURACION~/~',
            '  h config init            Asistente de credenciales',
            '  h config                 Ver configuracion (token oculto)',
            '  h config test            Probar conexion',
            '  h config path            Ruta del archivo de configuracion',
            '  h config reset --yes     Borrar credenciales',
            '  h config cache           Borrar cache local',
            '',
            'Variables de entorno (prioridad sobre el archivo):',
            '  HABITICA_USER_ID',
            '  HABITICA_API_TOKEN',
            '  HABITICA_CLIENT_ID',
            '  HABITICA_BASE_URL',
            '  HABITICA_TIMEOUT',
            '',
            'Consigue tus credenciales en Habitica: Ajustes -> API.'
        )
    }
    else {
        Write-HabiticaWarn ("Tema de ayuda desconocido: {0}" -f $Topic)
        Show-HabiticaCliHelp
        return
    }

    Write-HabiticaBlank
    $titleTopic = $Topic.ToUpperInvariant()
    if ($topicKey -in @('powers', 'skills', 'poderes', 'spells', 'cast')) { $titleTopic = 'PODERES' }
    Write-HabiticaPanel -Title ('AYUDA  //  ' + $titleTopic) -Lines $lines -Width $width -Color 'gold'
    Write-HabiticaBlank
}

function Show-HabiticaVersion {
    $width = Get-TerminalWidth
    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaBannerLines -Width $width)) { Write-HabiticaLine $line }
    Write-HabiticaLine ("  ~gray~Habitica CLI v{0}  //  PowerShell {1}~/~" -f $script:CliVersion, $PSVersionTable.PSVersion)
    Write-HabiticaLine ("  ~gray~Cliente no oficial. API v3 de Habitica.~/~")
    Write-HabiticaBlank
}

# -----------------------------------------------------------------------------
#  Acciones de tareas
# -----------------------------------------------------------------------------

function Invoke-HabiticaCliAdd {
    param([hashtable]$Options, [string[]]$Positionals)

    $rawText = (($Positionals -join ' ')).Trim()
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        throw 'Uso: h add "texto de la tarea" [--daily|--habit|--reward] [--due fecha]'
    }

    $tags = @(Get-HabiticaCliOptionArray -Options $Options -Names @('tag', 'tags'))
    $checks = @(Get-HabiticaCliOptionArray -Options $Options -Names @('check', 'checklist'))

    # Azucar: #etiqueta y !prioridad dentro del texto.
    $words = @($rawText -split '\s+')
    $cleanWords = @()
    foreach ($word in $words) {
        if ($word -match '^#(.+)$') { $tags += $matches[1]; continue }
        if ($word -match '^!(asc|alta|high|hard|!!!)$') { $Options['priority'] = 'dificil'; continue }
        if ($word -match '^!!$') { $Options['priority'] = 'media'; continue }
        if ($word -match '^!$') { $Options['priority'] = 'facil'; continue }
        if ($word -match '^due:(.+)$') { $Options['due'] = $matches[1]; continue }
        $cleanWords += $word
    }
    $text = ($cleanWords -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { $text = $rawText }

    $type = Get-HabiticaCliTaskType -Options $Options
    $params = @{
        Type = $type
        Text = $text
    }

    $notes = Get-HabiticaCliOption -Options $Options -Names @('notes', 'note')
    if ($notes) { $params.Notes = [string]$notes }

    $priority = Get-HabiticaCliOption -Options $Options -Names @('priority')
    if ($priority) { $params.Priority = ConvertTo-HabiticaCliPriority ([string]$priority) }

    $attribute = Get-HabiticaCliOption -Options $Options -Names @('attribute', 'attr')
    if ($attribute) {
        $attr = ([string]$attribute).ToLowerInvariant()
        if ($attr -notin @('str', 'int', 'per', 'con')) { throw 'Atributo no valido. Usa str, int, per o con.' }
        $params.Attribute = $attr.Substring(0, 1).ToUpperInvariant() + $attr.Substring(1)
    }

    if ($tags.Count -gt 0) { $params.Tag = $tags }
    $alias = Get-HabiticaCliOption -Options $Options -Names @('alias')
    if ($alias) { $params.Alias = [string]$alias }

    $due = Get-HabiticaCliOption -Options $Options -Names @('due', 'date')
    if ($due) { $params.DueDate = ConvertTo-HabiticaCliDate ([string]$due) }

    $frequency = Get-HabiticaCliOption -Options $Options -Names @('frequency', 'freq')
    $days = @(Get-HabiticaCliOptionArray -Options $Options -Names @('days', 'repeat') | ForEach-Object { [regex]::Split([string]$_, '[,\s]+') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($frequency) {
        $freq = ([string]$frequency).ToLowerInvariant()
        switch ($freq) {
            'diaria' { $params.Frequency = 'Daily' }
            'daily' { $params.Frequency = 'Daily' }
            'semanal' { $params.Frequency = 'Weekly' }
            'weekly' { $params.Frequency = 'Weekly' }
            'mensual' { $params.Frequency = 'Monthly' }
            'monthly' { $params.Frequency = 'Monthly' }
            'anual' { $params.Frequency = 'Yearly' }
            'yearly' { $params.Frequency = 'Yearly' }
            default { throw 'Frecuencia no valida: daily, weekly, monthly o yearly.' }
        }
    }
    elseif ($days.Count -gt 0) {
        $params.Frequency = 'Weekly'
    }
    if ($days.Count -gt 0) { $params.RepeatDays = $days }

    $every = Get-HabiticaCliOption -Options $Options -Names @('every', 'everyx')
    if ($every) {
        $number = 0
        if (-not [int]::TryParse([string]$every, [ref]$number)) { throw '--every debe ser un numero entero.' }
        $params.EveryX = $number
    }

    $start = Get-HabiticaCliOption -Options $Options -Names @('start', 'start-date')
    if ($start) { $params.StartDate = ConvertTo-HabiticaCliDate ([string]$start) }

    $cost = Get-HabiticaCliOption -Options $Options -Names @('cost', 'value')
    if ($cost) {
        $amount = 0.0
        if (-not [double]::TryParse([string]$cost, [ref]$amount)) { throw '--cost debe ser un numero.' }
        $params.Cost = $amount
    }

    if ($checks.Count -gt 0) { $params.Checklist = $checks }
    if (Test-HabiticaCliFlag $Options @('up')) { $params.Up = $true }
    if (Test-HabiticaCliFlag $Options @('down')) { $params.Down = $true }

    New-HabiticaTask @params | Out-Null
}

function Invoke-HabiticaCliEdit {
    param([hashtable]$Options, [string[]]$Positionals)

    if ($Positionals.Count -lt 1) { throw 'Uso: h edit <n|id|texto> [--text "..."] [--notes "..."] [--due fecha]' }
    $reference = [string]$Positionals[0]
    $task = Resolve-HabiticaTaskReference -Reference $reference

    $params = @{ Id = $task.Id }
    $text = Get-HabiticaCliOption -Options $Options -Names @('text')
    if (-not $text -and $Positionals.Count -ge 2) { $text = (($Positionals[1..($Positionals.Count - 1)]) -join ' ') }
    if ($text) { $params.Text = [string]$text }

    $notes = Get-HabiticaCliOption -Options $Options -Names @('notes', 'note')
    if ($notes) { $params.Notes = [string]$notes }

    $priority = Get-HabiticaCliOption -Options $Options -Names @('priority')
    if ($priority) { $params.Priority = ConvertTo-HabiticaCliPriority ([string]$priority) }

    $attribute = Get-HabiticaCliOption -Options $Options -Names @('attribute', 'attr')
    if ($attribute) {
        $attr = ([string]$attribute).ToLowerInvariant()
        if ($attr -notin @('str', 'int', 'per', 'con')) { throw 'Atributo no valido. Usa str, int, per o con.' }
        $params.Attribute = $attr.Substring(0, 1).ToUpperInvariant() + $attr.Substring(1)
    }

    $due = Get-HabiticaCliOption -Options $Options -Names @('due', 'date')
    if ($due) {
        if ($task.Type -eq 'Daily') { $params.StartDate = ConvertTo-HabiticaCliDate ([string]$due) }
        else { $params.DueDate = ConvertTo-HabiticaCliDate ([string]$due) }
    }
    if (Test-HabiticaCliFlag $Options @('clear-due')) { $params.ClearDueDate = $true }
    if (Test-HabiticaCliFlag $Options @('completed')) { $params.Completed = $true }
    if (Test-HabiticaCliFlag $Options @('reopen')) { $params.Reopen = $true }

    $cost = Get-HabiticaCliOption -Options $Options -Names @('cost', 'value')
    if ($cost) {
        $amount = 0.0
        if (-not [double]::TryParse([string]$cost, [ref]$amount)) { throw '--cost debe ser un numero.' }
        $params.Cost = $amount
    }

    $frequency = Get-HabiticaCliOption -Options $Options -Names @('frequency', 'freq')
    if ($frequency) {
        $params.Frequency = ([string]$frequency).Substring(0, 1).ToUpperInvariant() + ([string]$frequency).Substring(1).ToLowerInvariant()
    }
    $every = Get-HabiticaCliOption -Options $Options -Names @('every', 'everyx')
    if ($every) {
        $number = 0
        if (-not [int]::TryParse([string]$every, [ref]$number)) { throw '--every debe ser un numero entero.' }
        $params.EveryX = $number
    }
    $days = @(Get-HabiticaCliOptionArray -Options $Options -Names @('days', 'repeat') | ForEach-Object { [regex]::Split([string]$_, '[,\s]+') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($days.Count -gt 0) { $params.RepeatDays = $days }
    $start = Get-HabiticaCliOption -Options $Options -Names @('start', 'start-date')
    if ($start) { $params.StartDate = ConvertTo-HabiticaCliDate ([string]$start) }
    if (Test-HabiticaCliFlag $Options @('up')) { $params.Up = $true }
    if (Test-HabiticaCliFlag $Options @('down')) { $params.Down = $true }

    Set-HabiticaTask @params | Out-Null
}

function Invoke-HabiticaCliScore {
    param(
        [hashtable]$Options,
        [string[]]$Positionals,
        [ValidateSet('Up', 'Down')][string]$Direction
    )

    $references = @(ConvertTo-HabiticaTaskReferenceList -Positionals $Positionals)
    if ($references.Count -eq 0) { throw 'Uso: h done <n|id|texto> [n2,n3...]' }

    $dryRun = Test-HabiticaCliFlag $Options @('dry-run', 'dryrun', 'see')
    $failures = @()

    foreach ($reference in $references) {
        try {
            $task = Resolve-HabiticaTaskReference -Reference $reference

            if ($Direction -eq 'Up' -and $task.Type -eq 'reward') {
                throw ("'{0}' es una recompensa. Usa 'h buy {1}'." -f $task.Text, $reference)
            }

            if ($dryRun) {
                Write-HabiticaBlank
                Write-HabiticaLine ("  ~gray~[simulacion]~/~ ~cyan~{0}~/~  ~white~{1}~/~" -f $task.TypeLabel, $task.Text)
                Write-HabiticaLine ("           ~gray~ID:~/~ ~gray~{0}~/~" -f $task.Id)
                Write-HabiticaBlank
                continue
            }

            Invoke-HabiticaTaskScore -Id $task.Id -Direction $Direction -Text $task.Text | Out-Null
        }
        catch {
            # Con una sola referencia el error se propaga como siempre.
            if ($references.Count -eq 1) { throw }
            $failures += [pscustomobject]@{ Reference = $reference; Message = $_.Exception.Message }
        }
    }

    if ($failures.Count -gt 0) {
        $width = Get-TerminalWidth
        $messageWidth = [Math]::Max(20, $width - 12)
        $lines = @($failures | ForEach-Object {
            ("~red~{0}~/~  ~gray~{1}~/~" -f $_.Reference, (Truncate-HabiticaText -Text $_.Message -Width $messageWidth))
        })
        Write-HabiticaBlank
        Write-HabiticaPanel -Title 'NO SE PUDIERON PROCESAR' -Lines $lines -Width $width -Color 'red'
        Write-HabiticaBlank
    }
}

function Invoke-HabiticaCliWhich {
    param([string[]]$Positionals)

    if ($Positionals.Count -lt 1) { throw 'Uso: h which <n|id|texto>' }
    $task = Resolve-HabiticaTaskReference -Reference ([string]$Positionals[0])

    $width = Get-TerminalWidth
    $lines = Get-HabiticaTaskDetailLines -Task $task -ContentWidth ($width - 4)
    Write-HabiticaBlank
    foreach ($line in (Get-HabiticaPanelLines -Title 'RESOLUCION DE REFERENCIA' -Lines $lines -Width $width -Color 'cyan')) {
        Write-HabiticaLine $line
    }
    Write-HabiticaBlank
}

function Invoke-HabiticaCliCheck {
    param([hashtable]$Options, [string[]]$Positionals)

    if ($Positionals.Count -lt 1) { throw 'Uso: h check <n> | h check add <n> "texto" | h tick <n> <item>' }
    $task = Resolve-HabiticaTaskReference -Reference ([string]$Positionals[0])
    $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)

    $width = Get-TerminalWidth
    if ($items.Count -eq 0) {
        Write-HabiticaPanel -Title ("CHECKLIST // {0}" -f $task.Text) -Lines @('~gray~Sin items.~/~', '', 'Agrega uno con ~gold~h check add <n> "texto"~/~.') -Width $width -Color 'cyan'
        return
    }

    $lines = @()
    $index = 0
    foreach ($item in $items) {
        $index++
        if ($item.Completed) { $lines += ("  ~green~[x]~/~ ~gray~{0}. {1}~/~" -f $index, $item.Text) }
        else { $lines += ("  ~gray~[ ]~/~ {0}. {1}" -f $index, $item.Text) }
    }
    $lines += ''
    $lines += '~gray~Alternar:~/~ ~gold~h tick <tarea> <item>~/~   ~gray~Eliminar:~/~ ~gold~h check rm <tarea> <item>~/~'
    Write-HabiticaBlank
    Write-HabiticaPanel -Title ("CHECKLIST // {0}" -f $task.Text) -Lines $lines -Width $width -Color 'cyan'
    Write-HabiticaBlank
}

function Invoke-HabiticaCliTick {
    param([hashtable]$Options, [string[]]$Positionals, [switch]$Reopen)

    if ($Positionals.Count -lt 2) { throw 'Uso: h tick <tarea> <item>' }
    $task = Resolve-HabiticaTaskReference -Reference ([string]$Positionals[0])
    $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)

    $itemRef = [string]$Positionals[1]
    $item = $null
    if ($itemRef -match '^\d+$') {
        $item = $items | Where-Object { $_.Index -eq [int]$itemRef } | Select-Object -First 1
    }
    else {
        $item = $items | Where-Object { $_.Id -eq $itemRef } | Select-Object -First 1
    }
    if (-not $item) { throw ("No existe el item '{0}' en la checklist." -f $itemRef) }

    if ($Reopen) {
        Set-HabiticaChecklistItem -TaskId $task.Id -ItemId $item.Id -Reopen | Out-Null
        Write-HabiticaOk 'Item desmarcado.'
    }
    else {
        Complete-HabiticaChecklistItem -TaskId $task.Id -ItemId $item.Id | Out-Null
    }
}

function Invoke-HabiticaCliTag {
    param([hashtable]$Options, [string[]]$Positionals)

    $sub = if ($Positionals.Count -gt 0) { ([string]$Positionals[0]).ToLowerInvariant() } else { 'list' }
    switch ($sub) {
        'list' { Show-HabiticaTags }
        'add' {
            $name = Get-HabiticaCliTaskFromPositionals -Positionals $Positionals -MinimumIndex 1
            if (-not $name) { throw 'Uso: h tag add "Nombre"' }
            New-HabiticaTag -Name $name | Out-Null
        }
        'rename' {
            if ($Positionals.Count -lt 3) { throw 'Uso: h tag rename <n|nombre> "Nuevo nombre"' }
            $tags = @(Get-HabiticaTag)
            $reference = [string]$Positionals[1]
            $tag = $null
            if ($reference -match '^\d+$') { $tag = $tags | Where-Object { $tags.IndexOf($_) -eq ([int]$reference - 1) } | Select-Object -First 1 }
            if (-not $tag) { $tag = $tags | Where-Object { $_.Id -eq $reference -or $_.Name -eq $reference } | Select-Object -First 1 }
            if (-not $tag) { throw ("No existe la etiqueta '{0}'." -f $reference) }
            $name = (($Positionals[2..($Positionals.Count - 1)]) -join ' ')
            Set-HabiticaTag -Id $tag.Id -Name $name | Out-Null
        }
        'rm' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h tag rm <n|nombre> --yes' }
            $tags = @(Get-HabiticaTag)
            $reference = [string]$Positionals[1]
            $tag = $null
            if ($reference -match '^\d+$') { $tag = $tags | Where-Object { $tags.IndexOf($_) -eq ([int]$reference - 1) } | Select-Object -First 1 }
            if (-not $tag) { $tag = $tags | Where-Object { $_.Id -eq $reference -or $_.Name -eq $reference } | Select-Object -First 1 }
            if (-not $tag) { throw ("No existe la etiqueta '{0}'." -f $reference) }
            Remove-HabiticaTag -Id $tag.Id -Force:(Test-HabiticaCliFlag $Options @('yes', 'force'))
        }
        'attach' {
            if ($Positionals.Count -lt 3) { throw 'Uso: h tag attach <tarea> <etiqueta>' }
            $task = Resolve-HabiticaTaskReference -Reference ([string]$Positionals[1])
            $tagId = Resolve-HabiticaTagId -Reference ([string]$Positionals[2])
            Add-HabiticaTaskTag -TaskId $task.Id -TagId $tagId
        }
        'detach' {
            if ($Positionals.Count -lt 3) { throw 'Uso: h tag detach <tarea> <etiqueta>' }
            $task = Resolve-HabiticaTaskReference -Reference ([string]$Positionals[1])
            $tagId = Resolve-HabiticaTagId -Reference ([string]$Positionals[2])
            Remove-HabiticaTaskTag -TaskId $task.Id -TagId $tagId
        }
        'move' {
            if ($Positionals.Count -lt 3) { throw 'Uso: h tag move <etiqueta> <posicion>' }
            $tagId = Resolve-HabiticaTagId -Reference ([string]$Positionals[1])
            Move-HabiticaTag -Id $tagId -Position ([int]$Positionals[2])
        }
        default { throw 'Uso: h tag [list|add|rename|rm|attach|detach|move]' }
    }
}

function Invoke-HabiticaCliApi {
    param([hashtable]$Options, [string[]]$Positionals)

    if ($Positionals.Count -lt 1) {
        Show-HabiticaCliHelp -Topic 'api'
        return
    }

    $method = 'GET'
    $pathIndex = 0
    if (([string]$Positionals[0]).ToUpperInvariant() -in @('GET', 'POST', 'PUT', 'DELETE')) {
        $method = ([string]$Positionals[0]).ToUpperInvariant()
        $pathIndex = 1
    }
    if ($Positionals.Count -le $pathIndex) { throw 'Indica la ruta de la API.' }
    $path = [string]$Positionals[$pathIndex]

    $body = Get-HabiticaCliOption -Options $Options -Names @('body', 'data')
    if (-not $body -and $Positionals.Count -gt ($pathIndex + 1)) {
        $body = (($Positionals[($pathIndex + 1)..($Positionals.Count - 1)]) -join ' ')
    }

    $params = @{
        Method = $method
        Path   = $path
    }
    if ($body) { $params.Json = [string]$body }
    if (Test-HabiticaCliFlag $Options @('full')) { $params.Full = $true }

    $result = Invoke-HabiticaApi @params
    if ($result -is [string]) { Write-Host $result; return }

    $json = $result | ConvertTo-Json -Depth 40
    Write-HabiticaLine $json
}

function Invoke-HabiticaCliChatReference {
    param([string]$Reference)

    if ($Reference -match '^\d+$') {
        $list = Get-HabiticaLastChat -GroupId 'party'
        if (-not $list) { throw "No hay mensajes recientes. Ejecuta 'h chat' primero." }
        $item = @($list.items | Where-Object { [int]$_.index -eq [int]$Reference }) | Select-Object -First 1
        if (-not $item) { throw ("El mensaje #{0} no existe en la ultima lista." -f $Reference) }
        return $item.id
    }
    return $Reference
}

function Invoke-HabiticaCliParty {
    param([hashtable]$Options, [string[]]$Positionals)

    $sub = if ($Positionals.Count -gt 0) { ([string]$Positionals[0]).ToLowerInvariant() } else { 'show' }
    switch ($sub) {
        'show' { Show-HabiticaParty }
        'members' { Show-HabiticaParty }
        'create' {
            $name = Get-HabiticaCliTaskFromPositionals -Positionals $Positionals -MinimumIndex 1
            if (-not $name) { throw 'Uso: h party create "Nombre de la party"' }
            New-HabiticaParty -Name $name | Out-Null
        }
        'invite' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h party invite <uuid> [uuid2 ...]' }
            Send-HabiticaPartyInvite -UserId @($Positionals[1..($Positionals.Count - 1)]) | Out-Null
        }
        'kick' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h party kick <uuid> --yes' }
            Remove-HabiticaPartyMember -MemberId ([string]$Positionals[1]) -Force:(Test-HabiticaCliFlag $Options @('yes', 'force')) | Out-Null
        }
        'leave' {
            Exit-HabiticaGroup -Force:(Test-HabiticaCliFlag $Options @('yes', 'force'))
        }
        'join' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h party join <group-id>' }
            Join-HabiticaGroup -GroupId ([string]$Positionals[1]) | Out-Null
        }
        default { throw 'Uso: h party [show|members|create|invite|kick|leave|join]' }
    }
}

function Invoke-HabiticaCliQuest {
    param([hashtable]$Options, [string[]]$Positionals)

    $sub = if ($Positionals.Count -gt 0) { ([string]$Positionals[0]).ToLowerInvariant() } else { 'status' }
    switch ($sub) {
        'status' { Show-HabiticaQuest }
        'show' { Show-HabiticaQuest }
        'list' { Show-HabiticaQuestList }
        'invite' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h quest invite <clave>' }
            Invoke-HabiticaQuestAction -Action Invite -QuestKey ([string]$Positionals[1]) | Out-Null
        }
        'accept' { Invoke-HabiticaQuestAction -Action Accept | Out-Null }
        'reject' { Invoke-HabiticaQuestAction -Action Reject | Out-Null }
        'start' { Invoke-HabiticaQuestAction -Action Start | Out-Null }
        'cancel' {
            if (-not (Test-HabiticaCliFlag $Options @('yes', 'force')) -and -not (Test-InteractiveHost)) { throw 'Operacion destructiva. Usa --yes para confirmar.' }
            if (-not (Test-HabiticaCliFlag $Options @('yes', 'force')) -and -not (Confirm-HabiticaAction -Message 'Cancelar la quest pendiente?')) { Write-HabiticaWarn 'Cancelado.'; return }
            Invoke-HabiticaQuestAction -Action Cancel | Out-Null
        }
        'abort' {
            if (-not (Test-HabiticaCliFlag $Options @('yes', 'force')) -and -not (Test-InteractiveHost)) { throw 'Operacion destructiva. Usa --yes para confirmar.' }
            if (-not (Test-HabiticaCliFlag $Options @('yes', 'force')) -and -not (Confirm-HabiticaAction -Message 'Abortar la quest activa?')) { Write-HabiticaWarn 'Cancelado.'; return }
            Invoke-HabiticaQuestAction -Action Abort | Out-Null
        }
        'leave' {
            if (-not (Test-HabiticaCliFlag $Options @('yes', 'force')) -and -not (Test-InteractiveHost)) { throw 'Operacion destructiva. Usa --yes para confirmar.' }
            if (-not (Test-HabiticaCliFlag $Options @('yes', 'force')) -and -not (Confirm-HabiticaAction -Message 'Salir de la quest activa?')) { Write-HabiticaWarn 'Cancelado.'; return }
            Invoke-HabiticaQuestAction -Action Leave | Out-Null
        }
        default { throw 'Uso: h quest [status|list|invite|accept|reject|start|cancel|abort|leave]' }
    }
}

function Invoke-HabiticaCliChallenge {
    param([hashtable]$Options, [string[]]$Positionals)

    $sub = if ($Positionals.Count -gt 0) { ([string]$Positionals[0]).ToLowerInvariant() } else { 'list' }
    switch ($sub) {
        'list' {
            Show-HabiticaChallengeList -Member:(Test-HabiticaCliFlag $Options @('mine', 'member')) -Owned:(Test-HabiticaCliFlag $Options @('owned')) -Search (Get-HabiticaCliOption -Options $Options -Names @('search')) -Page ([int](Get-HabiticaCliOption -Options $Options -Names @('page') -Default 0))
        }
        'show' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge show <n|id>' }
            Show-HabiticaChallengeDetail -Reference ([string]$Positionals[1])
        }
        'join' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge join <n|id>' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            Join-HabiticaChallenge -Id $challenge.Id | Out-Null
        }
        'leave' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge leave <n|id> --yes' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            Exit-HabiticaChallenge -Id $challenge.Id -Force:(Test-HabiticaCliFlag $Options @('yes', 'force')) | Out-Null
        }
        'rm' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge rm <n|id> --yes' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            Remove-HabiticaChallenge -Id $challenge.Id -Force:(Test-HabiticaCliFlag $Options @('yes', 'force')) | Out-Null
        }
        'clone' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge clone <n|id>' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            Copy-HabiticaChallenge -Id $challenge.Id | Out-Null
        }
        'export' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge export <n|id> [archivo.csv]' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            $path = if ($Positionals.Count -ge 3) { [string]$Positionals[2] } else { $null }
            $csv = Export-HabiticaChallenge -Id $challenge.Id
            if ($path) { $csv | Set-Content -LiteralPath $path -Encoding UTF8; Write-HabiticaOk ("CSV exportado a {0}" -f $path) }
            else { Write-Host $csv }
        }
        'winner' {
            if ($Positionals.Count -lt 3) { throw 'Uso: h challenge winner <n|id> <uuid-ganador>' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            Select-HabiticaChallengeWinner -Id $challenge.Id -WinnerId ([string]$Positionals[2]) | Out-Null
        }
        'members' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge members <n|id>' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            $members = @(Get-HabiticaChallengeMembers -Id $challenge.Id)
            $width = Get-TerminalWidth
            $lines = @('~gray~  #  NOMBRE~/~')
            $index = 0
            foreach ($member in $members) {
                $index++
                $lines += ("~gray~{0,3}~/~  ~white~{1}~/~  ~gray~{2}~/~" -f $index, $member.Name, $member.Id)
            }
            Write-HabiticaBlank
            Write-HabiticaPanel -Title ("PARTICIPANTES // {0}" -f $challenge.Name) -Lines $lines -Width $width -Color 'magenta'
            Write-HabiticaBlank
        }
        'create' {
            $name = Get-HabiticaCliOption -Options $Options -Names @('name')
            if (-not $name) { throw 'Uso: h challenge create --name "Reto" [--group <id>] [--prize 5] [--summary "..."]' }
            $groupId = Get-HabiticaCliOption -Options $Options -Names @('group')
            if (-not $groupId) {
                $party = Get-HabiticaParty
                if (-not $party) { throw 'No tienes party. Indica --group <id>.' }
                $groupId = Get-HabiticaObjectValue $party '_id' ''
            }
            New-HabiticaChallenge -GroupId ([string]$groupId) -Name ([string]$name) -ShortName ([string](Get-HabiticaCliOption -Options $Options -Names @('short') -Default '')) -Summary ([string](Get-HabiticaCliOption -Options $Options -Names @('summary') -Default '')) -Description ([string](Get-HabiticaCliOption -Options $Options -Names @('description', 'desc') -Default '')) -Prize ([int](Get-HabiticaCliOption -Options $Options -Names @('prize') -Default 0)) | Out-Null
        }
        'update' {
            if ($Positionals.Count -lt 2) { throw 'Uso: h challenge update <n|id> [--name "..."] [--summary "..."] [--description "..."]' }
            $challenge = Resolve-HabiticaChallengeReference -Reference ([string]$Positionals[1])
            $params = @{ Id = $challenge.Id }
            $name = Get-HabiticaCliOption -Options $Options -Names @('name'); if ($name) { $params.Name = [string]$name }
            $summary = Get-HabiticaCliOption -Options $Options -Names @('summary'); if ($summary) { $params.Summary = [string]$summary }
            $description = Get-HabiticaCliOption -Options $Options -Names @('description', 'desc'); if ($description) { $params.Description = [string]$description }
            Set-HabiticaChallenge @params | Out-Null
        }
        default { throw 'Uso: h challenge [list|show|join|leave|rm|clone|export|winner|members|create|update]' }
    }
}

function Invoke-HabiticaCliCast {
    param([hashtable]$Options, [string[]]$Positionals)

    if ($Positionals.Count -lt 1) {
        throw 'Uso: h cast <n|clave|nombre> [--target <n|id|texto>] [--times n]'
    }

    $reference = [string]$Positionals[0]
    $target = Get-HabiticaCliOption -Options $Options -Names @('target', 'on', 'sobre')
    if (-not $target -and $Positionals.Count -ge 2) {
        $target = (($Positionals[1..($Positionals.Count - 1)]) -join ' ')
    }

    $quantity = 1
    $times = Get-HabiticaCliOption -Options $Options -Names @('times', 'quantity', 'veces')
    if ($times) {
        if (-not [int]::TryParse([string]$times, [ref]$quantity)) {
            throw '--times debe ser un numero entero.'
        }
    }
    if ($quantity -lt 1 -or $quantity -gt 50) {
        throw '--times debe estar entre 1 y 50.'
    }

    Invoke-HabiticaSkillCast -Skill $reference -Target ([string]$target) -Quantity $quantity | Out-Null
}

function Invoke-HabiticaCliConfig {
    param([hashtable]$Options, [string[]]$Positionals)

    $sub = if ($Positionals.Count -gt 0) { ([string]$Positionals[0]).ToLowerInvariant() } else { 'show' }
    switch ($sub) {
        'init' { Invoke-HabiticaSetup }
        'show' {
            $config = Get-HabiticaConfig
            $width = Get-TerminalWidth
            $lines = @(
                ("~gray~User ID:~/~    ~white~{0}~/~" -f $config.UserId),
                ("~gray~API Token:~/~  ~white~{0}~/~" -f $config.ApiToken),
                ("~gray~Client ID:~/~  ~white~{0}~/~" -f $config.ClientId),
                ("~gray~Base URL:~/~   ~gray~{0}~/~" -f $config.BaseUrl),
                ("~gray~Timeout:~/~    ~white~{0}s~/~" -f $config.TimeoutSec),
                ("~gray~Archivo:~/~    ~gray~{0}~/~" -f $config.ConfigFile),
                '',
                '~gray~Cambiar:~/~ ~gold~h config init~/~   ~gray~Probar:~/~ ~gold~h config test~/~'
            )
            Write-HabiticaBlank
            Write-HabiticaPanel -Title 'CONFIGURACION' -Lines $lines -Width $width -Color 'gold'
            Write-HabiticaBlank
        }
        'test' {
            Write-HabiticaInfo 'Probando conexion con Habitica...'
            try {
                $test = Test-HabiticaConnection
                Write-HabiticaOk ("Conectado como {0} (nivel {1})." -f $test.Name, $test.Level)
            }
            catch {
                Write-HabiticaError $_.Exception.Message
            }
        }
        'path' { Write-Host (Get-HabiticaConfigPath) }
        'reset' {
            $force = Test-HabiticaCliFlag $Options @('yes', 'force')
            if (-not $force) {
                if (-not (Test-InteractiveHost)) { throw 'Operacion destructiva. Usa --yes para confirmar.' }
                if (-not (Confirm-HabiticaAction -Message 'Eliminar las credenciales guardadas?')) {
                    Write-HabiticaWarn 'Cancelado.'
                    return
                }
            }
            Reset-HabiticaConfig -Confirm:$false
        }
        'cache' { Clear-HabiticaLocalCache }
        'set' {
            $params = @{}
            $userId = Get-HabiticaCliOption -Options $Options -Names @('user', 'userid'); if ($userId) { $params.UserId = [string]$userId }
            $token = Get-HabiticaCliOption -Options $Options -Names @('token'); if ($token) { $params.ApiToken = [string]$token }
            $client = Get-HabiticaCliOption -Options $Options -Names @('client', 'clientid'); if ($client) { $params.ClientId = [string]$client }
            $baseUrl = Get-HabiticaCliOption -Options $Options -Names @('baseurl'); if ($baseUrl) { $params.BaseUrl = [string]$baseUrl }
            if ($params.Count -eq 0) { throw 'Uso: h config set --user <id> --token <token> --client <id>' }
            Set-HabiticaConfig @params -PassThru | Format-Table
        }
        default { throw 'Uso: h config [show|init|test|path|reset|cache|set]' }
    }
}

# -----------------------------------------------------------------------------
#  Dispatcher principal
# -----------------------------------------------------------------------------

function Invoke-HabiticaCli {
    <#
    .SYNOPSIS
      Punto de entrada de Habitica CLI.
    .EXAMPLE
      h today
    .EXAMPLE
      h add "Comprar leche" --due manana --priority media
    .EXAMPLE
      h done 3
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    Initialize-HabiticaConsole

    $parsed = ConvertTo-HabiticaCliArguments -Tokens $Arguments
    $options = $parsed.Options
    $positionals = $parsed.Positionals
    $commandKey = if ([string]::IsNullOrWhiteSpace($Command)) { 'today' } else { $Command.ToLowerInvariant() }
    $listTag = [string](Get-HabiticaCliOption -Options $options -Names @('tag', 'tags') -Default '')
    $listSearch = [string](Get-HabiticaCliOption -Options $options -Names @('search', 'q') -Default '')

    if (Test-HabiticaCliFlag $options @('no-color')) {
        $script:UseColor = $false
    }

    if (Test-HabiticaCliFlag $options @('help')) {
        $helpTopic = switch ($commandKey) {
            { $_ -in @('add', 'new', 'edit', 'done', 'complete', 'undo', 'up', 'down', 'buy', 'show', 'which', 'rm', 'del', 'move', 'clear', 'check', 'tick', 'untick', 'todo', 'todos', 'tareas', 'daily', 'dailies', 'diarias', 'habit', 'habits', 'habitos', 'reward', 'rewards', 'recompensas', 'ls', 'list', 'all') } { 'tasks' }
            { $_ -in @('party', 'chat', 'quest', 'quests', 'challenges', 'challenge', 'retos', 'inbox', 'messages', 'groups') } { 'social' }
            { $_ -in @('skills', 'poderes', 'spells', 'cast', 'lanzar', 'usar') } { 'powers' }
            { $_ -in @('config', 'login', 'setup', 'status') } { 'config' }
            'api' { 'api' }
            'raw' { 'api' }
            { $_ -in @('ui', 'tui') } { 'ui' }
            default { '' }
        }
        Show-HabiticaCliHelp -Topic $helpTopic
        return
    }

    try {
        switch ($commandKey) {
            '' { Show-HabiticaDashboard }
            'today' { Show-HabiticaDashboard }
            'hoy' { Show-HabiticaDashboard }
            'dashboard' { Show-HabiticaDashboard -Refresh }
            'ui' { Start-HabiticaUi }
            'tui' { Start-HabiticaUi }

            'ls' { Show-HabiticaAllTasks -Tag $listTag -Search $listSearch -IncludeInactiveDailies:(Test-HabiticaCliFlag $options @('all')) }
            'list' { Show-HabiticaAllTasks -Tag $listTag -Search $listSearch -IncludeInactiveDailies:(Test-HabiticaCliFlag $options @('all')) }
            'all' { Show-HabiticaAllTasks -Tag $listTag -Search $listSearch -IncludeInactiveDailies:(Test-HabiticaCliFlag $options @('all')) }
            'todo' { Show-HabiticaTaskList -Type Todo -Tag $listTag -Search $listSearch }
            'todos' { Show-HabiticaTaskList -Type Todo -Tag $listTag -Search $listSearch }
            'tareas' { Show-HabiticaTaskList -Type Todo -Tag $listTag -Search $listSearch }
            'daily' { Show-HabiticaTaskList -Type Daily -Tag $listTag -Search $listSearch -ActiveOnly:(-not (Test-HabiticaCliFlag $options @('all'))) }
            'dailies' { Show-HabiticaTaskList -Type Daily -Tag $listTag -Search $listSearch -ActiveOnly:(-not (Test-HabiticaCliFlag $options @('all'))) }
            'diarias' { Show-HabiticaTaskList -Type Daily -Tag $listTag -Search $listSearch -ActiveOnly:(-not (Test-HabiticaCliFlag $options @('all'))) }
            'habit' { Show-HabiticaTaskList -Type Habit -Tag $listTag -Search $listSearch }
            'habits' { Show-HabiticaTaskList -Type Habit -Tag $listTag -Search $listSearch }
            'habitos' { Show-HabiticaTaskList -Type Habit -Tag $listTag -Search $listSearch }
            'reward' { Show-HabiticaTaskList -Type Reward -Tag $listTag -Search $listSearch }
            'rewards' { Show-HabiticaTaskList -Type Reward -Tag $listTag -Search $listSearch }
            'recompensas' { Show-HabiticaTaskList -Type Reward -Tag $listTag -Search $listSearch }
            'completed' { Show-HabiticaTaskList -Type CompletedTodo }
            'completadas' { Show-HabiticaTaskList -Type CompletedTodo }

            'done' { Invoke-HabiticaCliScore -Options $options -Positionals $positionals -Direction Up }
            'which' { Invoke-HabiticaCliWhich -Positionals $positionals }

            'add' { Invoke-HabiticaCliAdd -Options $options -Positionals $positionals }
            'new' { Invoke-HabiticaCliAdd -Options $options -Positionals $positionals }
            'edit' { Invoke-HabiticaCliEdit -Options $options -Positionals $positionals }
            'show' { if ($positionals.Count -lt 1) { throw 'Uso: h show <n|id|texto>' }; Show-HabiticaTaskDetail -Reference ([string]$positionals[0]) }
            'rm' { if ($positionals.Count -lt 1) { throw 'Uso: h rm <n|id|texto> --yes' }; $task = Resolve-HabiticaTaskReference -Reference ([string]$positionals[0]); Remove-HabiticaTask -Id $task.Id -Force:(Test-HabiticaCliFlag $options @('yes', 'force')) | Out-Null }
            'del' { if ($positionals.Count -lt 1) { throw 'Uso: h del <n|id|texto> --yes' }; $task = Resolve-HabiticaTaskReference -Reference ([string]$positionals[0]); Remove-HabiticaTask -Id $task.Id -Force:(Test-HabiticaCliFlag $options @('yes', 'force')) | Out-Null }
            'complete' { Invoke-HabiticaCliScore -Options $options -Positionals $positionals -Direction Up }
            'undo' { Invoke-HabiticaCliScore -Options $options -Positionals $positionals -Direction Down }
            'up' { Invoke-HabiticaCliScore -Options $options -Positionals $positionals -Direction Up }
            'down' { Invoke-HabiticaCliScore -Options $options -Positionals $positionals -Direction Down }
            'buy' {
                if ($positionals.Count -lt 1) { throw 'Uso: h buy <n|id|texto>' }
                $task = Resolve-HabiticaTaskReference -Reference ([string]$positionals[0])
                if ($task.Type -ne 'reward') { throw ("'{0}' no es una recompensa." -f $task.Text) }
                if (Test-HabiticaCliFlag $options @('dry-run', 'dryrun', 'see')) {
                    Write-HabiticaBlank
                    Write-HabiticaLine ("  ~gray~[simulacion]~/~ ~gold~Comprar~/~  ~white~{0}~/~" -f $task.Text)
                    Write-HabiticaLine ("           ~gray~ID:~/~ ~gray~{0}~/~" -f $task.Id)
                    Write-HabiticaBlank
                }
                else {
                    Invoke-HabiticaTaskScore -Id $task.Id -Direction Down -Text $task.Text | Out-Null
                }
            }
            'move' {
                if ($positionals.Count -lt 2) { throw 'Uso: h move <n|id> <posicion>' }
                $task = Resolve-HabiticaTaskReference -Reference ([string]$positionals[0])
                Move-HabiticaTask -Id $task.Id -Position ([int]$positionals[1])
            }
            'clear' { Clear-HabiticaCompletedTodo -Force:(Test-HabiticaCliFlag $options @('yes', 'force')) }

            'check' {
                if ($positionals.Count -eq 0) { throw 'Uso: h check <n> | h check add <n> "texto" | h check rm <n> <item>' }
                $sub = ([string]$positionals[0]).ToLowerInvariant()
                if ($sub -in @('add', 'rm', 'remove', 'edit')) {
                    if ($positionals.Count -lt 2) { throw 'Indica la tarea.' }
                    $task = Resolve-HabiticaTaskReference -Reference ([string]$positionals[1])
                    switch ($sub) {
                        'add' {
                            $text = (($positionals[2..($positionals.Count - 1)]) -join ' ')
                            if (-not $text) { throw 'Indica el texto del item.' }
                            Add-HabiticaChecklistItem -TaskId $task.Id -Text $text | Out-Null
                        }
                        { $_ -in @('rm', 'remove') } {
                            if ($positionals.Count -lt 3) { throw 'Indica el numero de item.' }
                            $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)
                            $item = $items | Where-Object { $_.Index -eq [int]$positionals[2] } | Select-Object -First 1
                            if (-not $item) { throw 'Item no encontrado.' }
                            Remove-HabiticaChecklistItem -TaskId $task.Id -ItemId $item.Id | Out-Null
                        }
                        'edit' {
                            if ($positionals.Count -lt 4) { throw 'Uso: h check edit <tarea> <item> "texto"' }
                            $items = @(Get-HabiticaChecklistItem -TaskId $task.Id)
                            $item = $items | Where-Object { $_.Index -eq [int]$positionals[2] } | Select-Object -First 1
                            if (-not $item) { throw 'Item no encontrado.' }
                            $text = (($positionals[3..($positionals.Count - 1)]) -join ' ')
                            Set-HabiticaChecklistItem -TaskId $task.Id -ItemId $item.Id -Text $text | Out-Null
                        }
                    }
                }
                else {
                    Invoke-HabiticaCliCheck -Options $options -Positionals $positionals
                }
            }
            'tick' { Invoke-HabiticaCliTick -Options $options -Positionals $positionals }
            'untick' { Invoke-HabiticaCliTick -Options $options -Positionals $positionals -Reopen }

            'tag' { Invoke-HabiticaCliTag -Options $options -Positionals $positionals }
            'tags' { Invoke-HabiticaCliTag -Options $options -Positionals $positionals }

            'stats' { Show-HabiticaStats -Refresh }
            'stat' { Show-HabiticaStats -Refresh }
            'skills' { Show-HabiticaSkills -Refresh }
            'poderes' { Show-HabiticaSkills -Refresh }
            'spells' { Show-HabiticaSkills -Refresh }
            'cast' { Invoke-HabiticaCliCast -Options $options -Positionals $positionals }
            'usar' { Invoke-HabiticaCliCast -Options $options -Positionals $positionals }
            'lanzar' { Invoke-HabiticaCliCast -Options $options -Positionals $positionals }
            'profile' { Show-HabiticaProfile -Refresh }
            'perfil' { Show-HabiticaProfile -Refresh }
            'notify' {
                $sub = if ($positionals.Count -gt 0) { ([string]$positionals[0]).ToLowerInvariant() } else { 'show' }
                switch ($sub) {
                    'show' { Show-HabiticaNotifications }
                    'read' {
                        $ids = @($positionals | Select-Object -Skip 1)
                        Set-HabiticaNotificationStatus -Status Read -All:((Test-HabiticaCliFlag $options @('all')) -or $ids.Count -eq 0) -Id $ids
                    }
                    'see' {
                        $ids = @($positionals | Select-Object -Skip 1)
                        Set-HabiticaNotificationStatus -Status See -All:((Test-HabiticaCliFlag $options @('all')) -or $ids.Count -eq 0) -Id $ids
                    }
                    default { Show-HabiticaNotifications }
                }
            }
            'notifications' { Show-HabiticaNotifications }

            'party' { Invoke-HabiticaCliParty -Options $options -Positionals $positionals }
            'groups' {
                $groups = @(Get-HabiticaGroups -Type All)
                $width = Get-TerminalWidth
                $lines = @('~gray~  #  TIPO       NOMBRE~/~')
                $index = 0
                foreach ($group in $groups) {
                    $index++
                    $lines += ("~gray~{0,3}~/~  ~cyan~{1,-10}~/~ ~white~{2}~/~" -f $index, (Get-HabiticaPropertyText -Object $group -Name 'type' -Default 'group'), (Get-HabiticaPropertyText -Object $group -Name 'name' -Default '(sin nombre)'))
                }
                Write-HabiticaBlank
                Write-HabiticaPanel -Title 'GRUPOS' -Lines $lines -Width $width -Color 'magenta'
                Write-HabiticaBlank
            }
            'chat' {
                $first = if ($positionals.Count -gt 0) { ([string]$positionals[0]).ToLowerInvariant() } else { '' }
                switch ($first) {
                    'like' {
                        if ($positionals.Count -lt 2) { throw 'Uso: h chat like <n>' }
                        $messageId = Invoke-HabiticaCliChatReference -Reference ([string]$positionals[1])
                        Add-HabiticaChatLike -MessageId $messageId
                    }
                    'rm' {
                        if ($positionals.Count -lt 2) { throw 'Uso: h chat rm <n> --yes' }
                        $messageId = Invoke-HabiticaCliChatReference -Reference ([string]$positionals[1])
                        Remove-HabiticaChatMessage -MessageId $messageId -Force:(Test-HabiticaCliFlag $options @('yes', 'force'))
                    }
                    'seen' { Set-HabiticaChatSeen }
                    'send' {
                        $message = (($positionals[1..($positionals.Count - 1)]) -join ' ')
                        if (-not $message) { throw 'Uso: h chat send "mensaje"' }
                        Send-HabiticaChatMessage -Message $message | Out-Null
                    }
                    '' {
                        $limit = [int](Get-HabiticaCliOption -Options $options -Names @('limit') -Default 20)
                        Show-HabiticaChat -Limit $limit
                    }
                    default {
                        $message = ($positionals -join ' ')
                        Send-HabiticaChatMessage -Message $message | Out-Null
                    }
                }
            }

            'quest' { Invoke-HabiticaCliQuest -Options $options -Positionals $positionals }
            'quests' { Invoke-HabiticaCliQuest -Options $options -Positionals $positionals }
            'challenges' { Invoke-HabiticaCliChallenge -Options $options -Positionals $positionals }
            'challenge' { Invoke-HabiticaCliChallenge -Options $options -Positionals $positionals }
            'retos' { Invoke-HabiticaCliChallenge -Options $options -Positionals $positionals }

            'inbox' {
                $sub = if ($positionals.Count -gt 0) { ([string]$positionals[0]).ToLowerInvariant() } else { 'show' }
                if ($sub -eq 'send') {
                    if ($positionals.Count -lt 3) { throw 'Uso: h inbox send <uuid> "mensaje"' }
                    $message = (($positionals[2..($positionals.Count - 1)]) -join ' ')
                    Send-HabiticaPrivateMessage -ToUserId ([string]$positionals[1]) -Message $message | Out-Null
                }
                else {
                    $page = [int](Get-HabiticaCliOption -Options $options -Names @('page') -Default 0)
                    Show-HabiticaInbox -Page $page
                }
            }
            'messages' { Show-HabiticaInbox }

            'config' { Invoke-HabiticaCliConfig -Options $options -Positionals $positionals }
            'login' { Invoke-HabiticaSetup }
            'setup' { Invoke-HabiticaSetup }
            'status' { Invoke-HabiticaCliConfig -Options $options -Positionals @('test') }
            'refresh' { Clear-HabiticaLocalCache; Show-HabiticaDashboard -Refresh }
            'version' { Show-HabiticaVersion }
            '--version' { Show-HabiticaVersion }
            'api' { Invoke-HabiticaCliApi -Options $options -Positionals $positionals }
            'raw' { Invoke-HabiticaCliApi -Options $options -Positionals $positionals }

            'help' {
                $helpTopic = if ($positionals.Count -gt 0) { [string]$positionals[0] } else { '' }
                Show-HabiticaCliHelp -Topic $helpTopic
            }
            '?' { Show-HabiticaCliHelp }
            'keys' { Show-HabiticaCliHelp -Topic 'ui' }
            default {
                Write-HabiticaError ("Comando desconocido: '{0}'." -f $Command)
                Write-HabiticaLine ("  Prueba ~gold~h help~/~ o ~gold~h help tasks~/~.")
                Write-HabiticaBlank
            }
        }
    }
    catch {
        Write-HabiticaBlank
        Write-HabiticaError $_.Exception.Message
        Write-HabiticaBlank
    }
}

function habitica {
    <#
    .SYNOPSIS
      Habitica CLI: administra tu cuenta de Habitica desde la terminal.
    .EXAMPLE
      habitica
    .EXAMPLE
      habitica add "Comprar leche" --due manana
    .EXAMPLE
      habitica ui
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    Invoke-HabiticaCli -Command $Command -Arguments $Arguments
}

