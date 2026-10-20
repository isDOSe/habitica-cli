Set-StrictMode -Version 1.0

$script:ModuleRoot = $PSScriptRoot

$files = @(
    'src\00-Common.ps1'
    'src\10-Config.ps1'
    'src\20-Api.ps1'
    'src\30-State.ps1'
    'src\40-Tasks.ps1'
    'src\50-Tags.ps1'
    'src\60-User.ps1'
    'src\70-Groups.ps1'
    'src\80-Challenges.ps1'
    'src\90-Render.ps1'
    'src\95-Cli.ps1'
    'src\98-Ui.ps1'
)

foreach ($file in $files) {
    $path = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "No se encontro el archivo interno: $path"
    }
    . $path
}

Initialize-HabiticaConsole
Initialize-HabiticaConfig
Reset-HabiticaUiData

$ExecutionContext.SessionState.Module.OnRemove = {
    try { Set-HabiticaCursorVisible $true } catch { }
    try { Set-Alias -Name h -Value Get-History -Option AllScope -Scope Global -Force -ErrorAction SilentlyContinue } catch { }
}

try {
    # 'h' es un alias integrado de Get-History. Solo se reemplaza si no hay
    # un alias personalizado del usuario; 'habitica' siempre esta disponible.
    $existingAlias = Get-Alias -Name h -ErrorAction SilentlyContinue
    if (-not $existingAlias -or $existingAlias.Definition -in @('Get-History', 'habitica')) {
        Set-Alias -Name h -Value habitica -Option AllScope -Scope Global -Force -ErrorAction Stop
    }
}
catch { }

Export-ModuleMember -Function @(
    'habitica'
    'Invoke-HabiticaCli'

    'Get-HabiticaConfig', 'Set-HabiticaConfig', 'Reset-HabiticaConfig',
    'Test-HabiticaConnection', 'Invoke-HabiticaSetup', 'Clear-HabiticaLocalCache',
    'Invoke-HabiticaApi'

    'Get-HabiticaTask', 'New-HabiticaTask', 'Set-HabiticaTask', 'Remove-HabiticaTask',
    'Complete-HabiticaTask', 'Invoke-HabiticaTaskScore', 'Move-HabiticaTask',
    'Clear-HabiticaCompletedTodo'

    'Get-HabiticaChecklistItem', 'Add-HabiticaChecklistItem', 'Set-HabiticaChecklistItem',
    'Complete-HabiticaChecklistItem', 'Remove-HabiticaChecklistItem'

    'Get-HabiticaTag', 'New-HabiticaTag', 'Set-HabiticaTag', 'Remove-HabiticaTag',
    'Move-HabiticaTag', 'Resolve-HabiticaTagId', 'Add-HabiticaTaskTag', 'Remove-HabiticaTaskTag'

    'Get-HabiticaUser', 'Get-HabiticaStats', 'Get-HabiticaNotification',
    'Set-HabiticaNotificationStatus', 'Get-HabiticaInbox', 'Send-HabiticaPrivateMessage'

    'Get-HabiticaGroup', 'Get-HabiticaGroups', 'Get-HabiticaParty', 'Get-HabiticaPartyMembers',
    'Get-HabiticaMember', 'New-HabiticaParty', 'Join-HabiticaGroup', 'Exit-HabiticaGroup',
    'Send-HabiticaPartyInvite', 'Remove-HabiticaPartyMember',
    'Get-HabiticaChat', 'Send-HabiticaChatMessage', 'Add-HabiticaChatLike',
    'Set-HabiticaChatSeen', 'Remove-HabiticaChatMessage',
    'Get-HabiticaQuest', 'Get-HabiticaQuestInfo', 'Invoke-HabiticaQuestAction'

    'Get-HabiticaChallengeList', 'Get-HabiticaChallenge', 'New-HabiticaChallenge',
    'Set-HabiticaChallenge', 'Join-HabiticaChallenge', 'Exit-HabiticaChallenge',
    'Remove-HabiticaChallenge', 'Copy-HabiticaChallenge', 'Export-HabiticaChallenge',
    'Select-HabiticaChallengeWinner', 'Get-HabiticaChallengeMembers'

    'Show-HabiticaDashboard', 'Show-HabiticaStats', 'Show-HabiticaProfile',
    'Show-HabiticaTaskList', 'Show-HabiticaAllTasks', 'Show-HabiticaTaskDetail',
    'Show-HabiticaParty', 'Show-HabiticaChat', 'Show-HabiticaQuest',
    'Show-HabiticaQuestList', 'Show-HabiticaTags', 'Show-HabiticaNotifications',
    'Show-HabiticaInbox', 'Show-HabiticaChallengeList', 'Show-HabiticaChallengeDetail',
    'Show-HabiticaCliHelp', 'Show-HabiticaVersion', 'Start-HabiticaUi'
)

