param(
    [string] $Cache = 'C:\mygame\victory-work\victory-9070-cache-v3-fixed',
    [string] $Binary = 'C:\mygame\victory-work\VIctory-9070-EXPERIMENTAL\target\diag\victory.exe',
    [string] $Upscaler = '6',
    [hashtable] $Extra = @{},
    [switch] $All,
    [switch] $Warm,
    [switch] $Again,
    [int] $Jobs = 0,
    [int] $Limit = 0
)

. (Join-Path $PSScriptRoot 'harness-env.ps1')

if (-not [System.IO.Path]::IsPathRooted($Binary)) { $Binary = Join-Path (Split-Path $PSScriptRoot -Parent) $Binary }
$settings = Get-HarnessSettings -Upscaler $Upscaler -Extra $Extra
Set-HarnessEnvironment -Cache $Cache -Settings $settings

$arguments = @('warm')
if (-not $All) { $arguments += @('--used') }
if ($Limit -gt 0) {
    $arguments += @('--limit', "$Limit")
} elseif (-not ($Warm -or $All)) {
    # A probe makes nothing but still prints the fingerprint and counts.
    $arguments += @('--limit', '0')
}
if ($Again) { $arguments += @('--again') }
if ($Jobs -gt 0) { $arguments += @('--jobs', "$Jobs") }

"cache=$Cache binary=$Binary args=$($arguments -join ' ')"
& $Binary @arguments
exit $LASTEXITCODE
