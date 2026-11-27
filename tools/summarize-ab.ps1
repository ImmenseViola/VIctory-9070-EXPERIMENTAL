param(
    [string] $Tag = 'ab-batch-port7-1',
    [int] $FirstPhase = 0
)

$root = 'C:\mygame\victory-work'
$log = Join-Path $root "$Tag-stderr.txt"
$rows = @()
Get-Content $log | ForEach-Object {
    $line = $_ -replace '\x1b\[[0-9;]*m', ''
    if ($line -notmatch 'A/B phase (\d+) bits (\d+) on \[([^\]]*)\]: (\d+) frames, mean ([\d.]+) ms, median ([\d.]+), p90 ([\d.]+), ([\d.]+) draws a frame') {
        return
    }
    $phase = [int]$Matches[1]
    if ($phase -lt $FirstPhase) { return }
    $rows += [pscustomobject]@{
        phase = $phase
        bits = [int]$Matches[2]
        on = $Matches[3]
        frames = [int]$Matches[4]
        mean = [double]$Matches[5]
        median = [double]$Matches[6]
        p90 = [double]$Matches[7]
        draws = [double]$Matches[8]
    }
}

"phases from $FirstPhase, grouped by switch bits"
$rows | Group-Object bits | ForEach-Object {
    $g = $_.Group
    [pscustomobject]@{
        bits = $_.Name
        on = $g[0].on
        phases = $g.Count
        frames = ($g | Measure-Object frames -Sum).Sum
        mean_of_means = [math]::Round(($g | Measure-Object mean -Average).Average, 2)
        mean_of_medians = [math]::Round(($g | Measure-Object median -Average).Average, 2)
        worst_p90 = [math]::Round(($g | Measure-Object p90 -Maximum).Maximum, 2)
        mean_draws = [math]::Round(($g | Measure-Object draws -Average).Average, 0)
    }
} | Format-Table -AutoSize

$csv = Join-Path $root "$Tag-monitor.csv"
if (Test-Path $csv) {
    'monitor tail'
    Get-Content $csv | Select-Object -Last 10
}
