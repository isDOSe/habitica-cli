Set-StrictMode -Version 1.0

# =============================================================================
#  Habitica CLI - Utilidades comunes
#  Compatible con Windows PowerShell 5.1 y PowerShell 7+.
# =============================================================================

$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:Esc = [char]27
$script:VtEnabled = $false
$script:UseColor = $false
$script:AsciiMode = $true

$script:Ansi = @{
    Reset   = "$($script:Esc)[0m"
    Bold    = "$($script:Esc)[1m"
    Dim     = "$($script:Esc)[2m"
    Italic  = "$($script:Esc)[3m"
    Under   = "$($script:Esc)[4m"
    Reverse = "$($script:Esc)[7m"
    Gold    = "$($script:Esc)[1;33m"
    Yellow  = "$($script:Esc)[1;33m"
    Orange  = "$($script:Esc)[1;31m"
    Red     = "$($script:Esc)[1;31m"
    Green   = "$($script:Esc)[1;32m"
    Cyan    = "$($script:Esc)[1;36m"
    Blue    = "$($script:Esc)[1;34m"
    Magenta = "$($script:Esc)[1;35m"
    White   = "$($script:Esc)[1;37m"
    Gray    = "$($script:Esc)[2;37m"
    Black   = "$($script:Esc)[1;30m"
}

$script:MarkupTagNames = @($script:Ansi.Keys | Where-Object { $_ -ne 'Reset' } | Sort-Object -Descending)
$script:MarkupPattern = '(?i)~/~|~(' + (($script:MarkupTagNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')~'

function Enable-VirtualTerminal {
    if ($script:VtEnabled) { return }
    $script:VtEnabled = $true

    try {
        if ($Host.UI.SupportsVirtualTerminal) { return }
    }
    catch { }

    try {
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            if (-not ('HabiticaCli.NativeConsole' -as [type])) {
                Add-Type -Namespace 'HabiticaCli' -Name 'NativeConsole' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
            }
            $handle = [HabiticaCli.NativeConsole]::GetStdHandle(-11)
            $mode = [uint32]0
            if ([HabiticaCli.NativeConsole]::GetConsoleMode($handle, [ref]$mode)) {
                [HabiticaCli.NativeConsole]::SetConsoleMode($handle, ($mode -bor 0x0004)) | Out-Null
            }
        }
    }
    catch {
        # Sin VT simplemente se usa texto plano.
    }
}

function Test-VtSupport {
    if ($env:NO_COLOR) { return $false }
    if ($env:HABITICA_CLI_NO_COLOR -eq '1') { return $false }

    try {
        if ([Console]::IsOutputRedirected) { return $false }
    }
    catch { }

    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) { return $true }
        if ($Host.UI.SupportsVirtualTerminal) { return $true }
    }
    catch { }

    return $false
}

