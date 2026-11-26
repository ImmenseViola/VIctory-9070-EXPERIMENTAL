param(
    [int] $TargetPid = 18396,
    [string] $Tag = 'ab-batch-port7-1',
    [double] $PrivateLimitGb = 28.0,
    [int] $MaxMinutes = 8,
    [int] $MinDraws = 3000,
    [int[]] $CycleEnds = @(7, 11, 15, 19, 23)
)

$root = 'C:\Users\Admin\AppData\Local\Temp\opencode'
$log = Join-Path $root "$Tag-stderr.txt"
$deadline = (Get-Date).AddMinutes($MaxMinutes)
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

function TranslationBusy {
    $lines = @(Get-Content $log -Tail 60 -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        $l = $line -replace '\x1b\[[0-9;]*m', ''
        if ($l -match ', ([1-9][0-9]*) being made') { return $true }
        if ($l -match 'translating shader|shader translation in progress|making host pipeline') { return $true }
    }
    return $false
}

while ((Get-Date) -lt $deadline) {
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { $reason = 'exited'; break }

    $busy = TranslationBusy
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

"STOP_REASON=$reason"
if ($reason -ne 'exited') {
    taskkill /PID $TargetPid /F /T
}
