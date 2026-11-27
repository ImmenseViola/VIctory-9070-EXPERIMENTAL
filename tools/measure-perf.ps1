param(
    [string] $Tag = 'manual-play1',
    [int] $TargetPid = 15936,
    [int] $WindowSeconds = 60,
    [int] $IntervalSeconds = 30
)

$root = 'C:\mygame\victory-work'
$log = Join-Path $root "$Tag-stderr.txt"
$out = Join-Path $root "$Tag-perf.csv"

if (-not (Test-Path $out)) {
    'timestamp,frames,fps_mean,fps_min,ms_mean,ms_median,ms_p90,draws_mean,prep_ms,copy_ms,copy_mb,tex_ms,tex_mb,gpu_ms,back_ms,ws_gb,private_gb,cpu_s' | Set-Content -Encoding ascii $out
}

$pattern = '(?<t>\d{4}-\d{2}-\d{2}T[\d:.]+Z).*?\b(?<fps>[\d.]+) fps, (?<ms>[\d.]+) ms/frame \((?<prep>[\d.]+) preparing: copies (?<cpyms>[\d.]+) ms (?<cpymb>[\d.]+) MB, textures (?<texms>[\d.]+) ms (?<texmb>[\d.]+) MB; (?<gpu>[\d.]+) on the GPU; (?<back>[\d.]+) copying back (?<backmb>[\d.]+) MB\), (?<draws>[\d.]+) draws/frame'

function P90([double[]] $values) {
    if ($values.Count -eq 0) { return 0 }
    $sorted = @($values | Sort-Object)
    $index = [math]::Min($sorted.Count - 1, [int][math]::Ceiling($sorted.Count * 0.9) - 1)
    return $sorted[$index]
}

while ($true) {
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $p -or $p.HasExited) { break }

    $end = [DateTimeOffset]::UtcNow
    $start = $end.AddSeconds(-$WindowSeconds)
    $rows = @()

    foreach ($raw in @(Get-Content $log -Tail 1200 -ErrorAction SilentlyContinue)) {
        $line = $raw -replace '\x1b\[[0-9;]*m', ''
        if ($line -notmatch $pattern) { continue }
        $ts = [datetimeoffset]::Parse($Matches['t'])
        if ($ts -lt $start -or $ts -gt $end) { continue }
        $rows += [pscustomobject]@{
            fps   = [double]$Matches['fps']
            ms    = [double]$Matches['ms']
            prep  = [double]$Matches['prep']
            cpyms = [double]$Matches['cpyms']
            cpymb = [double]$Matches['cpymb']
            texms = [double]$Matches['texms']
            texmb = [double]$Matches['texmb']
            gpu   = [double]$Matches['gpu']
            back  = [double]$Matches['back']
            draws = [double]$Matches['draws']
        }
    }

    if ($rows.Count -gt 0) {
        $msValues = @($rows | ForEach-Object { $_.ms } | Sort-Object)
        $msMedian = $msValues[[int][math]::Floor(($msValues.Count - 1) / 2)]
        $lineOut = '{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17}' -f `
            (Get-Date -Format o), `
            $rows.Count, `
            [math]::Round(($rows | Measure-Object fps -Average).Average, 2), `
            [math]::Round(($rows | Measure-Object fps -Minimum).Minimum, 2), `
            [math]::Round(($rows | Measure-Object ms -Average).Average, 2), `
            [math]::Round($msMedian, 2), `
            [math]::Round((P90 $msValues), 2), `
            [math]::Round(($rows | Measure-Object draws -Average).Average, 0), `
            [math]::Round(($rows | Measure-Object prep -Average).Average, 2), `
            [math]::Round(($rows | Measure-Object cpyms -Average).Average, 2), `
            [math]::Round(($rows | Measure-Object cpymb -Average).Average, 1), `
            [math]::Round(($rows | Measure-Object texms -Average).Average, 2), `
            [math]::Round(($rows | Measure-Object texmb -Average).Average, 1), `
            [math]::Round(($rows | Measure-Object gpu -Average).Average, 2), `
            [math]::Round(($rows | Measure-Object back -Average).Average, 2), `
            [math]::Round($p.WorkingSet64 / 1GB, 2), `
            [math]::Round($p.PrivateMemorySize64 / 1GB, 2), `
            [math]::Round($p.CPU, 1)
        $lineOut | Add-Content -Encoding ascii $out
    }

    Start-Sleep -Seconds $IntervalSeconds
}
