# PowerShell script to deploy the addon to the WoW directory
$SourceDir = $PSScriptRoot

# Find the .toc file in the directory
$tocFile = Get-ChildItem -Path $SourceDir -Filter "*.toc" | Select-Object -First 1

if (-not $tocFile) {
    Write-Host "Error: No .toc file found in $SourceDir" -ForegroundColor Red
    exit 1
}

# Read the Title from inside the .toc file
$titleLine = Get-Content $tocFile.FullName | Where-Object { $_ -match "^\s*##\s*Title:\s*(.*)" } | Select-Object -First 1
if ($titleLine -match "^\s*##\s*Title:\s*(.*)") {
    $addonTitle = $matches[1].Trim()
    Write-Host "Addon Title from .toc: $addonTitle" -ForegroundColor Yellow
}

# WoW requires the addon directory name to exactly match the .toc filename (BaseName)
$addonName = $tocFile.BaseName

# --- Resolve WoW AddOns path ---
$defaultWowPath = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns"
$wowPathsFile   = Join-Path $SourceDir "wow_paths.json"
$wowAddonsPath  = $null

if (Test-Path $wowPathsFile) {
    try {
        $config = Get-Content $wowPathsFile -Raw | ConvertFrom-Json
        if ($config.wowAddonPath) {
            if (Test-Path $config.wowAddonPath) {
                $wowAddonsPath = $config.wowAddonPath
                Write-Host "Using WoW AddOns path from wow_paths.json: $wowAddonsPath" -ForegroundColor Cyan
            } else {
                Write-Host "Path in wow_paths.json not found: $($config.wowAddonPath)" -ForegroundColor Yellow
                Write-Host "Falling back to default path..." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Could not parse wow_paths.json: $_" -ForegroundColor Yellow
        Write-Host "Falling back to default path..." -ForegroundColor Yellow
    }
}

if (-not $wowAddonsPath) {
    if (Test-Path $defaultWowPath) {
        $wowAddonsPath = $defaultWowPath
        Write-Host "Using default WoW AddOns path: $wowAddonsPath" -ForegroundColor Cyan
    } else {
        Write-Host "" 
        Write-Host "Error: Could not find the WoW AddOns folder." -ForegroundColor Red
        Write-Host "  Checked wow_paths.json : $(if (Test-Path $wowPathsFile) { (Get-Content $wowPathsFile -Raw | ConvertFrom-Json).wowAddonPath } else { '(file not found)' })" -ForegroundColor Red
        Write-Host "  Checked default path   : $defaultWowPath" -ForegroundColor Red
        Write-Host ""
        Write-Host "Fix: Edit wow_paths.json and set 'wowAddonPath' to your WoW AddOns folder." -ForegroundColor Yellow
        Write-Host "Example: { `"wowAddonPath`": `"D:\\Games\\World of Warcraft\\_anniversary_\\Interface\\AddOns`" }" -ForegroundColor Yellow
        exit 1
    }
}

$TargetDir = Join-Path $wowAddonsPath $addonName
Write-Host "Deploying addon '$addonName' to: $TargetDir" -ForegroundColor Cyan

# Ensure the destination directory exists
if (!(Test-Path $TargetDir)) {
    Write-Host "Creating target directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

# --- Build ignore patterns from .gitignore and .curseignore ---
$regexPatterns = @('^\.git(/|$)', '^\.gitignore$', '^\.curseignore$', '^wow_paths\.json$')

function Add-IgnoreFile($ignorePath) {
    if (Test-Path $ignorePath) {
        Write-Host "Reading rules from $(Split-Path $ignorePath -Leaf)..." -ForegroundColor Gray
        $lines = Get-Content $ignorePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
        foreach ($line in $lines) {
            $line = $line.Trim().Replace('\', '/')

            $isRooted = $line.StartsWith('/')
            if ($isRooted) { $line = $line.Substring(1) }

            $isDir = $line.EndsWith('/')
            if ($isDir) { $line = $line.Substring(0, $line.Length - 1) }

            $regex = [regex]::Escape($line)
            # Restore glob wildcards after escaping
            $regex = $regex -replace '\\\*', '.*'
            $regex = $regex -replace '\\\?', '.'

            if ($isRooted) { $regex = '^' + $regex }
            else            { $regex = '(^|/)' + $regex }

            if ($isDir) { $regex = $regex + '(/|$)' }
            else        { $regex = $regex + '($|/)' }

            $script:regexPatterns += $regex
        }
    }
}

Add-IgnoreFile (Join-Path $SourceDir ".gitignore")
Add-IgnoreFile (Join-Path $SourceDir ".curseignore")

# --- Copy files ---
$allFiles   = Get-ChildItem -Path $SourceDir -File -Recurse
$filesToCopy = @()

foreach ($file in $allFiles) {
    $relativePath = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/').Replace('\', '/')

    $shouldIgnore = $false
    foreach ($pattern in $regexPatterns) {
        if ($relativePath -match $pattern) {
            $shouldIgnore = $true
            break
        }
    }

    if (-not $shouldIgnore) {
        $filesToCopy += $relativePath
    }
}

foreach ($file in $filesToCopy) {
    $fullSourcePath = Join-Path $SourceDir $file
    $fullTargetPath = Join-Path $TargetDir $file

    $targetParentDir = Split-Path $fullTargetPath
    if (!(Test-Path $targetParentDir)) {
        New-Item -ItemType Directory -Force -Path $targetParentDir | Out-Null
    }

    Write-Host "Copying $file..."
    Copy-Item -Path $fullSourcePath -Destination $fullTargetPath -Force
}

Write-Host "Deployment successful!" -ForegroundColor Green
