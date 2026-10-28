param(
    [int]$Port = 18765
)

$ErrorActionPreference = 'Stop'

# Servidor HTTP minimo sobre TcpListener para pruebas locales.
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

$script:Now = [DateTime]::UtcNow

function New-MockTask {
    param(
        [string]$Id,
        [string]$Text,
        [string]$Type,
        [double]$Priority = 1,
        [string]$Notes = '',
        [string[]]$Tags = @(),
        [string]$Date = $null,
        [bool]$Completed = $false,
        [bool]$IsDue = $true
    )

    return [ordered]@{
        id         = $Id
        _id        = $Id
        text       = $Text
        type       = $Type
        notes      = $Notes
        priority   = $Priority
        attribute  = 'str'
        completed  = $Completed
        isDue      = $IsDue
        tags       = @($Tags)
        checklist  = @()
        date       = $Date
        value      = 0
        streak     = 0
        counterUp  = 0
        counterDown = 0
        up         = $true
        down       = $true
        frequency  = 'weekly'
        everyX     = 1
        repeat     = @{ su = $true; m = $true; t = $true; w = $true; th = $true; f = $true; s = $true }
        startDate  = '2024-01-01T00:00:00.000Z'
        challenge  = @{}
        group      = @{ id = 'party-1'; assignedUsers = @() }
    }
}

$script:Tasks = @(
    (New-MockTask -Id '11111111-1111-1111-1111-111111111111' -Text 'Comprar leche' -Type 'todo' -Priority 1.5 -Notes 'Leche entera' -Tags @('tag-casa') -Date ((Get-Date).ToString('yyyy-MM-dd')))
    (New-MockTask -Id '22222222-2222-2222-2222-222222222222' -Text 'Pagar la luz' -Type 'todo' -Priority 2 -Date ((Get-Date).AddDays(2).ToString('yyyy-MM-dd')))
    (New-MockTask -Id '33333333-3333-3333-3333-333333333333' -Text 'Llamar al dentista' -Type 'todo' -Priority 1)
    (New-MockTask -Id '44444444-4444-4444-4444-444444444444' -Text 'Ejercicio' -Type 'daily' -Priority 1.5 -Notes '30 minutos')
    (New-MockTask -Id '55555555-5555-5555-5555-555555555555' -Text 'Leer 10 paginas' -Type 'daily' -Priority 1 -IsDue $false)
    (New-MockTask -Id '66666666-6666-6666-6666-666666666666' -Text 'Beber agua' -Type 'habit' -Priority 1 -Tags @('tag-salud'))
    (New-MockTask -Id '77777777-7777-7777-7777-777777777777' -Text 'Procrastinar' -Type 'habit' -Priority 0.1)
    (New-MockTask -Id '88888888-8888-8888-8888-888888888888' -Text 'Ver una pelicula' -Type 'reward' -Priority 1)
)
$script:Tasks[0].checklist = @(
    @{ id = 'c1'; text = 'Revisar nevera'; completed = $false }
    @{ id = 'c2'; text = 'Llevar bolsa'; completed = $true }
)
$script:Tasks[1].checklist = @()
$script:Tasks[3].streak = 4
$script:Tasks[3].completed = $false
$script:Tasks[5].counterUp = 7
$script:Tasks[5].counterDown = 1
$script:Tasks[6].up = $false
$script:Tasks[7].value = 20

# Simula la API real: los tipos pueden llegar mezclados en cualquier orden.
if ($env:HABITICA_MOCK_SHUFFLE -eq '1') {
    $script:Tasks = @($script:Tasks | Sort-Object { [Guid]::NewGuid().ToString() })
}

$script:Tags = @(
    [ordered]@{ id = 'tag-casa'; name = 'casa' }
    [ordered]@{ id = 'tag-trabajo'; name = 'trabajo' }
    [ordered]@{ id = 'tag-salud'; name = 'salud' }
)

$script:Chat = @(
    [ordered]@{ id = 'chat-1'; uuid = 'user-1'; text = 'Hola party!' ; timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-30).ToUnixTimeMilliseconds(); likes = @{} }
    [ordered]@{ id = 'chat-2'; uuid = 'user-2'; text = 'A por la quest de hoy' ; timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToUnixTimeMilliseconds(); likes = @{ 'user-1' = $true } }
    [ordered]@{ id = 'chat-3'; uuid = 'user-1'; text = 'Vamos alla' ; timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToUnixTimeMilliseconds(); likes = @{} }
)

