@{
    RootModule           = 'habitica-cli.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'd7f1c2a4-6b1e-4c8f-9a3d-5e2b7c9f0a11'
    Author               = 'Habitica CLI'
    CompanyName          = 'Habitica CLI'
    Copyright            = '(c) 2026 Habitica CLI'
    Description          = 'Centro de mando ASCII para administrar Habitica desde PowerShell: tareas, habitos, diarias, recompensas, party, chat, quests y retos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'habitica', 'Invoke-HabiticaCli'
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
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Habitica', 'CLI', 'TUI', 'Tasks', 'Productivity', 'RPG')
            ProjectUri   = 'https://github.com/isDOSe/habitica-powershell'
            LicenseUri   = 'https://raw.githubusercontent.com/isDOSe/habitica-powershell/main/LICENSE'
            ReleaseNotes = 'v1.0.0: cliente completo con TUI, tareas, habitos, diarias, recompensas, etiquetas, party, chat, quests, retos y API generica.'
        }
    }
}

