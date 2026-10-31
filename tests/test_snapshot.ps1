$ErrorActionPreference = 'Stop'
$script = 'C:\tmp\fset\build\config-snapshot.ps1'
$root   = 'C:\tmp\fset\fakewow'
$real   = 'D:\World of Warcraft\_forever_\WTF\Config.wtf'
$results = New-Object System.Collections.Generic.List[string]

function Check([string]$name, [bool]$cond, [string]$detail) {
    if ($cond) { $results.Add("PASS $name") } else { $results.Add("FAIL $name  -- $detail") }
}

function Run-Script([string[]]$scriptArgs) {
    # returns @{ ok; text; warn } with every stream flattened to text
    $r = @{ ok = $true; text = ''; warn = '' }
    try {
        $all = & $script @scriptArgs -WowRoot $root 3>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.WarningRecord]) { 'WARN: ' + $_.Message } else { "$_" } }
        $r.text = ($all -join "`n")
        $r.warn = (($all | Where-Object { $_ -like 'WARN:*' }) -join "`n")
    } catch {
        $r.ok = $false
        $r.text = $_.Exception.Message
    }
    $r
}

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$root\_forever_\WTF" | Out-Null
$cfg = "$root\_forever_\WTF\Config.wtf"
Copy-Item -LiteralPath $real -Destination $cfg
$origHash = (Get-FileHash $cfg).Hash
$acct = ((Get-Content $cfg | Where-Object { $_ -match '^SET accountName ' }) -replace '^SET accountName\s+"?', '' -replace '"$', '')
Check 'setup: found an accountName value to test redaction with' ($acct.Length -gt 3) 'no accountName in the copied file'

# Save, List, Diff with no change
$r = Run-Script @('Save', 'before')
Check 'Save writes a labelled snapshot' ($r.ok -and (Get-ChildItem "$root\ForeverSettings-tools\backups" -Filter 'before-*.wtf').Count -eq 1) $r.text
$r = Run-Script @('Diff', 'before')
Check 'Diff of an unchanged file says no differences' ($r.ok -and $r.text -like '*No differences.*') $r.text
$r = Run-Script @('List')
Check 'List shows the snapshot' ($r.ok -and $r.text -like '*before-*.wtf*') $r.text

# Change the file four ways, plus a CACHE key that must be ignored
$lines = Get-Content $cfg | Where-Object { $_ -notmatch '^SET groundEffectDist ' }
$lines = $lines | ForEach-Object {
    if ($_ -match '^SET graphicsSSAO ') { 'SET graphicsSSAO "2"' }
    elseif ($_ -match '^SET accountName ') { 'SET accountName "someone-else@example.com"' }
    elseif ($_ -match '^SET CACHE-WQST-QuestV2RecordCount ') { 'SET CACHE-WQST-QuestV2RecordCount "1"' }
    else { $_ }
}
$lines += 'SET giQualityTest "1"'
Set-Content -LiteralPath $cfg -Value $lines -Encoding ASCII

$r = Run-Script @('Diff', 'before')
Check 'Diff reports a changed value' ($r.text -like '*CHANGED  graphicsSSAO : "3" -> "2"*') $r.text
Check 'Diff reports a removed key with its old value' ($r.text -like '*REMOVED  groundEffectDist (was "200")*') $r.text
Check 'Diff reports an added key' ($r.text -like '*ADDED    giQualityTest = "1"*') $r.text
Check 'Diff reports the account change without its values' ($r.text -like '*CHANGED  accountName : <withheld> -> <withheld>*') $r.text
Check 'Diff output never contains the account value' ($r.text -notlike ('*' + $acct + '*') -and $r.text -notlike '*someone-else@example.com*') 'account value leaked'
Check 'Diff ignores CACHE-* keys' ($r.text -notlike '*CACHE-*') $r.text
Check 'Diff counts exactly four differences' ($r.text -like '*4 difference(s).*') $r.text

# Argument errors
$r = Run-Script @('Diff', 'nosuchlabel')
Check 'Diff with an unknown label fails clearly' ((-not $r.ok) -and $r.text -like "*No snapshot labelled 'nosuchlabel'*") $r.text
$r = Run-Script @('Save', 'bad label!')
Check 'A label with odd characters is refused' ((-not $r.ok) -and $r.text -like '*letters, digits*') $r.text
$r = Run-Script @('Save')
Check 'Save without a label is refused' ((-not $r.ok) -and $r.text -like '*needs a label*') $r.text

# Restore
$r = Run-Script @('Restore', 'before')
Check 'Restore puts the snapshot back byte for byte' ($r.ok -and (Get-FileHash $cfg).Hash -eq $origHash) $r.text
Check 'Restore first saved the file it replaced as pre-restore' ((Get-ChildItem "$root\ForeverSettings-tools\backups" -Filter 'pre-restore-*.wtf').Count -eq 1) $r.text

# A stand-in process named Wow.exe, to exercise the running-game guard
$fake = 'C:\tmp\fset\fakeproc\Wow.exe'
New-Item -ItemType Directory -Force -Path (Split-Path $fake) | Out-Null
Copy-Item 'C:\Windows\System32\PING.EXE' $fake -Force
$p = Start-Process -FilePath $fake -ArgumentList '-n', '60', '127.0.0.1' -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Milliseconds 700
    Check 'setup: stand-in Wow process is visible to Get-Process' ([bool](Get-Process -Name 'Wow' -ErrorAction SilentlyContinue)) 'process not found'
    $r = Run-Script @('Restore', 'before')
    Check 'Restore refuses while a Wow process runs' ((-not $r.ok) -and $r.text -like '*WoW is running*') $r.text
    $r = Run-Script @('Save', 'whilerunning')
    Check 'Save still works but warns while a Wow process runs' ($r.ok -and $r.warn -like '*WoW is running*') ($r.text + ' / ' + $r.warn)
}
finally {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500
Check 'cleanup: stand-in process is gone' (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) 'still running'

$results -join "`n"
$failed = ($results | Where-Object { $_ -like 'FAIL*' }).Count
"`n$($results.Count - $failed)/$($results.Count) passed"
