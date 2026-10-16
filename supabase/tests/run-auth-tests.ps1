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
        $taskLog = Join-Path $taskLogs ($taskStage.Name + '.log')
        & $taskPsql -h 127.0.0.1 -p $Port -U $AdminUser -d $DatabaseName -v ON_ERROR_STOP=1 -q -f $taskStage.File -o $taskLog
        if ($LASTEXITCODE -ne 0) { throw "SQL stage $($taskStage.Name) failed. Inspect $taskLog; no remote project was contacted." }
        Write-Output "PASS $($taskStage.Name)"
    }
    Write-Output "Completed migration/security/delivery/operations/rollback verification in $DatabaseName. Logs: $taskLogs"
} finally {
    $env:PGPASSWORD = $taskPreviousPassword
}