function Initialize-HabiticaConsole {
    try {
        # Mejora la visualizacion de nombres con acentos o emojis.
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch { }

    if (Test-VtSupport) {
        Enable-VirtualTerminal
        $script:UseColor = $true
    }
    else {
        $script:UseColor = $false
    }
}

function Set-HabiticaCursorVisible {
    param([bool]$Visible)
    try { [Console]::CursorVisible = $Visible } catch { }
}

function Test-InteractiveHost {
    try {
        if ([Console]::IsInputRedirected) { return $false }
        if ([Console]::IsOutputRedirected) { return $false }
    }
    catch { }
    if ($Host.Name -notmatch 'ConsoleHost') { return $false }
    return $true
}

function Get-TerminalWidth {
    param([int]$Default = 86, [int]$Minimum = 50, [int]$Maximum = 110)

    if ($env:HABITICA_CLI_WIDTH -match '^\d+$') {
        $forced = [int]$env:HABITICA_CLI_WIDTH
        if ($forced -ge $Minimum) { return [Math]::Min($forced, $Maximum) }
    }

    $candidates = @()
    try {
        $value = [int]$Host.UI.RawUI.WindowSize.Width
        if ($value -gt 0) { $candidates += $value }
    }
    catch { }
    try {
        $value = [int][Console]::WindowWidth
        if ($value -gt 0) { $candidates += $value }
    }
    catch { }

    $width = $Default
    if ($candidates.Count -gt 0) {
        # El menor valor evita que un host que reporta el buffer en vez de la
        # ventana dibuje paneles mas anchos que la pantalla.
        $width = [int](($candidates | Measure-Object -Minimum).Minimum)
    }
    if ($width -lt $Minimum) { return $Minimum }
    if ($width -gt $Maximum) { return $Maximum }
    return $width
}

function Get-TerminalHeight {
    param([int]$Default = 30, [int]$Minimum = 15)

    if ($env:HABITICA_CLI_HEIGHT -match '^\d+$') {
        $forced = [int]$env:HABITICA_CLI_HEIGHT
        if ($forced -ge $Minimum) { return $forced }
    }

    $candidates = @()
    try {
        $value = [int]$Host.UI.RawUI.WindowSize.Height
        if ($value -gt 0) { $candidates += $value }
    }
    catch { }
    try {
        $value = [int][Console]::WindowHeight
        if ($value -gt 0) { $candidates += $value }
    }
    catch { }

    $height = $Default
    if ($candidates.Count -gt 0) {
        $height = [int](($candidates | Measure-Object -Minimum).Minimum)
    }
    if ($height -lt $Minimum) { return $Minimum }
    return $height
}

# -----------------------------------------------------------------------------
#  Markup simple: ~gold~texto~/~  ->  secuencias ANSI
# -----------------------------------------------------------------------------

function Convert-HabiticaMarkup {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if (-not $script:UseColor) {
        return [regex]::Replace($Text, $script:MarkupPattern, '')
    }

    $colored = [regex]::Replace($Text, '~([a-zA-Z]+)~', {
        param($match)
        $name = $match.Groups[1].Value.ToLowerInvariant()
        if ($script:Ansi.ContainsKey($name)) { return $script:Ansi[$name] }
        return $match.Value
    })
    return $colored.Replace('~/~', $script:Ansi.Reset)
}

function Get-HabiticaCodePointWidth {
    param([int]$CodePoint)

    if ($CodePoint -le 0) { return 0 }
    if ($CodePoint -lt 32 -or ($CodePoint -ge 0x7F -and $CodePoint -lt 0xA0)) { return 0 }

    # Combinantes, selectores de variacion y ZWJ.
    if (($CodePoint -ge 0x0300 -and $CodePoint -le 0x036F) -or
        ($CodePoint -ge 0x1AB0 -and $CodePoint -le 0x1AFF) -or
        ($CodePoint -ge 0x1DC0 -and $CodePoint -le 0x1DFF) -or
        ($CodePoint -ge 0x20D0 -and $CodePoint -le 0x20FF) -or
        ($CodePoint -ge 0xFE00 -and $CodePoint -le 0xFE0F) -or
        ($CodePoint -ge 0xFE20 -and $CodePoint -le 0xFE2F) -or
        $CodePoint -eq 0x200D -or
        ($CodePoint -ge 0x1F3FB -and $CodePoint -le 0x1F3FF)) {
        return 0
    }

    # CJK, hangul, fullwidth y emojis: dos columnas.
    if (($CodePoint -ge 0x1100 -and $CodePoint -le 0x115F) -or
        ($CodePoint -ge 0x2E80 -and $CodePoint -le 0xA4CF) -or
        ($CodePoint -ge 0xAC00 -and $CodePoint -le 0xD7A3) -or
        ($CodePoint -ge 0xF900 -and $CodePoint -le 0xFAFF) -or
        ($CodePoint -ge 0xFE10 -and $CodePoint -le 0xFE19) -or
        ($CodePoint -ge 0xFE30 -and $CodePoint -le 0xFE6F) -or
        ($CodePoint -ge 0xFF00 -and $CodePoint -le 0xFF60) -or
        ($CodePoint -ge 0xFFE0 -and $CodePoint -le 0xFFE6) -or
        ($CodePoint -ge 0x1F000 -and $CodePoint -le 0x1FAFF) -or
        ($CodePoint -ge 0x2600 -and $CodePoint -le 0x27BF) -or
        ($CodePoint -ge 0x2B00 -and $CodePoint -le 0x2BFF)) {
        return 2
    }

    return 1
}

function Get-HabiticaVisibleLength {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $plain = [regex]::Replace($Text, $script:MarkupPattern, '')
    $plain = [regex]::Replace($plain, "$($script:Esc)\[[0-9;]*m", '')

    $width = 0
    $i = 0
    while ($i -lt $plain.Length) {
        try {
            $codePoint = [char]::ConvertToUtf32($plain, $i)
            $width += Get-HabiticaCodePointWidth -CodePoint $codePoint
            if ([char]::IsHighSurrogate($plain[$i]) -and ($i + 1) -lt $plain.Length) { $i += 2 }
            else { $i++ }
        }
        catch {
            $width++
            $i++
        }
    }
    return $width
}

function Truncate-HabiticaText {
    param(
        [AllowNull()][string]$Text,
        [int]$Width,
        [string]$Ellipsis = '...'
    )

    if ($null -eq $Text) { return '' }
    if ($Width -le 0) { return '' }
    if ((Get-HabiticaVisibleLength $Text) -le $Width) { return $Text }

    $ellipsisLength = Get-HabiticaVisibleLength $Ellipsis
    if ($Width -le $ellipsisLength) { return $Ellipsis.Substring(0, [Math]::Min($Width, $Ellipsis.Length)) }

    $limit = $Width - $ellipsisLength
    $builder = New-Object System.Text.StringBuilder
    $visible = 0
    $i = 0
    while ($i -lt $Text.Length -and $visible -lt $limit) {
        if ($Text[$i] -eq '~') {
            $close = $Text.IndexOf('~', $i + 1)
            if ($close -gt $i + 1) {
                $tag = $Text.Substring($i, $close - $i + 1)
                if ($tag -eq '~/~' -or $script:Ansi.ContainsKey($tag.Substring(1, $tag.Length - 2))) {
                    [void]$builder.Append($tag)
                    $i = $close + 1
                    continue
                }
            }
        }

        $charWidth = 1
        $charLength = 1
        try {
            $codePoint = [char]::ConvertToUtf32($Text, $i)
            $charWidth = Get-HabiticaCodePointWidth -CodePoint $codePoint
            if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $Text.Length) { $charLength = 2 }
        }
        catch { }

        if (($visible + $charWidth) -gt $limit) { break }

        [void]$builder.Append($Text.Substring($i, $charLength))
        $visible += $charWidth
        $i += $charLength
    }
    [void]$builder.Append($Ellipsis)
    return $builder.ToString()
}

