param(
    [int] $TargetPid = 18396,
    [string] $Tag = 'ab-batch-port7-1',
    [double] $PrivateLimitGb = 28.0,
    [int] $MaxMinutes = 8,
    [double] $DenseGateMinutes = 5.0,
    [double] $MinDraws = 3000,
    [int[]] $CycleEnds = @(7, 11, 15, 19, 23)
)

$root = 'C:\mygame\victory-work'
$log = Join-Path $root "$Tag-stderr.txt"
$stopFile = Join-Path $root "$Tag-stop.txt"
$deadline = (Get-Date).AddMinutes($MaxMinutes)
$hardDeadline = $deadline.AddMinutes(15)
$reason = 'timeout'

function Get-PhaseDraws {
    $draws = @{}
    Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_ -replace '\x1b\[[0-9;]*m', ''
        if ($line -match 'A/B phase (\d+) bits .*: \d+ frames, mean [\d.]+ ms, median [\d.]+, p90 [\d.]+, ([\d.]+) draws a frame') {
            $draws[[int]$Matches[1]] = [double]$Matches[2]
        }
    }
    return $draws
}

function Has-DensePhase {
    @((Get-PhaseDraws).Values | Where-Object { $_ -ge $MinDraws }).Count -gt 0
}

function TranslationBusy {
    $lines = @(Get-Content $log -Tail 60 -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        $l = $line -replace '\x1b\[[0-9;]*m', ''
        if ($l -match ', ([1-9][0-9]*) being made') { return $true }
        if ($l -match 'translating shader|shader translation in progress|making host pipeline') { return $true }
    }
    return $false
}

while ((Get-Date) -lt $hardDeadline) {
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { $reason = 'exited'; break }

    # Cold menu/translation sessions are useless A/Bs. Time the gate from the
    # game's own start, not from when this watcher happened to be launched.
    if (-not (Has-DensePhase) -and (Get-Date) -ge $p.StartTime.AddMinutes($DenseGateMinutes)) {
        $reason = "no dense gameplay within $DenseGateMinutes minutes"
        $busy = TranslationBusy
        break
    }

    $busy = TranslationBusy
    if ((Get-Date) -ge $deadline -and $busy) {
        Start-Sleep -Seconds 10
        continue
    }
    $private = $p.PrivateMemorySize64 / 1GB
    if ($private -gt $PrivateLimitGb -and -not $busy) { $reason = "private ${private:N2} GB"; break }

    $draws = Get-PhaseDraws
    foreach ($end in $CycleEnds) {
        $all = $true
        for ($i = $end - 3; $i -le $end; $i++) {
            if (-not $draws.ContainsKey($i) -or $draws[$i] -lt $MinDraws) { $all = $false }
        }
        if ($all -and -not $busy) { $reason = "clean cycle ending at phase $end"; break }
    }
    if ($reason -ne 'timeout') { break }
    Start-Sleep -Seconds 10
}

if ($busy -and $reason -eq 'timeout') { $reason = 'busy at hard deadline' }
"STOP_REASON=$reason"
"STOP_REASON=$reason" | Set-Content -LiteralPath $stopFile -Encoding ascii
$gateAbort = $reason -like 'no dense gameplay*'
if ($reason -ne 'exited' -and (-not $busy -or $gateAbort)) {
    taskkill /PID $TargetPid /F /T
}
