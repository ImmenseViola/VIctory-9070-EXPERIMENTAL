param(
    [int] $TargetPid = 3516,
    [string] $Tag = 'active-play1',
    [int] $Samples = 10,
    [int] $IntervalSeconds = 60,
    [int] $WarmupSeconds = 120
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$out = "C:\Users\Admin\AppData\Local\Temp\opencode\$Tag-monitor.csv"
$log = "C:\Users\Admin\AppData\Local\Temp\opencode\$Tag-stderr.txt"

function Shot([string] $path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Measure-Shot([string] $aPath, [string] $bPath) {
    $a = [System.Drawing.Bitmap]::FromFile($aPath)
    $b = [System.Drawing.Bitmap]::FromFile($bPath)
    $step = 8
    $total = 0; $luma = 0.0; $nonblack = 0; $bright = 0
    $diff = 0.0; $changed = 0
    for ($y = 0; $y -lt $a.Height; $y += $step) {
        for ($x = 0; $x -lt $a.Width; $x += $step) {
            $ca = $a.GetPixel($x, $y); $cb = $b.GetPixel($x, $y)
            $l = 0.2126 * $ca.R + 0.7152 * $ca.G + 0.0722 * $ca.B
            $luma += $l; $total++
            if ($l -gt 8) { $nonblack++ }
            if ($l -gt 160) { $bright++ }
            $d = [Math]::Abs($ca.R - $cb.R) + [Math]::Abs($ca.G - $cb.G) + [Math]::Abs($ca.B - $cb.B)
            $diff += $d
            if ($d -gt 30) { $changed++ }
        }
    }
    $a.Dispose(); $b.Dispose()
    [pscustomobject]@{
        mean_luma = [math]::Round($luma / $total, 1)
        nonblack_pct = [math]::Round(100.0 * $nonblack / $total, 1)
        bright_pct = [math]::Round(100.0 * $bright / $total, 1)
        mean_rgb_diff = [math]::Round($diff / $total, 2)
        changed_pct = [math]::Round(100.0 * $changed / $total, 1)
    }
}

' timestamp,ws_gb,private_gb,cpu_s,title,mean_luma,nonblack_pct,bright_pct,mean_rgb_diff,changed_pct,frame' | Set-Content -Encoding ascii $out
Start-Sleep -Seconds $WarmupSeconds
for ($i = 0; $i -lt $Samples; $i++) {
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { " $(Get-Date -Format o),EXITED" | Add-Content -Encoding ascii $out; break }
    $aPath = "C:\Users\Admin\AppData\Local\Temp\opencode\$Tag-motion-a.png"
    $bPath = "C:\Users\Admin\AppData\Local\Temp\opencode\$Tag-motion-b.png"
    Shot $aPath
    Start-Sleep -Seconds 8
    Shot $bPath
    $m = Measure-Shot $aPath $bPath
    $frame = ''
    $match = Select-String -Path $log -Pattern 'fps, .*ms/frame' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($match) {
        $line = $match.Line -replace '\x1b\[[0-9;]*m', ''
        $frame = ($line -replace '\s+', ' ').Trim()
        if ($frame.Length -gt 120) { $frame = $frame.Substring(0, 120) }
    }
    $title = $p.MainWindowTitle -replace ',', ';'
    " $(Get-Date -Format o),$([math]::Round($p.WorkingSet64/1GB,2)),$([math]::Round($p.PrivateMemorySize64/1GB,2)),$([math]::Round($p.CPU,1)),$title,$($m.mean_luma),$($m.nonblack_pct),$($m.bright_pct),$($m.mean_rgb_diff),$($m.changed_pct),$frame" | Add-Content -Encoding ascii $out
    if ($i -lt $Samples - 1) { Start-Sleep -Seconds ($IntervalSeconds - 8) }
}
'ACTIVE_MONITOR_DONE' | Add-Content -Encoding ascii $out
