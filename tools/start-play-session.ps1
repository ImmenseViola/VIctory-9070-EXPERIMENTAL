param(
    [string] $Tag = 'play',
    [string] $Upscaler = '6',
    [string] $Console = 'series-s',
    [hashtable] $Extra = @{},
    [switch] $Guard,
    [switch] $NoPanel,
    [string] $Cache = 'C:\mygame\victory-work\victory-7900-clean-cache-1',
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

$keep = @('VICTORY_CONFIG','VICTORY_GAME_DIR','VICTORY_CACHE_DIR','VICTORY_DATA_DIR')
foreach ($e in @(Get-ChildItem Env:VICTORY_*)) { if ($e.Name -notin $keep) { Remove-Item "Env:$($e.Name)" } }
$settings = @{
    VICTORY_CACHE_DIR = $cache
    VICTORY_TEXTURE_NO_WAIT='1'; VICTORY_RELAY='2'; VICTORY_WIDE_BACK='1'; VICTORY_CARD_REHASH_RUNS='1'
    VICTORY_JOIN_COPIES='1'; VICTORY_INDIRECT_WINDOW='1'; VICTORY_RELAY_COPY='1'; VICTORY_CARD_STEPS='2'
    VICTORY_INDIRECT_BATCH='2'; VICTORY_MAP_THREADS='1'; VICTORY_TITLE_PRIORITIES='0'; VICTORY_CARD_AWAKE='1'
    VICTORY_SHOW_AFTER='1'; VICTORY_AMBIENT='0.8'; VICTORY_D3D12_DRED='light'
    VICTORY_THIN='1'; VICTORY_JOIN_PARTS='8'; VICTORY_UPLOAD_AHEAD='1'
    VICTORY_PORT_CONSTANTS='1'; VICTORY_PORT_DESCRIPTORS='1'; VICTORY_PORT_CBV='1'; VICTORY_PORT_GUARD='1'
    VICTORY_UPSCALER=$Upscaler; VICTORY_OUTPUT='1920x1080'
    VICTORY_RESIDENCY='1'; VICTORY_ASYNC_SUBMIT='1'; VICTORY_LATE_WAIT='1'
    # Enter-only schedule: no movement/camera keys after world entry, so A/B phases share one scene.
    # The 20 s Enter is world entry; without it the run sits at a menu until a human presses it.
    VICTORY_KEYS='2:Enter,5:Enter,8:Enter,11:Enter,20:Enter,75:Enter,78:Enter'
    VICTORY_LOG='info'
}
if (-not $NoPanel) { $settings.VICTORY_PANEL = '1' }
# The stale pre-fix warm-bad lists refuse real gameplay compute work. The host
# size fix removed the fault they were made against. Opt in only with -Guard.
if ($Guard) { $settings.VICTORY_SKIP_WARM_BAD = '1' }
foreach ($k in $Extra.Keys) { $settings[$k] = $Extra[$k] }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }

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