function Pad-HabiticaText {
    param(
        [AllowNull()][string]$Text,
        [int]$Width,
        [string]$Align = 'Left'
    )

    if ($null -eq $Text) { $Text = '' }
    $Text = Truncate-HabiticaText -Text $Text -Width $Width
    $missing = $Width - (Get-HabiticaVisibleLength $Text)
    if ($missing -le 0) { return $Text }

    switch ($Align.ToLowerInvariant()) {
        'right' { return ((' ' * $missing) + $Text) }
        'center' {
            $left = [int][Math]::Floor($missing / 2)
            $right = $missing - $left
            return ((' ' * $left) + $Text + (' ' * $right))
        }
        default { return ($Text + (' ' * $missing)) }
    }
}

function Write-HabiticaLine {
    param(
        [AllowNull()][string]$Text = '',
        [switch]$NoNewline
    )

    $line = Convert-HabiticaMarkup $Text
    if ($script:UseColor -and $line -match [char]27) { $line += $script:Ansi.Reset }

    if ($NoNewline) { Write-Host $line -NoNewline }
    else { Write-Host $line }
}

function Write-HabiticaBlank {
    param([int]$Count = 1)
    for ($i = 0; $i -lt $Count; $i++) { Write-Host '' }
}

function Write-HabiticaOk {
    param([string]$Text)
    Write-HabiticaLine "  ~green~[OK]~/~ $Text"
}

function Write-HabiticaInfo {
    param([string]$Text)
    Write-HabiticaLine "  ~cyan~[i]~/~ $Text"
}

function Write-HabiticaWarn {
    param([string]$Text)
    Write-HabiticaLine "  ~gold~[!]~/~ $Text"
}

function Write-HabiticaError {
    param([string]$Text)
    Write-HabiticaLine "  ~red~[X]~/~ $Text"
}

function ConvertFrom-HabiticaMarkdown {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $result = $Text
    $result = [regex]::Replace($result, '\[([^\]]+)\]\([^\)]+\)', '$1')
    $result = [regex]::Replace($result, '\*\*([^\*]+)\*\*', '$1')
    $result = [regex]::Replace($result, '__([^_]+)__', '$1')
    $result = [regex]::Replace($result, '\*([^\*]+)\*', '$1')
    $result = [regex]::Replace($result, '_([^_]+)_', '$1')
    $result = [regex]::Replace($result, '`([^`]+)`', '$1')
    $result = [regex]::Replace($result, '~~([^~]+)~~', '$1')
    return $result
}

