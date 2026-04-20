# package.ps1
# Creates a versioned CurseForge zip in the WoW AddOns folder after each commit.
# Called automatically by .githooks/post-commit. Can also be run manually.

$SourceDir = $PSScriptRoot

# --- Get addon name from .toc ---
$tocFile = Get-ChildItem -Path $SourceDir -Filter "*.toc" -Depth 0 | Select-Object -First 1
if (-not $tocFile) {
    Write-Host "package.ps1: No .toc file found — skipping zip." -ForegroundColor Yellow
    exit 0
}
$addonName = $tocFile.BaseName

# --- Get short commit hash ---
$hash = git -C $SourceDir rev-parse --short HEAD 2>$null
if (-not $hash) {
    Write-Host "package.ps1: Could not read git commit hash — skipping zip." -ForegroundColor Yellow
    exit 0
}

# --- Resolve WoW AddOns path (mirrors deploy.ps1 logic) ---
$defaultWowPath = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns"
$wowPathsFile   = Join-Path $SourceDir "wow_paths.json"
$wowAddonsPath  = $null

if (Test-Path $wowPathsFile) {
    try {
        $config = Get-Content $wowPathsFile -Raw | ConvertFrom-Json
        if ($config.wowAddonPath -and (Test-Path $config.wowAddonPath)) {
            $wowAddonsPath = $config.wowAddonPath
        } else {
            Write-Host "package.ps1: Path in wow_paths.json not found, falling back to default..." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "package.ps1: Could not parse wow_paths.json, falling back to default..." -ForegroundColor Yellow
    }
}

if (-not $wowAddonsPath) {
    if (Test-Path $defaultWowPath) {
        $wowAddonsPath = $defaultWowPath
    } else {
        Write-Host "package.ps1: Could not find the WoW AddOns folder." -ForegroundColor Red
        Write-Host "  Checked wow_paths.json : $(if (Test-Path $wowPathsFile) { (Get-Content $wowPathsFile -Raw | ConvertFrom-Json).wowAddonPath } else { '(file not found)' })" -ForegroundColor Red
        Write-Host "  Checked default path   : $defaultWowPath" -ForegroundColor Red
        Write-Host "Fix: Edit wow_paths.json and set 'wowAddonPath' to your WoW AddOns folder." -ForegroundColor Yellow
        exit 1
    }
}

# --- Remove stale zips ---
$staleZips = Get-ChildItem -Path $wowAddonsPath -Filter "$addonName-*.zip" -ErrorAction SilentlyContinue
if ($staleZips) {
    foreach ($zip in $staleZips) {
        Write-Host "Removing stale zip: $($zip.Name)" -ForegroundColor Yellow
        Remove-Item $zip.FullName -Force
    }
} else {
    Write-Host "No stale zips found." -ForegroundColor Gray
}

# --- Create versioned zip ---
$addonDir = Join-Path $wowAddonsPath $addonName
if (-not (Test-Path $addonDir)) {
    Write-Host "package.ps1: Addon folder not found at '$addonDir'." -ForegroundColor Red
    Write-Host "Run deploy.ps1 first to populate the WoW AddOns folder." -ForegroundColor Yellow
    exit 1
}

$zipPath = Join-Path $wowAddonsPath "$addonName-$hash.zip"
Compress-Archive -Path $addonDir -DestinationPath $zipPath -Force
Write-Host "✅ $addonName-$hash.zip created in the AddOns folder." -ForegroundColor Green
