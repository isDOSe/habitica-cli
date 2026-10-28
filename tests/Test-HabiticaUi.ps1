$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$port = 18771
$serverScript = Join-Path $PSScriptRoot 'Mock-HabiticaServer.ps1'
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ('habitica-cli-ui-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempHome -Force | Out-Null

$server = $null
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

    $output = & (Get-Module habitica-cli) {
        function Test-InteractiveHost { return $true }
        function Clear-Host { }
        function Clear-HabiticaUiScreen { }
        function Test-VtSupport { return $false }

        function New-TestKey {
            param([string]$Key, [char]$Char = [char]0, [ConsoleModifiers]$Modifiers = 0)
            return [pscustomobject]@{
                Key       = [ConsoleKey]$Key
                KeyChar   = $Char
                Modifiers = $Modifiers
            }
        }

        $script:TestKeys = New-Object System.Collections.Queue
        $script:TestKeys.Enqueue((New-TestKey -Key 'DownArrow'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Enter'))
        for ($i = 0; $i -lt 4; $i++) { $script:TestKeys.Enqueue((New-TestKey -Key 'Tab')) }
        $script:TestKeys.Enqueue((New-TestKey -Key 'B' -Char 'b'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Tab'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Tab'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'L' -Char 'l'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Tab'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'S' -Char 's'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Tab'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'J' -Char 'j'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Tab'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'P' -Char 'p'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'DownArrow'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'DownArrow'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Enter'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'D1' -Char '1'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Oem2' -Char '?'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Escape'))
        $script:TestKeys.Enqueue((New-TestKey -Key 'Q' -Char 'q'))

        function Read-HabiticaUiKey {
            if ($script:TestKeys.Count -gt 0) { return $script:TestKeys.Dequeue() }
            return (New-TestKey -Key 'Escape')
        }

        Start-HabiticaUi
    } 6>&1 | Out-String

    $checks = @(
        @{ Name = 'Cabecera'; Pattern = 'H A B I T I C A' },
        @{ Name = 'Pestana Hoy'; Pattern = 'HOY' },
        @{ Name = 'Pestana Party'; Pattern = 'PARTY' },
        @{ Name = 'Pestana Chat'; Pattern = 'CHAT' },
        @{ Name = 'Pestana Quest'; Pattern = 'QUEST' },
        @{ Name = 'Pestana Retos'; Pattern = 'RETOS' },
        @{ Name = 'Pestana Perfil'; Pattern = 'Atributos' },
        @{ Name = 'Pestana Poderes'; Pattern = 'PODERES' },
        @{ Name = 'Accion poder'; Pattern = 'Poder usado' },
        @{ Name = 'Accion completar'; Pattern = 'Completada:' },
        @{ Name = 'Accion comprar'; Pattern = 'Deshecha:' },
        @{ Name = 'Accion like'; Pattern = 'Me gusta actualizado' },
        @{ Name = 'Accion quest'; Pattern = 'Quest iniciada' },
        @{ Name = 'Accion reto'; Pattern = 'unido al reto' },
        @{ Name = 'Salida'; Pattern = 'Hasta luego' }
    )

    $failed = 0
    foreach ($check in $checks) {
        if ($output -match [regex]::Escape($check.Pattern)) {
            Write-Host ("  PASS  {0}" -f $check.Name) -ForegroundColor Green
        }
        else {
            Write-Host ("  FAIL  {0}" -f $check.Name) -ForegroundColor Red
            $failed++
        }
    }

    if ($output -match 'Error:') {
        Write-Host '  FAIL  La TUI mostro un error interno' -ForegroundColor Red
        $failed++
    }
    else {
        Write-Host '  PASS  La TUI no mostro errores internos' -ForegroundColor Green
    }

    # Regresion: el frame nunca debe superar la altura del terminal.
    foreach ($testHeight in @(15, 20, 24, 30)) {
        $frameOutput = & (Get-Module habitica-cli) {
            param($frameHeight)

            function Test-InteractiveHost { return $true }
            function Clear-Host { }
            function Clear-HabiticaUiScreen { }
            function Test-VtSupport { return $false }
            function Get-TerminalWidth { return 100 }
            function Get-TerminalHeight { return $frameHeight }
            function New-TestKey {
                param([string]$Key, [char]$Char = [char]0)
                return [pscustomobject]@{ Key = [ConsoleKey]$Key; KeyChar = $Char; Modifiers = 0 }
            }

            $script:LayoutKeys = New-Object System.Collections.Queue
            $script:LayoutKeys.Enqueue((New-TestKey -Key 'Q' -Char 'q'))
            function Read-HabiticaUiKey {
                if ($script:LayoutKeys.Count -gt 0) { return $script:LayoutKeys.Dequeue() }
                return (New-TestKey -Key 'Escape')
            }

            Start-HabiticaUi
        } $testHeight 6>&1 | Out-String

        $frameLines = $frameOutput -split "`r?`n"
        $exitIndex = -1
        for ($i = 0; $i -lt $frameLines.Count; $i++) {
            if ($frameLines[$i] -match 'Hasta luego') { $exitIndex = $i; break }
        }
        $drawn = [Math]::Max(0, $exitIndex - 1)
        if ($drawn -le ($testHeight - 1)) {
            Write-Host ("  PASS  Frame de {0} lineas cabe en altura {1}" -f $drawn, $testHeight) -ForegroundColor Green
        }
        else {
            Write-Host ("  FAIL  Frame de {0} lineas desborda altura {1}" -f $drawn, $testHeight) -ForegroundColor Red
            $failed++
        }
    }

    if ($failed -gt 0) { exit 1 }
    Write-Host '  TUI OK' -ForegroundColor Green
}
catch {
    Write-Host ("ERROR FATAL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
finally {
    Get-Module habitica-cli | Remove-Module -Force -ErrorAction SilentlyContinue
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

