param(
    [string] $Tag = 'play',
    [string] $Upscaler = '6',
    [string] $Console = 'series-s',
    [hashtable] $Extra = @{},
    [switch] $Guard,
    [switch] $NoPanel,
    [string] $Cache = 'C:\mygame\victory-work\victory-9070-cache-v3-fixed',
    [string] $Binary = 'C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL\target\diag\victory.exe'
)

$repo = 'C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL'
$victory = $Binary
if (-not [System.IO.Path]::IsPathRooted($victory)) { $victory = Join-Path $repo $victory }
$game = 'C:\mygame\warriors and stuff\game_scarlett_master.exe'
$out = 'C:\mygame\victory-work'
$cache = $Cache

if (Get-Process -Name victory -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited }) {
    Write-Error 'A victory game session is already running.'
    exit 1
}

. (Join-Path $PSScriptRoot 'harness-env.ps1')
$settings = Get-HarnessSettings -Upscaler $Upscaler -NoPanel:$NoPanel -Guard:$Guard -Extra $Extra
Set-HarnessEnvironment -Cache $cache -Settings $settings

$stdout = Join-Path $out "$Tag-stdout.txt"
$stderr = Join-Path $out "$Tag-stderr.txt"
Remove-Item -LiteralPath $stdout,$stderr,(Join-Path $out "$Tag.pid") -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath $victory -WorkingDirectory $repo `
    -ArgumentList @('run', ('"' + $game + '"'), '--execute', '--console', $Console) `
    -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
try {
    $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
    $proc.ProcessorAffinity = [IntPtr][long](([UInt64]1 -shl [Math]::Min([Environment]::ProcessorCount,64)) - 1)
} catch { Write-Host "priority: $($_.Exception.Message)" }
$proc.Id | Set-Content -LiteralPath (Join-Path $out "$Tag.pid")
"pid=$($proc.Id) tag=$Tag guard=$([bool]$Guard) console=$Console upscaler=$Upscaler started=$(Get-Date -Format o) cache=$cache"
