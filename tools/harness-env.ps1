function Get-HarnessSettings {
    param(
        [string] $Upscaler = '6',
        [switch] $NoPanel,
        [switch] $Guard,
        [hashtable] $Extra = @{}
    )

    $settings = @{
        VICTORY_TEXTURE_NO_WAIT='1'; VICTORY_RELAY='2'; VICTORY_WIDE_BACK='1'; VICTORY_CARD_REHASH_RUNS='1'
        VICTORY_JOIN_COPIES='1'; VICTORY_INDIRECT_WINDOW='1'; VICTORY_RELAY_COPY='1'; VICTORY_CARD_STEPS='2'
        VICTORY_INDIRECT_BATCH='2'; VICTORY_MAP_THREADS='1'; VICTORY_TITLE_PRIORITIES='0'; VICTORY_CARD_AWAKE='1'
        VICTORY_SHOW_AFTER='1'; VICTORY_AMBIENT='0.8'; VICTORY_D3D12_DRED='light'
        VICTORY_THIN='1'; VICTORY_JOIN_PARTS='8'; VICTORY_UPLOAD_AHEAD='1'
        VICTORY_PORT_CONSTANTS='1'; VICTORY_PORT_DESCRIPTORS='1'; VICTORY_PORT_CBV='1'; VICTORY_PORT_GUARD='1'
        VICTORY_UPSCALER=$Upscaler; VICTORY_OUTPUT='1920x1080'
        # Stage 3 is the A/B protocol used by copy-stages-5 and every cut run.
        # Keep it fixed across the warm run, baseline and cuts.
        VICTORY_RESIDENCY='1'; VICTORY_ASYNC_SUBMIT='1'; VICTORY_LATE_WAIT='3'
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
    return $settings
}

function Set-HarnessEnvironment {
    param(
        [string] $Cache,
        [hashtable] $Settings
    )

    $keep = @('VICTORY_CONFIG','VICTORY_GAME_DIR','VICTORY_CACHE_DIR','VICTORY_DATA_DIR')
    foreach ($e in @(Get-ChildItem Env:VICTORY_*)) { if ($e.Name -notin $keep) { Remove-Item "Env:$($e.Name)" } }
    foreach ($k in $Settings.Keys) { Set-Item "Env:$k" $Settings[$k] }
    Set-Item Env:VICTORY_CACHE_DIR $Cache
}
