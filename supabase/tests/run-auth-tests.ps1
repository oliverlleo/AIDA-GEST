[CmdletBinding()]
param(
    [string]$PostgresBin,
    [string]$RecoveryDirectory,
    [string]$PasswordFile,
    [string]$DatabaseName = ('aida_auth_review_' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')),
    [int]$Port = 54329,
    [string]$AdminUser = 'aida_test_admin'
)
$ErrorActionPreference = 'Stop'
$taskRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $PostgresBin) { $PostgresBin = [IO.Path]::GetFullPath((Join-Path $taskRepo '..\tools\pg17\pgsql\bin')) }
if (-not $RecoveryDirectory) { $RecoveryDirectory = [IO.Path]::GetFullPath((Join-Path $taskRepo '..\recovery\database')) }
if (-not $PasswordFile) { $PasswordFile = [IO.Path]::GetFullPath((Join-Path $taskRepo '..\pg-test-password.txt')) }
if ($DatabaseName -notmatch '^aida_auth_review_[a-zA-Z0-9_]+$') { throw 'Test database name must start with aida_auth_review_; no existing database is reset or deleted.' }
$taskPsql = Join-Path $PostgresBin 'psql.exe'
$taskCreatedb = Join-Path $PostgresBin 'createdb.exe'
$taskPreviousPassword = $env:PGPASSWORD
$taskLogs = [IO.Path]::GetFullPath((Join-Path $taskRepo ('..\sql-auth-test-results\' + $DatabaseName)))
New-Item -ItemType Directory -Path $taskLogs -Force | Out-Null

function Invoke-AuthConcurrency {
    $taskSetupLog = Join-Path $taskLogs 'concurrency-setup.log'
    & $taskPsql -h 127.0.0.1 -p $Port -U $AdminUser -d $DatabaseName -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'auth-concurrency-setup.sql') -o $taskSetupLog
    if ($LASTEXITCODE -ne 0) { throw "Concurrency setup failed. Inspect $taskSetupLog" }
    $taskFirstLog = Join-Path $taskLogs 'concurrency-first.log'
    $taskSecondLog = Join-Path $taskLogs 'concurrency-second.log'
    $taskBaseArgs = @('-h','127.0.0.1','-p',$Port,'-U',$AdminUser,'-d',$DatabaseName,'-v','ON_ERROR_STOP=1','-q','-A','-t','-f')
    $taskFirstSQL = Join-Path $PSScriptRoot 'auth-concurrency-first.sql'
    $taskFirstProcess = Start-Process -FilePath $taskPsql -ArgumentList ($taskBaseArgs + ('"' + $taskFirstSQL + '"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput $taskFirstLog -RedirectStandardError (Join-Path $taskLogs 'concurrency-first.err.log')
    $taskDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $taskMarkerSeen = $false
    while ([DateTime]::UtcNow -lt $taskDeadline -and -not $taskFirstProcess.HasExited) {
        if ((Test-Path -LiteralPath $taskFirstLog) -and (Get-Content -LiteralPath $taskFirstLog -Raw) -match '(?m)^LOCK_HELD\r?$') { $taskMarkerSeen = $true; break }
        Start-Sleep -Milliseconds 20
    }
    if (-not $taskMarkerSeen) { throw "First acceptance did not hold its transaction as expected. Inspect $taskFirstLog" }
    $taskSecondSQL = Join-Path $PSScriptRoot 'auth-concurrency-second.sql'
    $taskSecondProcess = Start-Process -FilePath $taskPsql -ArgumentList ($taskBaseArgs + ('"' + $taskSecondSQL + '"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput $taskSecondLog -RedirectStandardError (Join-Path $taskLogs 'concurrency-second.err.log')
    $taskLockObserved = $false
    while (-not $taskFirstProcess.HasExited -and [DateTime]::UtcNow -lt $taskDeadline) {
        $taskProbe = & $taskPsql -h 127.0.0.1 -p $Port -U $AdminUser -d $DatabaseName -v ON_ERROR_STOP=1 -q -A -t -c "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND application_name='aida_auth_accept_second' AND wait_event_type='Lock');"
        if ($LASTEXITCODE -ne 0) { throw 'Concurrency lock observation failed.' }
        if (($taskProbe -join '').Trim() -eq 't') { $taskLockObserved = $true; break }
        Start-Sleep -Milliseconds 20
    }
    if (-not $taskFirstProcess.WaitForExit(10000) -or -not $taskSecondProcess.WaitForExit(10000)) { throw 'Concurrent local acceptance did not finish in time.' }
    if ($taskFirstProcess.ExitCode -ne 0 -or $taskSecondProcess.ExitCode -ne 0) { throw 'Concurrent acceptance failed; inspect concurrency worker logs.' }
    if (-not $taskLockObserved) { throw 'No actual row-lock contention observed; concurrent test cannot claim coverage.' }
    foreach ($taskWorkerLog in @($taskFirstLog,$taskSecondLog)) {
        if ((Get-Content -LiteralPath $taskWorkerLog -Raw) -notmatch '(?m)^20000000-0000-4000-8000-000000000002\r?$') { throw "Acceptance did not return the expected same workspace. Inspect $taskWorkerLog" }
    }
    $taskVerifyLog = Join-Path $taskLogs 'concurrency.log'
    & $taskPsql -h 127.0.0.1 -p $Port -U $AdminUser -d $DatabaseName -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'auth-concurrency-verify.sql') -o $taskVerifyLog
    if ($LASTEXITCODE -ne 0) { throw "Concurrency invariants failed. Inspect $taskVerifyLog" }
    Write-Output 'PASS concurrency (two sessions, observed lock wait, same result)'
}

function Invoke-SqlRowRace([string]$Prefix,[string]$SecondApplication,[string]$SecondMarker) {
    $taskRaceArgs = @('-h','127.0.0.1','-p',$Port,'-U',$AdminUser,'-d',$DatabaseName,'-v','ON_ERROR_STOP=1','-q','-A','-t','-f')
    $taskRaceSetup = Join-Path $PSScriptRoot ($Prefix+'-setup.sql')
    & $taskPsql @($taskRaceArgs + $taskRaceSetup) -o (Join-Path $taskLogs ($Prefix+'-setup.log'))
    if ($LASTEXITCODE -ne 0) { throw "Race setup failed: $Prefix" }
    $taskRaceFirstLog = Join-Path $taskLogs ($Prefix+'-first.log')
    $taskRaceSecondLog = Join-Path $taskLogs ($Prefix+'-second.log')
    $taskRaceFirstSQL = Join-Path $PSScriptRoot ($Prefix+'-first.sql')
    $taskRaceSecondSQL = Join-Path $PSScriptRoot ($Prefix+'-second.sql')
    $taskRaceFirst = Start-Process -FilePath $taskPsql -ArgumentList ($taskRaceArgs + ('"'+$taskRaceFirstSQL+'"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput $taskRaceFirstLog -RedirectStandardError (Join-Path $taskLogs ($Prefix+'-first.err.log'))
    $taskRaceDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $taskRaceMarkerSeen = $false
    while ([DateTime]::UtcNow -lt $taskRaceDeadline -and -not $taskRaceFirst.HasExited) {
        if ((Test-Path -LiteralPath $taskRaceFirstLog) -and (Get-Content -LiteralPath $taskRaceFirstLog -Raw) -match '(?m)^LOCK_HELD\r?$') { $taskRaceMarkerSeen=$true;break }
        Start-Sleep -Milliseconds 20
    }
    if (-not $taskRaceMarkerSeen) { throw "First race connection did not acquire its lock: $Prefix" }
    $taskRaceSecond = Start-Process -FilePath $taskPsql -ArgumentList ($taskRaceArgs + ('"'+$taskRaceSecondSQL+'"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput $taskRaceSecondLog -RedirectStandardError (Join-Path $taskLogs ($Prefix+'-second.err.log'))
    $taskRaceLockObserved = $false
    while (-not $taskRaceFirst.HasExited -and [DateTime]::UtcNow -lt $taskRaceDeadline) {
        $taskRaceProbe = & $taskPsql -h 127.0.0.1 -p $Port -U $AdminUser -d $DatabaseName -v ON_ERROR_STOP=1 -q -A -t -c "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND application_name='$SecondApplication' AND wait_event_type='Lock');"
        if ($LASTEXITCODE -ne 0) { throw "Race observation failed: $Prefix" }
        if (($taskRaceProbe -join '').Trim() -eq 't') { $taskRaceLockObserved=$true;break }
        Start-Sleep -Milliseconds 20
    }
    if (-not $taskRaceFirst.WaitForExit(10000) -or -not $taskRaceSecond.WaitForExit(10000)) { throw "Race did not finish: $Prefix" }
    if ($taskRaceFirst.ExitCode -ne 0 -or $taskRaceSecond.ExitCode -ne 0) { throw "Race connection failed: $Prefix" }
    if (-not $taskRaceLockObserved) { throw "No actual lock wait observed: $Prefix" }
    if ((Get-Content -LiteralPath $taskRaceSecondLog -Raw) -notmatch ('(?m)^'+[regex]::Escape($SecondMarker)+'\r?$')) { throw "Second race connection did not reject its stale write: $Prefix" }
    & $taskPsql @($taskRaceArgs + (Join-Path $PSScriptRoot ($Prefix+'-verify.sql'))) -o (Join-Path $taskLogs ($Prefix+'-verify.log'))
    if ($LASTEXITCODE -ne 0) { throw "Race invariant failed: $Prefix" }
    Write-Output "PASS $Prefix (two sessions, observed lock wait, one effect and one conflict)"
}

try {
    $env:PGPASSWORD = [IO.File]::ReadAllText($PasswordFile).Trim()
    & $taskCreatedb -h 127.0.0.1 -p $Port -U $AdminUser $DatabaseName
    if ($LASTEXITCODE -ne 0) { throw 'Could not create a fresh test database. Existing databases are never reused or deleted.' }
    $taskStages = @(
        @{Name='bootstrap'; File=(Join-Path $RecoveryDirectory 'LOCAL_TEST_BOOTSTRAP.sql')},
        @{Name='baseline'; File=(Join-Path $RecoveryDirectory 'baseline.sql')},
        @{Name='fixtures'; File=(Join-Path $PSScriptRoot 'auth-fixtures.sql')},
        @{Name='migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261013141221_supabase_auth_workspace_memberships.sql')},
        @{Name='current_role_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261014214111_current_role_operational_guards.sql')},
        @{Name='full_audit_baseline'; File=(Join-Path $PSScriptRoot 'auth-full-audit-baseline.sql')},
        @{Name='full_audit_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261015194150_full_authorization_audit.sql')},
        @{Name='full_audit_runtime_owner'; File=(Join-Path $PSScriptRoot 'auth-full-audit-runtime-owner.sql')},
        @{Name='security'; File=(Join-Path $PSScriptRoot 'auth-security.sql')},
        @{Name='delivery'; File=(Join-Path $PSScriptRoot 'auth-invitation-delivery.sql')},
        @{Name='operations'; File=(Join-Path $PSScriptRoot 'auth-operations.sql')},
        @{Name='current_role'; File=(Join-Path $PSScriptRoot 'auth-current-role.sql')},
        @{Name='privilege_escalation'; File=(Join-Path $PSScriptRoot 'auth-privilege-escalation.sql')},
        @{Name='full_authorization'; File=(Join-Path $PSScriptRoot 'auth-full-authorization.sql')},
        @{Name='multirole'; File=(Join-Path $PSScriptRoot 'auth-multirole.sql')},
        @{Name='null_authorization'; File=(Join-Path $PSScriptRoot 'auth-null-authorization.sql')},
        @{Name='concurrency'; File=$null},
        @{Name='abuse_baseline'; File=(Join-Path $PSScriptRoot 'abuse-protection-baseline.sql')},
        @{Name='abuse_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261016020611_advanced_abuse_protection.sql')},
        @{Name='abuse_protection'; File=(Join-Path $PSScriptRoot 'abuse-protection.sql')},
        @{Name='abuse_role_regression'; File=(Join-Path $PSScriptRoot 'auth-current-role.sql')},
        @{Name='abuse_authorization_regression'; File=(Join-Path $PSScriptRoot 'auth-full-authorization.sql')},
        @{Name='abuse_multirole_regression'; File=(Join-Path $PSScriptRoot 'auth-multirole.sql')},
        @{Name='abuse_null_regression'; File=(Join-Path $PSScriptRoot 'auth-null-authorization.sql')},
        @{Name='ticket_concurrency_baseline'; File=(Join-Path $PSScriptRoot 'ticket-concurrency-baseline.sql')},
        @{Name='ticket_concurrency_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261016170911_ticket_concurrency.sql')},
        @{Name='ticket_concurrency'; File=(Join-Path $PSScriptRoot 'ticket-concurrency.sql')},
        @{Name='ticket_row_race'; File=$null},
        @{Name='workspace_sync_baseline'; File=(Join-Path $PSScriptRoot 'workspace-sync-baseline.sql')},
        @{Name='workspace_sync_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261016171002_workspace_sync.sql')},
        @{Name='workspace_sync'; File=(Join-Path $PSScriptRoot 'workspace-sync.sql')},
        @{Name='operation_concurrency_baseline'; File=(Join-Path $PSScriptRoot 'operation-concurrency-baseline.sql')},
        @{Name='operation_concurrency_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261016171938_operation_concurrency.sql')},
        @{Name='operation_concurrency'; File=(Join-Path $PSScriptRoot 'operation-concurrency.sql')},
        @{Name='operation_receipt_race'; File=$null},
        @{Name='operation_schedule_race'; File=$null},
        @{Name='atomic_note_checklist_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261016172205_atomic_note_checklist.sql')},
        @{Name='atomic_note_checklist'; File=(Join-Path $PSScriptRoot 'atomic-note-checklist.sql')},
        @{Name='command_receipt_baseline'; File=(Join-Path $PSScriptRoot 'command-receipt-baseline.sql')},
        @{Name='command_receipt_migration'; File=(Join-Path $taskRepo 'supabase\migrations\20261016172737_scheduled_ticket_revision_receipt.sql')},
        @{Name='command_receipt'; File=(Join-Path $PSScriptRoot 'command-receipt.sql')},
        @{Name='workspace_sync_regression'; File=(Join-Path $PSScriptRoot 'workspace-sync.sql')},
        @{Name='ticket_concurrency_regression'; File=(Join-Path $PSScriptRoot 'ticket-concurrency.sql')},
        @{Name='sync_role_regression'; File=(Join-Path $PSScriptRoot 'auth-current-role.sql')},
        @{Name='sync_authorization_regression'; File=(Join-Path $PSScriptRoot 'auth-full-authorization.sql')},
        @{Name='sync_multirole_regression'; File=(Join-Path $PSScriptRoot 'auth-multirole.sql')},
        @{Name='sync_null_regression'; File=(Join-Path $PSScriptRoot 'auth-null-authorization.sql')},
        @{Name='command_receipt_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_scheduled_ticket_revision_receipt.sql')},
        @{Name='command_receipt_equivalence'; File=(Join-Path $PSScriptRoot 'command-receipt-rollback.sql')},
        @{Name='atomic_note_checklist_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_atomic_note_checklist.sql')},
        @{Name='operation_concurrency_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_operation_concurrency.sql')},
        @{Name='operation_concurrency_equivalence'; File=(Join-Path $PSScriptRoot 'operation-concurrency-rollback.sql')},
        @{Name='workspace_sync_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_workspace_sync.sql')},
        @{Name='workspace_sync_equivalence'; File=(Join-Path $PSScriptRoot 'workspace-sync-rollback.sql')},
        @{Name='ticket_concurrency_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_ticket_concurrency.sql')},
        @{Name='ticket_concurrency_equivalence'; File=(Join-Path $PSScriptRoot 'ticket-concurrency-rollback.sql')},
        @{Name='abuse_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_advanced_abuse_protection.sql')},
        @{Name='abuse_equivalence'; File=(Join-Path $PSScriptRoot 'abuse-protection-rollback.sql')},
        @{Name='full_audit_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_full_authorization_audit.sql')},
        @{Name='full_audit_equivalence'; File=(Join-Path $PSScriptRoot 'auth-full-audit-rollback.sql')},
        @{Name='current_role_rollback'; File=(Join-Path $taskRepo 'supabase\rollback_current_role_operational_guards.sql')},
        @{Name='rollback'; File=(Join-Path $taskRepo 'supabase\rollback_auth_workspace_memberships.sql')},
        @{Name='equivalence'; File=(Join-Path $PSScriptRoot 'auth-rollback.sql')}
    )
    foreach ($taskStage in $taskStages) {
        if ($taskStage.Name -eq 'concurrency') { Invoke-AuthConcurrency; continue }
        if ($taskStage.Name -eq 'ticket_row_race') { Invoke-SqlRowRace 'ticket-concurrency-race' 'aida_ticket_revision_second' 'STALE_WRITE_REJECTED'; continue }
        if ($taskStage.Name -eq 'operation_receipt_race') { Invoke-SqlRowRace 'operation-receipt-concurrency' 'aida_operation_receipt_second' 'OPERATION_CONFLICT'; continue }
        if ($taskStage.Name -eq 'operation_schedule_race') { Invoke-SqlRowRace 'operation-schedule-concurrency' 'aida_operation_schedule_second' 'OPERATION_CONFLICT'; continue }
        $taskLog = Join-Path $taskLogs ($taskStage.Name + '.log')
        & $taskPsql -h 127.0.0.1 -p $Port -U $AdminUser -d $DatabaseName -v ON_ERROR_STOP=1 -q -f $taskStage.File -o $taskLog
        if ($LASTEXITCODE -ne 0) { throw "SQL stage $($taskStage.Name) failed. Inspect $taskLog; no remote project was contacted." }
        Write-Output "PASS $($taskStage.Name)"
    }
    Write-Output "Completed migration/security/delivery/operations/rollback verification in $DatabaseName. Logs: $taskLogs"
} finally {
    $env:PGPASSWORD = $taskPreviousPassword
}
