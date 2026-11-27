param(
    [int] $TargetPid,
    [string] $Tag,
    [int] $TimeoutMinutes = 60
)

# Close a game that a phase stopper left alive because shader/pipeline work was
# still active. This never kills a busy game: it waits for a quiet log window,
# then uses the same tree kill as the normal stopper.
$root = 'C:\mygame\victory-work'
$log = Join-Path $root "$Tag-stderr.txt"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

function TranslationBusy {
    $lines = @(Get-Content $log -Tail 60 -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        $l = $line -replace '\x1b\[[0-9;]*m', ''
        if ($l -match ', ([1-9][0-9]*) being made') { return $true }
        if ($l -match 'translating shader|shader translation in progress|making host pipeline') { return $true }
        if ($l -match 'shader translated stage=|host pipeline shaders=|host mesh pipeline shaders=') { return $true }
    }
    return $false
}

while ((Get-Date) -lt $deadline) {
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { "IDLE_STOP_REASON=exited $(Get-Date -Format o)"; return }

    if (TranslationBusy) {
        Start-Sleep -Seconds 10
        continue
    }
    "IDLE_STOP_REASON=quiet $(Get-Date -Format o)"
    taskkill /PID $TargetPid /F /T
    return
}

"IDLE_STOP_REASON=busy at idle-stop timeout $(Get-Date -Format o)"
