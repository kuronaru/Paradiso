param(
    [string]$GodotPath = "C:\Program Files\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe",
    [string]$ItchTarget = $env:PARADISO_ITCH_TARGET,
    [string]$ButlerPath = "butler",
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$gameRoot = Join-Path $projectRoot "game"
$buildRoot = Join-Path $projectRoot "outputs\web"
$entryPath = Join-Path $buildRoot "index.html"
$logRoot = Join-Path $gameRoot ".godot"
$logPath = Join-Path $logRoot "web-demo-export.log"

$resolvedProjectRoot = [IO.Path]::GetFullPath($projectRoot)
$resolvedBuildRoot = [IO.Path]::GetFullPath($buildRoot)
if (-not $resolvedBuildRoot.StartsWith($resolvedProjectRoot + [IO.Path]::DirectorySeparatorChar)) {
	throw "Refusing to clean a build path outside the repository: $resolvedBuildRoot"
}
if (Test-Path -LiteralPath $resolvedBuildRoot) {
    Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

Write-Host "Exporting Web Demo..."
& $GodotPath --headless --path $gameRoot --export-release "Web Demo" $entryPath --log-file $logPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot Web export failed with exit code $LASTEXITCODE. See $logPath"
}

$requiredFiles = @(
    $entryPath,
    (Join-Path $buildRoot "index.wasm"),
    (Join-Path $buildRoot "index.pck")
)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Web export is incomplete: missing $requiredFile"
    }
}

# Never publish editor metadata if another local tool created it in the output.
Get-ChildItem -LiteralPath $buildRoot -Filter "*.import" -File |
    Remove-Item -Force

$artifactSummary = Get-ChildItem -LiteralPath $buildRoot -File |
    Where-Object { $_.Name -in @("index.html", "index.wasm", "index.pck") } |
    Select-Object Name, Length
$artifactSummary | Format-Table -AutoSize

if ($SkipUpload) {
    Write-Host "Export verified. Upload skipped: $buildRoot"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ItchTarget) -or $ItchTarget -notmatch "^[^/]+/[^/]+$") {
    throw "Set -ItchTarget 'account/project' or PARADISO_ITCH_TARGET before publishing."
}

Write-Host "Publishing the existing itch.io validation channel..."
& $ButlerPath push $buildRoot "${ItchTarget}:html5-validation"
if ($LASTEXITCODE -ne 0) {
    throw "butler push failed with exit code $LASTEXITCODE."
}

Write-Host "Published ${ItchTarget}:html5-validation"
