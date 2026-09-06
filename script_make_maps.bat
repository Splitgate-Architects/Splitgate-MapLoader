<# :
@echo off
title Map Packager Automation
setlocal
chcp 65001 >nul

set "BASEDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b %errorlevel%
#>

# ============================================================
# POWERSHELL LOGIC STARTS HERE
# ============================================================
$ErrorActionPreference = "Stop"
$baseDir = $env:BASEDIR
$targetDir = Join-Path $baseDir "CommunityMaps"
$outputDir = Join-Path $baseDir "ConvertedMaps"
$comment = "Packed by CreativeCore1047"

Write-Host "Starting strict map processing..." -ForegroundColor Cyan
Write-Host "Target Directory: $targetDir" -ForegroundColor Cyan
Write-Host "Output Directory: $outputDir" -ForegroundColor Cyan
Write-Host "================================================="

if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] The folder 'CommunityMaps' does not exist in the script's directory." -ForegroundColor Red
    Write-Host "Please make sure the script is placed in the correct main folder." -ForegroundColor Yellow
    exit
}

# Create output folder if it doesn't exist yet
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$folders = Get-ChildItem -Path $targetDir -Directory
$processedCount = 0
$skippedFolders = @()

foreach ($folder in $folders) {
    $subFolder = $folder.FullName
    $readme = Join-Path $subFolder "README.md"
    $mapFile = Join-Path $subFolder "World.cf1047"
    $imgFile = Join-Path $subFolder "Screenshot.jpg"

    if ((Test-Path $readme) -and (Test-Path $mapFile) -and (Test-Path $imgFile)) {
        Write-Host "`nAnalyzing folder: $($folder.Name)" -ForegroundColor Yellow

        # Read README.md and filter out empty lines to ensure we get the real first two lines
        $lines = @(Get-Content $readme -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
        
        if ($lines.Count -lt 2) {
            Write-Host "  -> [SKIPPED] README.md does not contain enough text lines." -ForegroundColor Red
            $skippedFolders += $folder.Name
            continue
        }

        $line1 = $lines[0]
        $line2 = $lines[1]
        $mapName = ""
        $author = ""

        # Strict check on Line 1 (Map Name) and Line 2 (Author)
        if ($line1 -match "^#+\s*(.*)") {
            $mapName = $matches[1].Trim()
        }
        if ($line2 -match "(?i)^#+\s*Author:\s*(.*)") {
            $author = $matches[1].Trim()
        }

        if ([string]::IsNullOrWhiteSpace($mapName) -or [string]::IsNullOrWhiteSpace($author)) {
            Write-Host "  -> [SKIPPED] Line 1 and 2 do not match the expected naming format." -ForegroundColor Red
            $skippedFolders += $folder.Name
            continue
        }

        Write-Host "  -> Found: '$mapName' by '$author'"

        # Create info.json
        $jsonObj = [ordered]@{
            name = $mapName
            author = $author
        }
        $jsonPath = Join-Path $subFolder "info.json"
        $jsonObj | ConvertTo-Json -Depth 2 | Set-Content $jsonPath -Encoding UTF8

        # Generate filename base
        $cleanAuthor = $author.ToLower() -replace '[^a-z0-9]', ''
        $lowerMap = $mapName.ToLower().Trim()

        if ($lowerMap -match '^(.*?)\s*\((.*?)\)$') {
            $baseName = $matches[1].Trim() -replace '[^a-z0-9]', '-' -replace '-+', '-'
            $gameMode = $matches[2].Trim() -replace '[^a-z0-9]', ''
            $cleanMap = "$baseName-$gameMode"
        } else {
            $cleanMap = $lowerMap -replace '[^a-z0-9]', '-' -replace '-+', '-'
        }
        $cleanMap = $cleanMap.Trim('-')

        $binFileName = "${cleanAuthor}_${cleanMap}.bin"
        $imgFileName = "${cleanAuthor}_${cleanMap}.jpg"
        
        $zipPath = Join-Path $baseDir "temp_$($folder.Name).zip"
        $binPath = Join-Path $outputDir $binFileName
        $targetImgPath = Join-Path $outputDir $imgFileName

        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        if (Test-Path $binPath) { Remove-Item $binPath -Force }

        # Create ZIP using native Windows PowerShell command
        Push-Location $subFolder
        Compress-Archive -Path "info.json", "Screenshot.jpg", "World.cf1047" -DestinationPath $zipPath -Force
        Pop-Location

        if (Test-Path $zipPath) {
            # ZIP Comment Hex-Patching
            $bytes = [System.IO.File]::ReadAllBytes($zipPath)
            $commentBytes = [System.Text.Encoding]::ASCII.GetBytes($comment)
            $eocdPos = -1
            for ($i = $bytes.Length - 22; $i -ge 0; $i--) {
                if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
                    $eocdPos = $i
                    break
                }
            }

            if ($eocdPos -ne -1) {
                $head = $bytes[0..($eocdPos + 19)]
                $newLen = [System.BitConverter]::GetBytes([UInt16]$commentBytes.Length)
                $result = New-Object byte[] ($head.Length + 2 + $commentBytes.Length)
                [Array]::Copy($head, 0, $result, 0, $head.Length)
                [Array]::Copy($newLen, 0, $result, $head.Length, 2)
                [Array]::Copy($commentBytes, 0, $result, $head.Length + 2, $commentBytes.Length)
                [System.IO.File]::WriteAllBytes($zipPath, $result)
            } else {
                Write-Host "  -> [WARNING] Could not find signature for ZIP comment." -ForegroundColor DarkYellow
            }

            # Move and rename finished ZIP to ConvertedMaps folder as .bin
            Move-Item -Path $zipPath -Destination $binPath -Force
            
            # Copy screenshot to ConvertedMaps directory with matching name
            Copy-Item -Path $imgFile -Destination $targetImgPath -Force

            Write-Host "  -> Successfully packed: $binFileName (+ extracted JPG)" -ForegroundColor Green
            $processedCount++
        } else {
            Write-Host "  -> [ERROR] ZIP archive could not be created." -ForegroundColor Red
            $skippedFolders += $folder.Name
        }

        # Cleanup info.json from the subfolder
        if (Test-Path $jsonPath) { Remove-Item $jsonPath -Force }
    } else {
        $skippedFolders += $folder.Name
    }
}

Write-Host "`n================================================="
Write-Host "Process completed! $processedCount map(s) successfully packed." -ForegroundColor Cyan

if ($skippedFolders.Count -gt 0) {
    Write-Host "`n[NOTICE] The following $($skippedFolders.Count) folder(s) were skipped (missing files or invalid README format):" -ForegroundColor DarkGray
    foreach ($skip in $skippedFolders) {
        Write-Host " - $skip" -ForegroundColor DarkGray
    }
}