$script:Members = @(
    [ordered]@{ _id = 'user-1'; profile = @{ name = 'TestHero' }; stats = @{ class = 'rogue'; lvl = 13; hp = 40; maxHealth = 50 }; auth = @{ timestamps = @{ lastLoggedIn = (Get-Date).ToString('o') } } }
    [ordered]@{ _id = 'user-2'; profile = @{ name = 'Luna' }; stats = @{ class = 'healer'; lvl = 10; hp = 48; maxHealth = 50 }; auth = @{ timestamps = @{ lastLoggedIn = (Get-Date).AddHours(-2).ToString('o') } } }
    [ordered]@{ _id = 'user-3'; profile = @{ name = 'Kai' }; stats = @{ class = 'warrior'; lvl = 14; hp = 35; maxHealth = 55 }; auth = @{ timestamps = @{ lastLoggedIn = (Get-Date).AddDays(-1).ToString('o') } } }
)

$script:User = [ordered]@{
    _id       = 'user-1'
    profile   = @{ name = 'TestHero'; joined = '2020-01-01T00:00:00.000Z' }
    stats     = @{
        hp = 40; maxHealth = 50; exp = 30; toNextLevel = 100; mp = 50; maxMP = 50;
        gp = 123.45; lvl = 13; class = 'rogue'; points = 2;
        str = 10; int = 12; per = 14; con = 8; streak = 3;
        buffs = @{ str = 0; int = 0; per = 0; con = 0 }
    }
    party     = @{ _id = 'party-1'; name = 'Test Party'; quest = @{ key = 'goldenknight'; RSVPNeeded = $false } }
    notifications = @(
        @{ id = 'notification-1'; type = 'TEST_NOTIFICATION'; seen = $false; data = @{ message = 'Hola' } }
    )
    items     = @{ quests = @{ goldenknight = 1; dustbunnies = 1 } }
}

$script:Party = [ordered]@{
    _id = 'party-1'
    name = 'Test Party'
    type = 'party'
    privacy = 'private'
    description = 'Una party de prueba'
    leader = 'user-1'
    members = @($script:Members)
    memberCount = 3
    chat = @()
    quest = [ordered]@{
        key = 'goldenknight'
        active = $true
        leader = 'user-1'
        progress = [ordered]@{ hp = 400; rage = 10; up = 3; down = 1; collect = @{} }
        members = @{}
    }
}

$script:Challenges = @(
    [ordered]@{ _id = 'challenge-1'; name = 'Reto de lectura'; shortName = 'lectura'; summary = 'Lee cada dia'; description = 'Un reto de prueba'; prize = 5; memberCount = 3; official = $false; group = @{ _id = 'party-1'; name = 'Test Party' }; leader = @{ _id = 'user-2'; profile = @{ name = 'Luna' } }; categories = @() }
    [ordered]@{ _id = 'challenge-2'; name = 'Reto de ejercicio'; shortName = 'ejercicio'; summary = 'Muevete'; description = 'Otro reto'; prize = 2; memberCount = 8; official = $false; group = @{ _id = 'party-1'; name = 'Test Party' }; leader = @{ _id = 'user-1'; profile = @{ name = 'TestHero' } }; categories = @() }
)

$script:Inbox = @(
    [ordered]@{ _id = 'inbox-1'; uuid = 'user-2'; text = 'Hola! Te apuntas a la quest?'; timestamp = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds(); sent = $false; likes = @{} }
)

$script:Content = @{
    quests = @{
        goldenknight = @{ text = 'El Caballero Dorado'; notes = 'Derrota al caballero dorado.'; boss = @{ hp = 500; rage = @{ value = 50 } }; collect = @{} }
        dustbunnies = @{ text = 'Conejos de Polvo'; notes = 'Recoge pelusa.'; boss = $null; collect = @{ 'dust' = @{ text = 'Polvo'; count = 10 } } }
    }
}

