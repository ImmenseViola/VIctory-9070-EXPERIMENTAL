param(
    [int] $TargetPid,
    [string] $Tag,
    [int] $TimeoutMinutes = 720,
    [int] $QuietSeconds = 45,
    [int] $PressIntervalSeconds = 20,
    [int] $DenseDraws = 3000
)

Add-Type -AssemblyName System.Windows.Forms

$log = "C:\mygame\victory-work\$Tag-stderr.txt"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$quietSince = $null
$lastPress = $null

function Get-RecentLogLines {
    $cutoff = (Get-Date).ToUniversalTime().AddSeconds(-30)
    foreach ($line in @(Get-Content $log -Tail 400 -ErrorAction SilentlyContinue)) {
        $l = $line -replace '\x1b\[[0-9;]*m', ''
        if ($l -match '^(\d{4}-\d\d-\d\dT[^\s]+Z)') {
            try {
                $at = [datetimeoffset]::Parse($Matches[1])
                if ($at -lt $cutoff) { continue }
            } catch { }
        } else {
            continue
        }
        $l
    }
}

function TranslationBusy {
    $busy = $false
    foreach ($l in Get-RecentLogLines) {
        if ($l -match ', ([0-9]+) being made') { $busy = ([int]$Matches[1] -gt 0) }
        if ($l -match 'translating shader|shader translation in progress|making host pipeline|shader translated stage=|host pipeline shaders=|host mesh pipeline shaders=') { $busy = $true }
    }
    return $busy
}

function HasGameplay {
    foreach ($l in Get-RecentLogLines) {
        if ($l -match '([0-9][0-9,]*) draws/frame') {
            $draws = [double](($Matches[1] -replace ',', ''))
            if ($draws -ge $DenseDraws) { return $true }
        }
    }
    return $false
}

while ((Get-Date) -lt $deadline) {
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { "EXITED $(Get-Date -Format o)"; return }

    if (HasGameplay) {
        "GAMEPLAY_DETECTED at $(Get-Date -Format o) draws>=$DenseDraws"
        return
    }

    if (TranslationBusy) {
        $quietSince = $null
        Start-Sleep -Seconds 10
        continue
    }

    if (-not $quietSince) { $quietSince = Get-Date }
    if (((Get-Date) - $quietSince).TotalSeconds -lt $QuietSeconds) {
        Start-Sleep -Seconds 10
        continue
    }

    if ($lastPress -and ((Get-Date) - $lastPress).TotalSeconds -lt $PressIntervalSeconds) {
        Start-Sleep -Seconds 5
        continue
    }

    $wshell = New-Object -ComObject WScript.Shell
    $ok = $wshell.AppActivate($TargetPid)
    if (-not $ok) {
        "ENTER_SKIP at $(Get-Date -Format o) appactivate=$ok"
        $lastPress = Get-Date
        Start-Sleep -Seconds 5
        continue
    }

    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    "ENTER_SENT at $(Get-Date -Format o) appactivate=$ok interval=$PressIntervalSeconds"
    $lastPress = Get-Date
}

"TIMEOUT $(Get-Date -Format o)"
