# Deploy the addon to every configured WoW client.
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
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

# Resolve all destinations before modifying any installation.
$wowPathsFile = Join-Path $SourceDir "wow_paths.json"
$wowAddonPaths = @()
if (Test-Path -LiteralPath $wowPathsFile) {
    $config = Get-Content -LiteralPath $wowPathsFile -Raw | ConvertFrom-Json
    if ($config.wowAddonPaths) {
        $wowAddonPaths = @($config.wowAddonPaths)
    } elseif ($config.wowAddonPath) {
        # Keep older single-client configurations working.
        $wowAddonPaths = @($config.wowAddonPath)
    }
}
if ($wowAddonPaths.Count -eq 0) {
    $wowRoot = "C:\Program Files (x86)\World of Warcraft"
    $wowAddonPaths = @(
        (Join-Path $wowRoot "_anniversary_\Interface\AddOns"),
        (Join-Path $wowRoot "_classic_beta_\Interface\AddOns")
    )
}
$targetDirs = @()
foreach ($path in ($wowAddonPaths | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "WoW AddOns folder not found: $path. Update wow_paths.json."
    }
    $addonsRoot = (Resolve-Path -LiteralPath $path).ProviderPath.TrimEnd('\')
    if ((Split-Path $addonsRoot -Leaf) -ne 'AddOns') {
        throw "Destination must be an AddOns folder: $addonsRoot"
    }
    $targetDir = [IO.Path]::GetFullPath((Join-Path $addonsRoot $addonName))
    if ([IO.Path]::GetDirectoryName($targetDir) -ne $addonsRoot -or
        (Split-Path $targetDir -Leaf) -ne $addonName -or $targetDir -eq $SourceDir) {
        throw "Unsafe deployment target: $targetDir"
    }
    if (Test-Path -LiteralPath $targetDir) {
        $targetItem = Get-Item -LiteralPath $targetDir
        if (-not $targetItem.PSIsContainer -or
            ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Deployment target must be a normal directory: $targetDir"
        }
        if (Get-ChildItem -LiteralPath $targetDir -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            throw "Deployment target contains a link or junction: $targetDir"
        }
    }
    $targetDirs += $targetDir
}

# --- Build ignore patterns from .gitignore and .curseignore ---
$blacklistPatterns = @('^\.git(/|$)', '^\.gitignore$', '^\.curseignore$', '^wow_paths\.json$')
$whitelistPatterns = @()

function Add-IgnoreFile($ignorePath) {
    if (Test-Path $ignorePath) {
        Write-Host "Reading rules from $(Split-Path $ignorePath -Leaf)..." -ForegroundColor Gray
        $lines = Get-Content $ignorePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
        foreach ($line in $lines) {
            $line = $line.Trim().Replace('\', '/')

            $isWhitelist = $line.StartsWith('!')
            if ($isWhitelist) { $line = $line.Substring(1) }

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

            if ($isWhitelist) {
                $script:whitelistPatterns += $regex
            } else {
                $script:blacklistPatterns += $regex
            }
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

    # 1. Check if it's explicitly Whitelisted (kept)
    $isWhitelisted = $false
    foreach ($pattern in $whitelistPatterns) {
        if ($relativePath -match $pattern) {
            $isWhitelisted = $true
            break
        }
    }

    if ($isWhitelisted) {
        $filesToCopy += $relativePath
        continue
    }

    # 2. Check if it's Blacklisted (ignored)
    $isBlacklisted = $false
    foreach ($pattern in $blacklistPatterns) {
        if ($relativePath -match $pattern) {
            $isBlacklisted = $true
            break
        }
    }

    if (-not $isBlacklisted) {
        $filesToCopy += $relativePath
    }
}

function Get-ContentHash($filePath) {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $filePath).Hash
    }
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $hasher.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hashBytes).Replace('-', '')
}

foreach ($targetDir in $targetDirs) {
    Write-Host "Deploying '$addonName' to: $targetDir ($($filesToCopy.Count) files)" -ForegroundColor Cyan
    if ($DryRun) { continue }
    if (Test-Path -LiteralPath $targetDir) {
        # Only the validated addon directory is replaced; other addons and WTF are untouched.
        Get-ChildItem -LiteralPath $targetDir -Force |
            Remove-Item -Force -Recurse
    } else {
        New-Item -ItemType Directory -Path $targetDir | Out-Null
    }
    foreach ($file in $filesToCopy) {
        $fullSourcePath = Join-Path $SourceDir $file
        $fullTargetPath = Join-Path $targetDir $file
        $targetParentDir = Split-Path $fullTargetPath
        if (-not (Test-Path -LiteralPath $targetParentDir)) {
            New-Item -ItemType Directory -Force -Path $targetParentDir | Out-Null
        }
        Copy-Item -LiteralPath $fullSourcePath -Destination $fullTargetPath -Force
        if ((Get-ContentHash $fullSourcePath) -ne (Get-ContentHash $fullTargetPath)) {
            throw "Deployment verification failed: $fullTargetPath"
        }
    }
    Write-Host "Verified deployment: $targetDir" -ForegroundColor Green
}
if ($DryRun) {
    Write-Host "Dry run successful. No files changed." -ForegroundColor Green
} else {
    Write-Host "Deployment successful for all $($targetDirs.Count) clients!" -ForegroundColor Green
}
