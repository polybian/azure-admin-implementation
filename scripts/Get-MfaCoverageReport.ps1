<#
.SYNOPSIS
    Read-only MFA coverage report from exported user data (offline).

.DESCRIPTION
    Parses a CSV of user identity data and reports MFA coverage: who lacks
    MFA, a per-auth-method breakdown, and privileged admins without MFA
    (flagged as the critical finding).

    This script works against EXPORTED CSV DATA, not a live tenant. It never
    calls Microsoft Graph, Azure cmdlets, or any network endpoint. There is
    nothing to authenticate to and nothing it can change, which is why it
    needs no SupportsShouldProcess/WhatIf: it is pure reporting.

    Expected CSV columns:
        UserPrincipalName, DisplayName, Department, MfaState,
        RegisteredAuthMethods (semicolon-separated), IsPrivilegedAdmin,
        DaysSinceLastSignIn

    A fictional example file ships at scripts/users.csv.example
    (contoso.example users). Real exports must NEVER be committed;
    see .gitignore (*.csv is ignored except *.csv.example).

.PARAMETER InputCsv
    Path to the CSV file to analyze. Defaults to users.csv.example
    next to this script.

.PARAMETER OutputPath
    Optional path to also write the summary as JSON.

.EXAMPLE
    ./Get-MfaCoverageReport.ps1
    Runs the report against the bundled example data.

.EXAMPLE
    ./Get-MfaCoverageReport.ps1 -InputCsv ./users-export.csv -OutputPath ./mfa-report.json
    Runs the report against a real export and saves a JSON summary.
    (Do not commit the real export.)
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string] $InputCsv = (Join-Path -Path $PSScriptRoot -ChildPath 'users.csv.example'),

    [Parameter()]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'

$users = Import-Csv -Path $InputCsv

$total = $users.Count
if ($total -eq 0) {
    Write-Warning "No users found in '$InputCsv'."
    return
}

$withMfa = @($users | Where-Object { $_.MfaState -eq 'MfaRegistered' })
$withoutMfa = @($users | Where-Object { $_.MfaState -ne 'MfaRegistered' })

$methodCounts = @{}
foreach ($user in $withMfa) {
    $methods = @($user.RegisteredAuthMethods -split ';' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' })
    foreach ($method in $methods) {
        if (-not $methodCounts.ContainsKey($method)) {
            $methodCounts[$method] = 0
        }
        $methodCounts[$method]++
    }
}

$adminsWithoutMfa = @($withoutMfa | Where-Object { $_.IsPrivilegedAdmin -eq 'True' })
$staleWithoutMfa = @($withoutMfa |
    Where-Object { [int]$_.DaysSinceLastSignIn -ge 30 })

$coveragePct = [math]::Round(($withMfa.Count / $total) * 100, 1)

$summary = [ordered]@{
    GeneratedUtc   = (Get-Date).ToUniversalTime().ToString('o')
    SourceFile     = (Split-Path -Path $InputCsv -Leaf)
    TotalUsers     = $total
    WithMfa        = $withMfa.Count
    WithoutMfa     = $withoutMfa.Count
    CoveragePct    = $coveragePct
    MethodBreakdown = $methodCounts
    AdminsWithoutMfa = @($adminsWithoutMfa | ForEach-Object { $_.UserPrincipalName })
}

Write-Output ''
Write-Output '=== MFA Coverage Report (CSV data, no live tenant) ==='
Write-Output ("Source file : {0}" -f $summary.SourceFile)
Write-Output ("Generated   : {0:u} UTC" -f (Get-Date).ToUniversalTime())
Write-Output ''
Write-Output ("Total users        : {0}" -f $total)
Write-Output ("With MFA registered: {0}" -f $withMfa.Count)
Write-Output ("Without MFA        : {0}" -f $withoutMfa.Count)
Write-Output ("Coverage           : {0}%" -f $coveragePct)
Write-Output ''

Write-Output '--- Auth method breakdown (registered users) ---'
if ($methodCounts.Count -eq 0) {
    Write-Output '(no auth methods registered)'
}
else {
    foreach ($entry in ($methodCounts.GetEnumerator() | Sort-Object Value -Descending)) {
        Write-Output ("{0,-24} {1,3} user(s)" -f $entry.Key, $entry.Value)
    }
}
Write-Output ''

Write-Output '--- Users WITHOUT MFA ---'
if ($withoutMfa.Count -eq 0) {
    Write-Output '(none — full coverage)'
}
else {
    $withoutMfa |
        Sort-Object { [int]$_.DaysSinceLastSignIn } -Descending |
        Format-Table -AutoSize -Property `
            @{ Label = 'UPN'; Expression = { $_.UserPrincipalName } },
            @{ Label = 'Name'; Expression = { $_.DisplayName } },
            Department,
            @{ Label = 'Admin'; Expression = { $_.IsPrivilegedAdmin } },
            @{ Label = 'LastSignInDaysAgo'; Expression = { $_.DaysSinceLastSignIn } } |
        Out-String |
        Write-Output
}

if ($adminsWithoutMfa.Count -gt 0) {
    Write-Output ''
    Write-Output '!!! CRITICAL: privileged admins WITHOUT MFA !!!'
    foreach ($admin in $adminsWithoutMfa) {
        Write-Output ("  - {0} ({1})" -f $admin.UserPrincipalName, $admin.DisplayName)
    }
}

if ($staleWithoutMfa.Count -gt 0) {
    Write-Output ''
    Write-Output '--- Stale accounts (>= 30 days since sign-in) without MFA ---'
    foreach ($stale in $staleWithoutMfa) {
        Write-Output ("  - {0} ({1}d inactive)" -f $stale.UserPrincipalName, $stale.DaysSinceLastSignIn)
    }
}

Write-Output ''

if ($OutputPath) {
    $summary | ConvertTo-Json -Depth 4 | Set-Content -Path $OutputPath -Encoding utf8
    Write-Verbose "Summary written to '$OutputPath'."
}

return $summary
