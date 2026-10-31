<#
.SYNOPSIS
  Snapshot, compare and restore the WoW Forever Config.wtf.

.DESCRIPTION
  The game writes Config.wtf when it exits or reloads, so quit WoW before Save,
  Diff or Restore if you want the file to reflect your latest changes.

  Save <label>      copy Config.wtf to ForeverSettings-tools\backups\<label>-<timestamp>.wtf
  Diff <label>      compare the current Config.wtf with the newest snapshot of that label
  List              list the snapshots
  Restore <label>   put the newest snapshot of that label back. Refuses while WoW runs
                    and saves the current file first, labelled pre-restore.

  To find which CVar a menu slider controls:
    .\config-snapshot.ps1 Save before
    (start WoW, change ONE slider, quit WoW)
    .\config-snapshot.ps1 Diff before

  Diff withholds values for account-like keys and for long token-like values.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('Save', 'Diff', 'List', 'Restore')]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$Label,

    [string]$WowRoot = 'D:\World of Warcraft',
    [string]$Client  = '_forever_'
)

$ErrorActionPreference = 'Stop'

$Config    = Join-Path $WowRoot "$Client\WTF\Config.wtf"
$Backups   = Join-Path $WowRoot 'ForeverSettings-tools\backups'
$Sensitive = '(?i)account|agentuid|portal|token|password|email|login'

if (-not (Test-Path -LiteralPath $Config)) { throw "Config.wtf not found: $Config" }

function Test-GameRunning {
    [bool](Get-Process -Name 'Wow', 'WowB', 'WowT', 'WowClassic' -ErrorAction SilentlyContinue)
}

function Assert-Label {
    if (-not $Label) { throw "$Action needs a label, for example: .\config-snapshot.ps1 $Action before" }
    if ($Label -notmatch '^[A-Za-z0-9._-]+$') { throw 'A label may only hold letters, digits, dot, underscore and hyphen.' }
}

function Find-Snapshot([string]$name) {
    if (-not (Test-Path -LiteralPath $Backups)) { return $null }
    $pattern = '^' + [regex]::Escape($name) + '-\d{8}-\d{6}\.wtf$'
    Get-ChildItem -LiteralPath $Backups -File |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Read-Settings([string]$path) {
    $h = [System.Collections.Generic.Dictionary[string, string]]::new()
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^SET\s+(\S+)\s+(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() }
    }
    $h
}

function Show-Value([string]$key, [string]$value) {
    if ($key -match $Sensitive -or $value -match '[A-Za-z0-9+/=_-]{32,}') { '<withheld>' } else { $value }
}

function Save-Snapshot([string]$name) {
    New-Item -ItemType Directory -Force -Path $Backups | Out-Null
    $dest = Join-Path $Backups ('{0}-{1}.wtf' -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $Config -Destination $dest
    $dest
}

if ($Action -ne 'List' -and (Test-GameRunning)) {
    if ($Action -eq 'Restore') { throw 'WoW is running. Quit it first, it would overwrite the restored file on exit.' }
    Write-Warning 'WoW is running. Config.wtf only updates when the game exits or reloads, so this may be stale.'
}

switch ($Action) {
    'Save' {
        Assert-Label
        $dest = Save-Snapshot $Label
        "Saved $dest"
    }
    'List' {
        if (-not (Test-Path -LiteralPath $Backups)) { 'No snapshots yet.'; break }
        Get-ChildItem -LiteralPath $Backups -File -Filter '*.wtf' |
            Sort-Object LastWriteTime |
            ForEach-Object { '{0}  {1,6} bytes  {2}' -f $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $_.Length, $_.Name }
    }
    'Diff' {
        Assert-Label
        $snap = Find-Snapshot $Label
        if (-not $snap) { throw "No snapshot labelled '$Label'. Use List to see what exists." }
        $old = Read-Settings $snap.FullName
        $new = Read-Settings $Config
        "Comparing $($snap.Name) with the current Config.wtf"
        $keys = @($old.Keys) + @($new.Keys) | Sort-Object -Unique -CaseSensitive
        $count = 0
        foreach ($k in $keys) {
            if ($k -like 'CACHE-*') { continue }
            $inOld = $old.ContainsKey($k)
            $inNew = $new.ContainsKey($k)
            if ($inOld -and $inNew) {
                if ($old[$k] -cne $new[$k]) {
                    "CHANGED  $k : $(Show-Value $k $old[$k]) -> $(Show-Value $k $new[$k])"
                    $count++
                }
            }
            elseif ($inNew) { "ADDED    $k = $(Show-Value $k $new[$k])"; $count++ }
            else            { "REMOVED  $k (was $(Show-Value $k $old[$k]))"; $count++ }
        }
        if ($count -eq 0) { 'No differences.' } else { "$count difference(s)." }
    }
    'Restore' {
        Assert-Label
        $snap = Find-Snapshot $Label
        if (-not $snap) { throw "No snapshot labelled '$Label'. Use List to see what exists." }
        $pre = Save-Snapshot 'pre-restore'
        Copy-Item -LiteralPath $snap.FullName -Destination $Config -Force
        "Restored $($snap.Name). The file it replaced is saved as $pre"
    }
}