$script:MockSpells = @{
    warrior = @{
        smash = @{ mana = 10; target = 'task' }
        defensiveStance = @{ mana = 25; target = 'self' }
        valorousPresence = @{ mana = 20; target = 'party' }
        intimidate = @{ mana = 15; target = 'party' }
    }
    rogue = @{
        pickPocket = @{ mana = 10; target = 'task' }
        backStab = @{ mana = 15; target = 'task' }
        toolsOfTrade = @{ mana = 25; target = 'party' }
        stealth = @{ mana = 45; target = 'self' }
    }
    wizard = @{
        fireball = @{ mana = 10; target = 'task' }
        mpheal = @{ mana = 30; target = 'party' }
        earth = @{ mana = 35; target = 'party' }
        frost = @{ mana = 40; target = 'self' }
    }
    healer = @{
        heal = @{ mana = 15; target = 'self' }
        brightness = @{ mana = 15; target = 'tasks' }
        protectAura = @{ mana = 30; target = 'party' }
        healAll = @{ mana = 25; target = 'party' }
    }
}

function Send-MockResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode = 200,
        $Data = $null,
        [string]$ContentType = 'application/json'
    )

    $payload = ''
    if ($null -ne $Data) {
        if ($Data -is [string]) { $payload = $Data }
        else { $payload = $Data | ConvertTo-Json -Depth 30 -Compress }
    }

    $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $statusText = switch ($StatusCode) {
        200 { 'OK' }
        201 { 'Created' }
        204 { 'No Content' }
        400 { 'Bad Request' }
        401 { 'Unauthorized' }
        404 { 'Not Found' }
        default { 'OK' }
    }
    $header = "HTTP/1.1 $StatusCode $statusText`r`nContent-Type: $ContentType; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($body.Length -gt 0) { $Stream.Write($body, 0, $body.Length) }
    $Stream.Flush()
}

function Send-MockJson {
    param([System.Net.Sockets.NetworkStream]$Stream, $Data, [int]$StatusCode = 200)
    Send-MockResponse -Stream $Stream -StatusCode $StatusCode -Data @{ success = $true; data = $Data; notifications = @() }
}

function Send-MockError {
    param([System.Net.Sockets.NetworkStream]$Stream, [int]$StatusCode, [string]$Message)
    Send-MockResponse -Stream $Stream -StatusCode $StatusCode -Data @{ success = $false; error = 'MockError'; message = $Message }
}