function Wrap-HabiticaText {
    param(
        [AllowNull()][string]$Text,
        [int]$Width = 60
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return @('') }
    if ($Width -lt 10) { $Width = 10 }

    $words = [regex]::Split($Text.Trim(), '\s+')
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($word in $words) {
        if ($current.Length -eq 0) {
            $current = $word
        }
        elseif (($current.Length + 1 + $word.Length) -le $Width) {
            $current += ' ' + $word
        }
        else {
            $lines.Add($current)
            $current = $word
        }
    }
    if ($current.Length -gt 0) { $lines.Add($current) }
    if ($lines.Count -eq 0) { $lines.Add('') }
    return $lines.ToArray()
}

function Get-HabiticaObjectValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-HabiticaArray {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Format-HabiticaNumber {
    param(
        [AllowNull()]$Value,
        [int]$Decimals = 0,
        [string]$Suffix = ''
    )

    if ($null -eq $Value) { return '-' }
    try {
        $number = [double]$Value
    }
    catch { return [string]$Value }

    if ($Decimals -gt 0) {
        return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:N$Decimals}", $number) + $Suffix)
    }
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:N0}', $number) + $Suffix)
}

function ConvertTo-HabiticaDate {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.Date }
    if ($Value -is [datetimeoffset]) { return $Value.Date }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    if ($text.Length -ge 10) {
        $candidate = $text.Substring(0, 10)
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($candidate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.Date
        }
    }

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($text, [ref]$parsed)) { return $parsed.Date }
    return $null
}

function Format-HabiticaDateHuman {
    param([AllowNull()]$Value)

    $date = ConvertTo-HabiticaDate $Value
    if (-not $date) { return '-' }

    $today = (Get-Date).Date
    $days = [int]($date - $today).TotalDays

    if ($days -lt 0) {
        if ($days -eq -1) { return 'ayer' }
        return ('hace {0}d' -f [Math]::Abs($days))
    }
    if ($days -eq 0) { return 'hoy' }
    if ($days -eq 1) { return 'manana' }
    if ($days -le 6) {
        $names = @('dom', 'lun', 'mar', 'mie', 'jue', 'vie', 'sab')
        return $names[[int]$date.DayOfWeek]
    }
    return $date.ToString('dd/MM')
}

function Format-HabiticaTimestamp {
    param(
        [AllowNull()]$Timestamp,
        [switch]$WithTime
    )

    if ($null -eq $Timestamp) { return '-' }

    $date = $null
    try {
        if ($Timestamp -is [datetime]) { $date = $Timestamp.ToLocalTime() }
        elseif ($Timestamp -is [datetimeoffset]) { $date = $Timestamp.ToLocalTime().DateTime }
        elseif ($Timestamp -is [string] -and $Timestamp -match '^\d{4}-\d{2}-\d{2}T') { $date = [DateTimeOffset]::Parse([string]$Timestamp, [System.Globalization.CultureInfo]::InvariantCulture).LocalDateTime }
        elseif ([double]$Timestamp -gt 100000000000) { $date = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Timestamp).LocalDateTime }
        elseif ([double]$Timestamp -gt 1000000000) { $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$Timestamp).LocalDateTime }
        else { $date = ([datetime]$Timestamp).ToLocalTime() }
    }
    catch { return [string]$Timestamp }

    if ($WithTime) { return $date.ToString('dd/MM HH:mm') }
    return $date.ToString('dd/MM')
}

function New-HabiticaProgressBar {
    param(
        [AllowNull()]$Current,
        [AllowNull()]$Maximum,
        [int]$Width = 14,
        [string]$FullChar = '#',
        [string]$EmptyChar = '-',
        [string]$Color = 'green'
    )

    $cur = 0.0
    $max = 0.0
    try { $cur = [double]$Current } catch { }
    try { $max = [double]$Maximum } catch { }

    $ratio = 0.0
    if ($max -gt 0) { $ratio = $cur / $max }
    if ($ratio -lt 0) { $ratio = 0 }
    if ($ratio -gt 1) { $ratio = 1 }

    $filled = [int][Math]::Round($ratio * $Width)
    if ($filled -gt $Width) { $filled = $Width }
    if ($filled -lt 0) { $filled = 0 }

    $bar = ('#' * $filled) + ('-' * ($Width - $filled))
    return "~${Color}~[$bar]~/~"
}

function Confirm-HabiticaAction {
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Force
    )

    if ($Force) { return $true }
    if (-not (Test-InteractiveHost)) { return $false }

    $answer = Read-Host ("  {0} [s/N]" -f $Message)
    return ($answer -match '^(s|si|si|y|yes)$')
}

function Get-HabiticaPropertyText {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = ''
    )

    $value = Get-HabiticaObjectValue -Object $Object -Name $Name -Default $null
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $Default }
    return [string]$value
}
