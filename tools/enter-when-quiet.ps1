param(
    [int] $TargetPid,
    [string] $Tag,
    [int] $TimeoutMinutes = 25,
    [int] $QuietSeconds = 45
)

Add-Type -AssemblyName System.Windows.Forms

$log = "C:\mygame\victory-work\$Tag-stderr.txt"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$quietSince = $null

function TranslationBusy {
    $lines = @(Get-Content $log -Tail 50 -ErrorAction SilentlyContinue)
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
    if (-not $p -or $p.HasExited) { "EXITED $(Get-Date -Format o)"; return }

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

    $wshell = New-Object -ComObject WScript.Shell
    $ok = $wshell.AppActivate($TargetPid)
    "ENTER_QUIET at $(Get-Date -Format o) appactivate=$ok"
    if ($ok) {
        for ($i = 0; $i -lt 3; $i++) {
            [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            Start-Sleep -Seconds 3
        }
    }
    "ENTER_SENT at $(Get-Date -Format o)"
    return
}

"TIMEOUT $(Get-Date -Format o)"