function Parse-MockQuery {
    param([string]$Query)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Query)) { return $result }
    foreach ($pair in $Query.TrimStart('?').Split('&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $parts = $pair.Split('=', 2)
        $key = [uri]::UnescapeDataString($parts[0])
        $value = if ($parts.Count -gt 1) { [uri]::UnescapeDataString($parts[1]) } else { '' }
        $result[$key] = $value
    }
    return $result
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        try {
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }

            $parts = $requestLine.Split(' ')
            $method = $parts[0].ToUpperInvariant()
            $target = $parts[1]

            $headers = @{}
            while ($true) {
                $line = $reader.ReadLine()
                if ($null -eq $line -or $line -eq '') { break }
                $index = $line.IndexOf(':')
                if ($index -gt 0) {
                    $headers[$line.Substring(0, $index).Trim().ToLowerInvariant()] = $line.Substring($index + 1).Trim()
                }
            }

            $body = ''
            if ($headers.ContainsKey('content-length')) {
                $length = [int]$headers['content-length']
                if ($length -gt 0) {
                    $buffer = New-Object char[] $length
                    $read = 0
                    while ($read -lt $length) {
                        $count = $reader.Read($buffer, $read, $length - $read)
                        if ($count -le 0) { break }
                        $read += $count
                    }
                    $body = -join $buffer[0..($read - 1)]
                }
            }

            $bodyObject = $null
            if (-not [string]::IsNullOrWhiteSpace($body)) {
                try { $bodyObject = $body | ConvertFrom-Json } catch { }
            }

            $uri = [uri]('http://localhost' + $target)
            $path = $uri.AbsolutePath
            if ($path.StartsWith('/api/v3/')) { $path = $path.Substring(7) }
            elseif ($path -eq '/api/v3') { $path = '' }
            $path = $path.TrimStart('/')
            $segments = @($path.Split('/') | Where-Object { $_ -ne '' } | ForEach-Object { [uri]::UnescapeDataString($_) })
            $query = Parse-MockQuery -Query $uri.Query

            # ---- endpoints -------------------------------------------------
            if ($path -eq 'status' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data @{ status = 'up' }
                continue
            }

            if ($path -eq 'user' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data $script:User
                continue
            }

            if ($path -eq 'user' -and $method -eq 'PUT') {
                Send-MockJson -Stream $stream -Data $script:User
                continue
            }

            if ($path -eq 'content' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data $script:Content
                continue
            }

            if ($path -eq 'tags' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data @($script:Tags)
                continue
            }
            if ($path -eq 'tags' -and $method -eq 'POST') {
                $newTag = [ordered]@{ id = 'tag-' + [Guid]::NewGuid().ToString('N').Substring(0, 8); name = [string]$bodyObject.name }
                $script:Tags += $newTag
                Send-MockJson -Stream $stream -Data $newTag -StatusCode 201
                continue
            }
            if ($segments.Count -eq 2 -and $segments[0] -eq 'tags' -and $method -eq 'PUT') {
                $tag = $script:Tags | Where-Object { $_.id -eq $segments[1] } | Select-Object -First 1
                if ($tag) { $tag.name = [string]$bodyObject.name; Send-MockJson -Stream $stream -Data $tag; continue }
                Send-MockError -Stream $stream -StatusCode 404 -Message 'Tag not found'; continue
            }
            if ($segments.Count -eq 2 -and $segments[0] -eq 'tags' -and $method -eq 'DELETE') {
                $script:Tags = @($script:Tags | Where-Object { $_.id -ne $segments[1] })
                Send-MockResponse -Stream $stream -StatusCode 200 -Data @{ success = $true; data = @{} }
                continue
            }
            if ($path -eq 'reorder-tags' -and $method -eq 'POST') {
                Send-MockJson -Stream $stream -Data @{}
                continue
            }

            if ($path -eq 'tasks/user' -and $method -eq 'GET') {
                $type = if ($query.ContainsKey('type')) { $query['type'] } else { '' }
                $result = @()
                switch ($type) {
                    'todos' { $result = @($script:Tasks | Where-Object { $_.type -eq 'todo' -and -not $_.completed }) }
                    'dailys' { $result = @($script:Tasks | Where-Object { $_.type -eq 'daily' }) }
                    'habits' { $result = @($script:Tasks | Where-Object { $_.type -eq 'habit' }) }
                    'rewards' { $result = @($script:Tasks | Where-Object { $_.type -eq 'reward' }) }
                    'completedTodos' { $result = @($script:Tasks | Where-Object { $_.type -eq 'todo' -and $_.completed }) }
                    default { $result = @($script:Tasks | Where-Object { -not ($_.type -eq 'todo' -and $_.completed) }) }
                }
                Send-MockJson -Stream $stream -Data @($result)
                continue
            }

            if ($path -eq 'tasks/user' -and $method -eq 'POST') {
                $new = New-MockTask -Id ([Guid]::NewGuid().ToString()) -Text ([string]$bodyObject.text) -Type ([string]$bodyObject.type) -Priority ([double]$bodyObject.priority)
                foreach ($property in $bodyObject.PSObject.Properties) {
                    if ($property.Name -in @('text', 'type', 'priority')) { continue }
                    $new[$property.Name] = $property.Value
                }
                if ($new.type -eq 'daily' -and -not $new.Contains('startDate')) { $new.startDate = (Get-Date).ToString('yyyy-MM-dd') }
                $script:Tasks += $new
                Send-MockJson -Stream $stream -Data $new -StatusCode 201
                continue
            }

            if ($path -eq 'tasks/clearCompletedTodos' -and $method -eq 'POST') {
                $script:Tasks = @($script:Tasks | Where-Object { -not ($_.type -eq 'todo' -and $_.completed) })
                Send-MockJson -Stream $stream -Data @{}
                continue
            }

            if ($segments.Count -ge 2 -and $segments[0] -eq 'tasks') {
                $taskId = $segments[1]
                $task = $script:Tasks | Where-Object { $_.id -eq $taskId } | Select-Object -First 1

                if (-not $task) {
                    Send-MockError -Stream $stream -StatusCode 404 -Message 'Task not found'
                    continue
                }

                if ($segments.Count -eq 2 -and $method -eq 'GET') {
                    Send-MockJson -Stream $stream -Data $task
                    continue
                }
                if ($segments.Count -eq 2 -and $method -eq 'PUT') {
                    foreach ($property in $bodyObject.PSObject.Properties) {
                        $task[$property.Name] = $property.Value
                    }
                    Send-MockJson -Stream $stream -Data $task
                    continue
                }
                if ($segments.Count -eq 2 -and $method -eq 'DELETE') {
                    $script:Tasks = @($script:Tasks | Where-Object { $_.id -ne $taskId })
                    Send-MockJson -Stream $stream -Data @{}
                    continue
                }

                if ($segments.Count -eq 4 -and $segments[2] -eq 'score') {
                    $direction = $segments[3]
                    $delta = @{ exp = 10; gp = 2; hp = 0; mp = 0 }
                    if ($direction -eq 'up') {
                        if ($task.type -in @('todo', 'daily')) { $task.completed = $true }
                        if ($task.type -eq 'habit') { $task.counterUp = [int]$task.counterUp + 1 }
                    }
                    else {
                        if ($task.type -eq 'todo') { $task.completed = $false }
                        if ($task.type -eq 'habit') { $task.counterDown = [int]$task.counterDown + 1 }
                        if ($task.type -eq 'reward') { $delta = @{ exp = 0; gp = -[double]$task.value; hp = 0; mp = 0 } }
                    }
                    $data = @{
                        delta = $delta
                        hp = $script:User.stats.hp
                        exp = $script:User.stats.exp
                        gp = $script:User.stats.gp
                        mp = $script:User.stats.mp
                        lvl = $script:User.stats.lvl
                    }
                    Send-MockJson -Stream $stream -Data $data
                    continue
                }

                if ($segments.Count -eq 5 -and $segments[2] -eq 'move' -and $segments[3] -eq 'to') {
                    Send-MockJson -Stream $stream -Data @()
                    continue
                }

                if ($segments.Count -eq 3 -and $segments[2] -eq 'checklist' -and $method -eq 'POST') {
                    $item = @{ id = 'item-' + [Guid]::NewGuid().ToString('N').Substring(0, 6); text = [string]$bodyObject.text; completed = $false }
                    $task.checklist = @($task.checklist) + @($item)
                    Send-MockJson -Stream $stream -Data $task
                    continue
                }

                if ($segments.Count -eq 4 -and $segments[2] -eq 'checklist') {
                    $itemId = $segments[3]
                    $item = @($task.checklist) | Where-Object { $_.id -eq $itemId } | Select-Object -First 1
                    if (-not $item) { Send-MockError -Stream $stream -StatusCode 404 -Message 'Checklist item not found'; continue }
                    if ($method -eq 'PUT') {
                        foreach ($property in $bodyObject.PSObject.Properties) { $item[$property.Name] = $property.Value }
                    }
                    elseif ($method -eq 'DELETE') {
                        $task.checklist = @($task.checklist | Where-Object { $_.id -ne $itemId })
                    }
                    Send-MockJson -Stream $stream -Data $task
                    continue
                }

                if ($segments.Count -eq 5 -and $segments[2] -eq 'checklist' -and $segments[4] -eq 'score') {
                    $itemId = $segments[3]
                    $item = @($task.checklist) | Where-Object { $_.id -eq $itemId } | Select-Object -First 1
                    if ($item) { $item.completed = -not [bool]$item.completed }
                    Send-MockJson -Stream $stream -Data $task
                    continue
                }

                if ($segments.Count -eq 4 -and $segments[2] -eq 'tags') {
                    $tagId = $segments[3]
                    if ($method -eq 'POST') {
                        $task.tags = @(@($task.tags) + $tagId | Select-Object -Unique)
                    }
                    else {
                        $task.tags = @($task.tags | Where-Object { $_ -ne $tagId })
                    }
                    Send-MockJson -Stream $stream -Data $task
                    continue
                }
            }

            if ($segments.Count -eq 4 -and $segments[0] -eq 'user' -and $segments[1] -eq 'class' -and $segments[2] -eq 'cast' -and $method -eq 'POST') {
                $spellId = $segments[3]
                $class = [string]$script:User.stats.class
                $spell = $null
                if ($script:MockSpells.ContainsKey($class)) { $spell = $script:MockSpells[$class][$spellId] }
                if (-not $spell) {
                    Send-MockError -Stream $stream -StatusCode 404 -Message 'Spell not found'
                    continue
                }

                $quantity = 1
                if ($bodyObject -and $bodyObject.PSObject.Properties['quantity']) { $quantity = [int]$bodyObject.quantity }
                $cost = [double]$spell.mana * $quantity
                if ([double]$script:User.stats.mp -lt $cost) {
                    Send-MockError -Stream $stream -StatusCode 400 -Message 'Not enough mana'
                    continue
                }
                $script:User.stats.mp = [double]$script:User.stats.mp - $cost

                if ($spell.target -eq 'task') {
                    $targetId = if ($query.ContainsKey('targetId')) { $query['targetId'] } else { '' }
                    $task = $script:Tasks | Where-Object { $_.id -eq $targetId } | Select-Object -First 1
                    if (-not $task) {
                        Send-MockError -Stream $stream -StatusCode 404 -Message 'Task not found'
                        continue
                    }
                    $task.value = [double]$task.value + 1
                    Send-MockJson -Stream $stream -Data @{ user = $script:User; task = $task }
                    continue
                }
                if ($spell.target -eq 'party' -or $spell.target -eq 'user') {
                    Send-MockJson -Stream $stream -Data @{ user = $script:User; partyMembers = @($script:Members) }
                    continue
                }
                if ($spell.target -eq 'tasks') {
                    Send-MockJson -Stream $stream -Data @{ user = $script:User; tasks = @($script:Tasks) }
                    continue
                }
                Send-MockJson -Stream $stream -Data @{ user = $script:User }
                continue
            }

            if ($path -eq 'groups' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data @($script:Party)
                continue
            }

            if ($segments.Count -ge 2 -and $segments[0] -eq 'groups') {
                $groupId = $segments[1]
                $group = if ($groupId -in @('party', 'party-1')) { $script:Party } else { $null }
                if (-not $group) { Send-MockError -Stream $stream -StatusCode 404 -Message 'Group not found'; continue }

                if ($segments.Count -eq 2 -and $method -eq 'GET') {
                    Send-MockJson -Stream $stream -Data $group
                    continue
                }
                if ($segments.Count -eq 3 -and $segments[2] -eq 'members') {
                    Send-MockJson -Stream $stream -Data @($script:Members)
                    continue
                }
                if ($segments.Count -eq 3 -and $segments[2] -eq 'chat' -and $method -eq 'GET') {
                    $limit = if ($query.ContainsKey('limit')) { [int]$query['limit'] } else { 50 }
                    $messages = @($script:Chat | Sort-Object { $_.timestamp } -Descending | Select-Object -First $limit)
                    Send-MockJson -Stream $stream -Data @($messages)
                    continue
                }
                if ($segments.Count -eq 3 -and $segments[2] -eq 'chat' -and $method -eq 'POST') {
                    $message = [ordered]@{ id = 'chat-' + [Guid]::NewGuid().ToString('N').Substring(0, 6); uuid = 'user-1'; text = [string]$bodyObject.message; timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); likes = @{} }
                    $script:Chat += $message
                    Send-MockJson -Stream $stream -Data $group
                    continue
                }
                if ($segments.Count -eq 4 -and $segments[2] -eq 'chat' -and $segments[3] -eq 'seen') {
                    Send-MockJson -Stream $stream -Data @{}
                    continue
                }
                if ($segments.Count -eq 5 -and $segments[2] -eq 'chat' -and $segments[4] -eq 'like') {
                    $message = $script:Chat | Where-Object { $_.id -eq $segments[3] } | Select-Object -First 1
                    if ($message) {
                        if ($message.likes.ContainsKey('user-1')) { $message.likes.Remove('user-1') } else { $message.likes['user-1'] = $true }
                    }
                    Send-MockJson -Stream $stream -Data @{}
                    continue
                }
                if ($segments.Count -eq 4 -and $segments[2] -eq 'chat' -and $method -eq 'DELETE') {
                    $script:Chat = @($script:Chat | Where-Object { $_.id -ne $segments[3] })
                    Send-MockJson -Stream $stream -Data @{}
                    continue
                }

                if ($segments.Count -ge 3 -and $segments[2] -eq 'invite') {
                    Send-MockJson -Stream $stream -Data $group
                    continue
                }
                if ($segments.Count -ge 3 -and $segments[2] -eq 'join') {
                    Send-MockJson -Stream $stream -Data $group
                    continue
                }
                if ($segments.Count -ge 3 -and $segments[2] -eq 'leave') {
                    Send-MockJson -Stream $stream -Data @{}
                    continue
                }

                if ($segments.Count -ge 4 -and $segments[2] -eq 'quests') {
                    $action = $segments[3]
                    switch ($action) {
                        'invite' {
                            $group.quest.key = $segments[4]
                            $group.quest.active = $false
                        }
                        'accept' { $group.quest.active = $false }
                        'reject' { $group.quest = @{ key = ''; active = $false; progress = @{} } }
                        'force-start' { $group.quest.active = $true }
                        'abort' { $group.quest.active = $false }
                        'cancel' { $group.quest = @{ key = ''; active = $false; progress = @{} } }
                        'leave' { }
                    }
                    Send-MockJson -Stream $stream -Data $group
                    continue
                }
            }

            if ($path -eq 'challenges/user' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data @($script:Challenges)
                continue
            }
            if ($segments.Count -ge 2 -and $segments[0] -eq 'challenges') {
                $challenge = $script:Challenges | Where-Object { $_._id -eq $segments[1] } | Select-Object -First 1
                if (-not $challenge) { Send-MockError -Stream $stream -StatusCode 404 -Message 'Challenge not found'; continue }
                if ($segments.Count -eq 2 -and $method -eq 'GET') { Send-MockJson -Stream $stream -Data $challenge; continue }
                if ($segments.Count -eq 3) {
                    switch ($segments[2]) {
                        'join' { $challenge.memberCount = [int]$challenge.memberCount + 1; Send-MockJson -Stream $stream -Data $challenge; continue }
                        'leave' { $challenge.memberCount = [Math]::Max(0, [int]$challenge.memberCount - 1); Send-MockJson -Stream $stream -Data $challenge; continue }
                        'clone' { Send-MockJson -Stream $stream -Data $challenge; continue }
                        'members' { Send-MockJson -Stream $stream -Data @($script:Members); continue }
                        'flag' { Send-MockJson -Stream $stream -Data @{}; continue }
                    }
                }
                if ($segments.Count -eq 2 -and $method -eq 'DELETE') {
                    $script:Challenges = @($script:Challenges | Where-Object { $_._id -ne $segments[1] })
                    Send-MockJson -Stream $stream -Data @{}
                    continue
                }
                if ($segments.Count -eq 4 -and $segments[2] -eq 'export' -and $segments[3] -eq 'csv') {
                    Send-MockResponse -Stream $stream -Data "name,value`nTest,1" -ContentType 'text/csv'
                    continue
                }
            }

            if ($path -eq 'inbox/messages' -and $method -eq 'GET') {
                Send-MockJson -Stream $stream -Data @($script:Inbox)
                continue
            }

            if ($segments.Count -eq 2 -and $segments[0] -eq 'members' -and $method -eq 'GET') {
                $member = $script:Members | Where-Object { $_._id -eq $segments[1] } | Select-Object -First 1
                if ($member) { Send-MockJson -Stream $stream -Data $member; continue }
                Send-MockError -Stream $stream -StatusCode 404 -Message 'Member not found'
                continue
            }

            if ($path -eq 'notifications/read' -and $method -eq 'POST') {
                foreach ($notification in $script:User.notifications) { $notification.seen = $true }
                Send-MockJson -Stream $stream -Data $script:User
                continue
            }
            if ($path -eq 'notifications/see' -and $method -eq 'POST') {
                Send-MockJson -Stream $stream -Data $script:User
                continue
            }

            if ($path -eq 'members/send-private-message' -and $method -eq 'POST') {
                Send-MockJson -Stream $stream -Data @{ message = @{ text = [string]$bodyObject.message } }
                continue
            }

            Send-MockError -Stream $stream -StatusCode 404 -Message ("Endpoint no implementado: {0} {1}" -f $method, $path)
        }
        catch {
            try { Send-MockError -Stream $stream -StatusCode 500 -Message $_.Exception.Message } catch { }
        }
        finally {
            try { $stream.Close() } catch { }
            try { $client.Close() } catch { }
        }
    }
}
finally {
    $listener.Stop()
}
