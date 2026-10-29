<# :
@echo off
title Splitgate MapLoader
setlocal
chcp 65001 >nul
set "BATCH_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b %errorlevel%
#>

# ╔════════════════════════════════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗ 
# ║ Splitgate-MapLoader                                                                                                ║ 
# ╠══════════════════════════╦═════════════════════════════════════════════════════════════════════════════════════════╣ 
# ║ Script:                  ║ MapLoader                                                                               ║ 
# ║ Version:                 ║ 3.4.0                                                                                   ║ 
# ║ Author:                  ║ AI                                                                                      ║ 
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝ 

$msg = @{
    AutoPathFound     = "Automatically found Splitgate CloudSave folder:"
    PathNotFound      = "Splitgate CloudSave folder not found in AppData."
    UsingCurrentDir   = "Using current directory as base:"
    SkipEmptyNative   = "  Skipping {0} (folder exists but has no .bin files inside - likely an unsaved/empty draft)"
    FolderCreated     = "Automatically created missing folder:"
    BackupPrompt      = "Do you want to back up your current MapCreator / MapCreatorPrefab folders (and the manifest) first? (Y/N)"
    BackupExists      = "A backup for today already exists, overwriting it:"
    BackupNative      = "Backing up native maps only ..."
    SkipBackupFolder  = "Skipping backup of {0} (no native map folders)"
    BackupManifest    = "Backed up CloudSaveManifest.json"
    BackupDone        = "Backup done:"
    BackupSkipped     = "Skipping backup."
    ReadingManifest   = "Reading existing manifest..."
    ParseError        = "[ABORTED] Could not parse the existing CloudSaveManifest.json as JSON."
    MissingFields     = "[ABORTED] The existing manifest parsed, but is missing expected fields (Version/Files)."
    ParsedOk          = "  Parsed OK: Version={0}, {1} existing entries."
    NoManifest        = "No existing manifest found. Creating a new one automatically."
    NoOwnerIdNote     = "Note: No existing OwnerId found anywhere. New entries will be created without an OwnerId field."
    ActionUpdated     = "UPDATED"
    ActionNew         = "NEW"
    ActionRemoved     = "REMOVED (community): {0} - .bin no longer found, dropping it from the manifest"
    DoneSuccess       = "Done. Manifest updated:"
    TotalEntries      = "Total entries: {0} ({1} native, {2} community)"
    FirstRunBackup    = "First run detected - it's strongly recommended to back up before continuing."
    PackScanning      = "Scanning for pack files (.sgmaps / .sgprefabs / .sgmixed) and loose/misplaced .bin files..."
    PackFound         = "Found pack: {0}"
    PackItemImported  = "    Imported: {0} -> {1}"
    PackItemMoved     = "    Moved: {0} ({1} -> {2})"
    PackItemSkipped   = "    Skipped: {0} (already exists in {1})"
    PackItemUnknown   = "    Skipped: {0} (couldn't determine type - no World.cf1047 / Prefab.cf1047_prefab / payload.json found)"
    LooseBinFound     = "Found loose .bin in CloudSave root: {0}"
    MisplacedBinFound = "Found misplaced .bin in {1}: {0}"
    NoPacksFound      = "No pack files or loose/misplaced .bin files found."
    PackCleanupPrompt = "Delete the {0} processed pack file(s) now that they've been unpacked? (Y/N - 'N' moves them to Backup\Packs\ instead)"
    PackDeleted       = "Deleted: {0}"
    PackMoved         = "Moved to Backup\Packs\: {0}"
}

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$communityTag = "[P]"
$contentTypes = @("MapCreator", "MapCreatorPrefab", "CustomModes")
$contentTypeMarkers = [ordered]@{
    "World.cf1047"         = "MapCreator"
    "Prefab.cf1047_prefab" = "MapCreatorPrefab"
    "payload.json"         = "CustomModes"
}

# --- Automatic Path Detection (unabhängig vom Startort) ---
$scriptDir = if ($env:BATCH_DIR) { $env:BATCH_DIR.TrimEnd('\') } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$defaultGamePath = Join-Path $env:LOCALAPPDATA "PortalWars2\Saved\Cloud\CloudSave"

# Prüfen, ob das Skript direkt in einem CloudSave-Ordner (oder Unterordner davon) gestartet wurde
if (Test-Path (Join-Path $scriptDir "CloudSaveManifest.json")) {
    $root = $scriptDir
    Write-Host "$($msg.UsingCurrentDir) $root" -ForegroundColor Cyan
} elseif (Test-Path (Join-Path (Split-Path $scriptDir -Parent) "CloudSaveManifest.json")) {
    $root = Split-Path $scriptDir -Parent
    Write-Host "$($msg.UsingCurrentDir) $root" -ForegroundColor Cyan
} elseif (Test-Path $defaultGamePath) {
    $root = $defaultGamePath
    Write-Host "$($msg.AutoPathFound)" -ForegroundColor Green
    Write-Host "  $root" -ForegroundColor Cyan
} else {
    $root = $scriptDir
    Write-Host "$($msg.PathNotFound)" -ForegroundColor Yellow
    Write-Host "$($msg.UsingCurrentDir) $root" -ForegroundColor Yellow
}
Write-Host ""

$manifestPath = Join-Path $root "CloudSaveManifest.json"

foreach ($folderName in $contentTypes) {
    $targetDir = Join-Path $root $folderName
    if (-not (Test-Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory | Out-Null
        Write-Host "$($msg.FolderCreated) $folderName" -ForegroundColor Cyan
    }
}
Write-Host ""

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Functions & Helpers                                                                     ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

function Get-IsoNow {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

function Get-ManifestEncoding {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return New-Object System.Text.UTF8Encoding($false) }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return New-Object System.Text.UTF8Encoding($true)
    }
    return New-Object System.Text.UTF8Encoding($false)
}

$manifestEncoding = New-Object System.Text.UTF8Encoding($false)

function Format-Json {
    param([string]$Json)
    $indent = 0
    $sb = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $chars = $Json.ToCharArray()

    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]

        if ($escaped) { [void]$sb.Append($ch); $escaped = $false; continue }
        if ($ch -eq '\' -and $inString) { [void]$sb.Append($ch); $escaped = $true; continue }
        if ($ch -eq '"') { $inString = -not $inString; [void]$sb.Append($ch); continue }
        if ($inString) { [void]$sb.Append($ch); continue }

        switch ($ch) {
            '{' {
                $next = if ($i + 1 -lt $chars.Length) { $chars[$i + 1] } else { $null }
                if ($next -eq '}') { [void]$sb.Append('{}'); $i++ }
                else { $indent++; [void]$sb.Append("{`r`n" + (' ' * ($indent * 2))) }
            }
            '[' {
                $next = if ($i + 1 -lt $chars.Length) { $chars[$i + 1] } else { $null }
                if ($next -eq ']') { [void]$sb.Append('[]'); $i++ }
                else { $indent++; [void]$sb.Append("[`r`n" + (' ' * ($indent * 2))) }
            }
            '}' { $indent--; [void]$sb.Append("`r`n" + (' ' * ($indent * 2)) + '}') }
            ']' { $indent--; [void]$sb.Append("`r`n" + (' ' * ($indent * 2)) + ']') }
            ',' { [void]$sb.Append(",`r`n" + (' ' * ($indent * 2))) }
            ':' { [void]$sb.Append(': ') }
            default { [void]$sb.Append($ch) }
        }
    }
    return $sb.ToString()
}

function Get-InfoJsonFromBin {
    param([string]$BinPath)
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($BinPath)
        try {
            $entry = $zip.Entries | Where-Object { [System.IO.Path]::GetFileName($_.FullName) -ieq "info.json" } | Select-Object -First 1
            if (-not $entry) { return $null }
            $stream = $entry.Open()
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                $text = $reader.ReadToEnd()
            } finally {
                $stream.Dispose()
            }
            return ConvertFrom-Json -InputObject $text
        } finally {
            $zip.Dispose()
        }
    } catch {
        Write-Warning "  Could not read info.json from $(Split-Path -Leaf $BinPath): $($_.Exception.Message)"
        return $null
    }
}

function Get-ContentTypeFromZipArchive {
    param([System.IO.Compression.ZipArchive]$Zip)
    $names = @($Zip.Entries | ForEach-Object { [System.IO.Path]::GetFileName($_.FullName) })
    foreach ($marker in $contentTypeMarkers.Keys) {
        foreach ($n in $names) {
            if ($n -ieq $marker) { return $contentTypeMarkers[$marker] }
        }
    }
    return $null
}

function Get-ContentTypeFromBinBytes {
    param([byte[]]$Bytes)
    try {
        $ms = [System.IO.MemoryStream]::new($Bytes)
        try {
            $zip = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
            try {
                return Get-ContentTypeFromZipArchive -Zip $zip
            } finally { $zip.Dispose() }
        } finally { $ms.Dispose() }
    } catch {
        return $null
    }
}

function Get-ContentTypeFromBinFile {
    param([string]$Path)
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            return Get-ContentTypeFromZipArchive -Zip $zip
        } finally { $zip.Dispose() }
    } catch {
        return $null
    }
}

function Add-ZipCommentBytes {
    param([byte[]]$Bytes, [string]$Comment)
    $commentBytes = [System.Text.Encoding]::ASCII.GetBytes($Comment)
    $eocdPos = -1
    for ($i = $Bytes.Length - 22; $i -ge 0; $i--) {
        if ($Bytes[$i] -eq 0x50 -and $Bytes[$i+1] -eq 0x4B -and $Bytes[$i+2] -eq 0x05 -and $Bytes[$i+3] -eq 0x06) {
            $eocdPos = $i
            break
        }
    }
    if ($eocdPos -eq -1) { return $Bytes }
    $head = $Bytes[0..($eocdPos + 19)]
    $newLen = [System.BitConverter]::GetBytes([UInt16]$commentBytes.Length)
    $result = New-Object byte[] ($head.Length + 2 + $commentBytes.Length)
    [Array]::Copy($head, 0, $result, 0, $head.Length)
    [Array]::Copy($newLen, 0, $result, $head.Length, 2)
    [Array]::Copy($commentBytes, 0, $result, $head.Length + 2, $commentBytes.Length)
    return $result
}

function Save-RoutedBin {
    param([string]$Root, [string]$ContentType, [string]$ItemName, [byte[]]$Bytes)
    $destDir = Join-Path $Root $ContentType
    if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory | Out-Null }
    $destPath = Join-Path $destDir "$ItemName.bin"
    if (Test-Path $destPath) {
        Write-Host ($msg.PackItemSkipped -f $ItemName, $ContentType)
        return $false
    }
    [System.IO.File]::WriteAllBytes($destPath, $Bytes)
    Write-Host ($msg.PackItemImported -f $ItemName, $ContentType)
    return $true
}

function Expand-Pack {
    param([string]$PackPath, [string]$Root)
    $ext = [System.IO.Path]::GetExtension($PackPath).ToLower()
    $fallbackType = switch ($ext) {
        ".sgmaps"    { "MapCreator" }
        ".sgprefabs" { "MapCreatorPrefab" }
        default      { $null }
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackPath)
    try {
        # Prüfen, ob eine der enthaltenen Dateien selbst ein .bin-Archiv ist
        $hasNestedBins = ($archive.Entries | Where-Object { $_.Name -match '\.bin$' } | Select-Object -First 1) -ne $null
        $folderStyleEntry = $archive.Entries | Where-Object { $_.FullName -match '[/\\]' } | Select-Object -First 1

        if (-not $hasNestedBins -and $folderStyleEntry) {
            # --- Folder-per-item: Einträge sind in Unterordnern gruppiert ---
            $groups = $archive.Entries | Where-Object { $_.FullName -match '[/\\]' -and $_.Name -ne '' } |
                Group-Object { ($_.FullName -split '[/\\]')[0] }

            foreach ($group in $groups) {
                $itemName = $group.Name
                $ms = New-Object System.IO.MemoryStream
                $newZip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
                foreach ($entry in $group.Group) {
                    $entryName = [System.IO.Path]::GetFileName($entry.FullName)
                    if ([string]::IsNullOrEmpty($entryName)) { continue }
                    $newEntry = $newZip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
                    $src = $entry.Open()
                    $dst = $newEntry.Open()
                    $src.CopyTo($dst)
                    $dst.Dispose()
                    $src.Dispose()
                }
                $newZip.Dispose()
                $bytes = Add-ZipCommentBytes -Bytes $ms.ToArray() -Comment "Packed by CreativeCore1047"
                $ms.Dispose()

                $contentType = Get-ContentTypeFromBinBytes -Bytes $bytes
                if (-not $contentType) { $contentType = $fallbackType }
                if (-not $contentType) {
                    Write-Host ($msg.PackItemUnknown -f $itemName)
                    continue
                }
                Save-RoutedBin -Root $Root -ContentType $contentType -ItemName $itemName -Bytes $bytes | Out-Null
            }
        } else {
            # --- Nested zip per item: Jede enthaltene Datei ist eine eigene .bin ---
            foreach ($entry in $archive.Entries) {
                $entryFileName = [System.IO.Path]::GetFileName($entry.FullName)
                if ([string]::IsNullOrEmpty($entryFileName)) { continue }
                $itemName = [System.IO.Path]::GetFileNameWithoutExtension($entryFileName)

                $stream = $entry.Open()
                $ms = New-Object System.IO.MemoryStream
                $stream.CopyTo($ms)
                $stream.Dispose()
                $bytes = $ms.ToArray()
                $ms.Dispose()

                if ($bytes.Length -lt 4 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
                    continue
                }

                $contentType = Get-ContentTypeFromBinBytes -Bytes $bytes
                if (-not $contentType) { $contentType = $fallbackType }
                if (-not $contentType) {
                    Write-Host ($msg.PackItemUnknown -f $itemName)
                    continue
                }
                Save-RoutedBin -Root $Root -ContentType $contentType -ItemName $itemName -Bytes $bytes | Out-Null
            }
        }
    } finally {
        $archive.Dispose()
    }
}

function Test-IsCommunityEntry {
    param($ManifestEntry)
    if (-not $ManifestEntry.Saves) { return $false }
    return @($ManifestEntry.Saves | Where-Object { $_.SaveId -eq "custom-map" }).Count -gt 0
}

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Part 1: Backup                                                                          ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$backupRoot = Join-Path $root "Backup"
$isFirstRun = -not (Test-Path $backupRoot)

if ($isFirstRun) {
    Write-Host "$($msg.FirstRunBackup)" -ForegroundColor Cyan
    $answer = Read-Host "$($msg.BackupPrompt)"
} else {
    $answer = "N"
}

if ($answer -match '^[Yy]') {
    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $backupDest = Join-Path $backupRoot "$dateStr-Backup"

    if (-not (Test-Path $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory | Out-Null
    }
    if (Test-Path $backupDest) {
        Write-Host "$($msg.BackupExists) $backupDest"
        Remove-Item -Path $backupDest -Recurse -Force
    }
    New-Item -Path $backupDest -ItemType Directory | Out-Null

    foreach ($folderName in $contentTypes) {
        $source = Join-Path $root $folderName
        if (Test-Path $source) {
            $nativeFolders = @(Get-ChildItem -Path $source -Directory)
            if ($nativeFolders.Count -eq 0) {
                Write-Host ($msg.SkipBackupFolder -f $folderName)
            } else {
                Write-Host "$($msg.BackupNative)"
                $destFolder = Join-Path $backupDest $folderName
                New-Item -Path $destFolder -ItemType Directory | Out-Null
                foreach ($nativeFolder in $nativeFolders) {
                    Copy-Item -Path $nativeFolder.FullName -Destination (Join-Path $destFolder $nativeFolder.Name) -Recurse -Force
                }
            }
        }
    }

    if (Test-Path $manifestPath) {
        Copy-Item -Path $manifestPath -Destination (Join-Path $backupDest "CloudSaveManifest.json") -Force
        Write-Host "$($msg.BackupManifest)"
    }

    Write-Host "$($msg.BackupDone) $backupDest"
} elseif ($isFirstRun) {
    Write-Host "$($msg.BackupSkipped)"
}

if (-not (Test-Path $backupRoot)) {
    New-Item -Path $backupRoot -ItemType Directory | Out-Null
}
Write-Host ""

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Part 2: Read Existing Manifest                                                          ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$existingById = @{}
$manifestVersion = 1
$hasSyncedFromBackend = $true

if (Test-Path $manifestPath) {
    Write-Host "$($msg.ReadingManifest)"
    try {
        $manifestEncoding = Get-ManifestEncoding -Path $manifestPath
        $raw = [System.IO.File]::ReadAllText($manifestPath, $manifestEncoding)
        $existing = ConvertFrom-Json -InputObject $raw
    } catch {
        Write-Host ""
        Write-Host "$($msg.ParseError)" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        pause
        exit 1
    }

    if ($null -ne $existing) {
        if ($null -ne $existing.Version) { $manifestVersion = $existing.Version }
        if ($null -ne $existing.HasSyncedFromBackend) { $hasSyncedFromBackend = $existing.HasSyncedFromBackend }
        if ($null -ne $existing.Files) {
            foreach ($f in $existing.Files) {
                $existingById[$f.FileId] = $f
            }
        }
    }
    Write-Host ($msg.ParsedOk -f $manifestVersion, $($existingById.Count))
} else {
    Write-Host "$($msg.NoManifest)"
}

$defaultOwnerId = $null
if ($existingById.Count -gt 0) {
    $nativeOwnerIds = @($existingById.Values | Where-Object { -not (Test-IsCommunityEntry $_) -and $_.PSObject.Properties['OwnerId'] -and -not [string]::IsNullOrEmpty($_.OwnerId) } | ForEach-Object { $_.OwnerId })
    if ($nativeOwnerIds.Count -gt 0) {
        $defaultOwnerId = ($nativeOwnerIds | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
    } else {
        $fallbackOwnerIds = @($existingById.Values | Where-Object { $_.PSObject.Properties['OwnerId'] -and -not [string]::IsNullOrEmpty($_.OwnerId) } | ForEach-Object { $_.OwnerId })
        if ($fallbackOwnerIds.Count -gt 0) {
            $defaultOwnerId = ($fallbackOwnerIds | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
        }
    }
}
if (-not $defaultOwnerId) {
    Write-Host "$($msg.NoOwnerIdNote)" -ForegroundColor Yellow
}
Write-Host ""

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Part 2.5: Process Packs & Loose / Misplaced Files                                       ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

Write-Host "$($msg.PackScanning)"

$packExtensions = @("*.sgmaps", "*.sgprefabs", "*.sgmixed")
$packScanLocations = @($root) + ($contentTypes | ForEach-Object { Join-Path $root $_ })
$processedPackFiles = New-Object System.Collections.Generic.List[Object]
$foundAnything = $false

# 1. Packs (.sgmaps / .sgprefabs / .sgmixed) im Root und in allen Unterordnern entpacken
foreach ($loc in ($packScanLocations | Select-Object -Unique)) {
    if (-not (Test-Path $loc)) { continue }
    foreach ($ext in $packExtensions) {
        Get-ChildItem -Path $loc -File -Filter $ext | ForEach-Object {
            $foundAnything = $true
            Write-Host ($msg.PackFound -f $_.Name)
            Expand-Pack -PackPath $_.FullName -Root $root
            $processedPackFiles.Add($_.FullName)
        }
    }
}

# 2. Lose .bin-Dateien im CloudSave-Root prüfen und verschieben
Get-ChildItem -Path $root -File -Filter "*.bin" | ForEach-Object {
    $foundAnything = $true
    Write-Host ($msg.LooseBinFound -f $_.Name)
    $contentType = Get-ContentTypeFromBinFile -Path $_.FullName
    if (-not $contentType) {
        Write-Host ($msg.PackItemUnknown -f $_.BaseName)
        return
    }
    $destDir = Join-Path $root $contentType
    $destPath = Join-Path $destDir $_.Name
    if (Test-Path $destPath) {
        Write-Host ($msg.PackItemSkipped -f $_.BaseName, $contentType)
    } else {
        Move-Item -Path $_.FullName -Destination $destPath -Force
        Write-Host ($msg.PackItemImported -f $_.BaseName, $contentType)
    }
}

# 3. Falsch einsortierte .bin-Dateien in den Unterordnern prüfen und bei Bedarf korrigieren
foreach ($currentType in $contentTypes) {
    $dirPath = Join-Path $root $currentType
    if (-not (Test-Path $dirPath)) { continue }
    Get-ChildItem -Path $dirPath -File -Filter "*.bin" | ForEach-Object {
        $detectedType = Get-ContentTypeFromBinFile -Path $_.FullName
        if ($detectedType -and ($detectedType -ne $currentType)) {
            $foundAnything = $true
            Write-Host ($msg.MisplacedBinFound -f $_.Name, $currentType)
            $destDir = Join-Path $root $detectedType
            $destPath = Join-Path $destDir $_.Name
            if (Test-Path $destPath) {
                Write-Host ($msg.PackItemSkipped -f $_.BaseName, $detectedType)
            } else {
                Move-Item -Path $_.FullName -Destination $destPath -Force
                Write-Host ($msg.PackItemMoved -f $_.BaseName, $currentType, $detectedType)
            }
        }
    }
}

if (-not $foundAnything) {
    Write-Host "$($msg.NoPacksFound)"
}
Write-Host ""

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Part 3: Scan Folders & Build Manifest Data                                              ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$newFiles = New-Object System.Collections.Generic.List[Object]
$logLines = New-Object System.Collections.Generic.List[Object]

foreach ($contentType in $contentTypes) {
    $contentDir = Join-Path $root $contentType
    if (-not (Test-Path $contentDir)) { continue }

    $nativeFolders = @{}
    Get-ChildItem -Path $contentDir -Directory | ForEach-Object { $nativeFolders[$_.Name] = $_ }

    $flatBins = @{}
    Get-ChildItem -Path $contentDir -File -Filter "*.bin" | ForEach-Object {
        $flatBins[[System.IO.Path]::GetFileNameWithoutExtension($_.Name)] = $_
    }

    $allFileIds = @($nativeFolders.Keys) + @($flatBins.Keys) | Select-Object -Unique

    foreach ($fileId in $allFileIds) {
        $existingEntry = $existingById[$fileId]
        $saves = New-Object System.Collections.Generic.List[Object]
        $hasCommunityComponent = $false
        $info = $null

        if ($nativeFolders.ContainsKey($fileId)) {
            $folderPath = $nativeFolders[$fileId].FullName
            $binFiles = Get-ChildItem -Path $folderPath -Filter "*.bin" -File
            foreach ($bin in $binFiles) {
                $saveId = [System.IO.Path]::GetFileNameWithoutExtension($bin.Name)
                $relPath = "$contentType/$fileId/$($bin.Name)"
                $createdAt = $null
                if ($existingEntry) {
                    $existingSave = $existingEntry.Saves | Where-Object { $_.SaveId -eq $saveId }
                    if ($existingSave) { $createdAt = $existingSave.CreatedAt }
                }
                if (-not $createdAt) { $createdAt = $bin.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
                $saves.Add([ordered]@{ SaveId = $saveId; RelativePath = $relPath; SaveType = "Manual"; CreatedAt = $createdAt })
            }
        }

        if ($flatBins.ContainsKey($fileId)) {
            $hasCommunityComponent = $true
            $bin = $flatBins[$fileId]
            $info = Get-InfoJsonFromBin -BinPath $bin.FullName
            $existingSave = $null
            if ($existingEntry) {
                $existingSave = $existingEntry.Saves | Where-Object { $_.SaveId -eq "custom-map" } | Select-Object -First 1
            }
            $saveCreatedAt = if ($existingSave) { $existingSave.CreatedAt } else { $bin.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
            $saves.Add([ordered]@{ SaveId = "custom-map"; RelativePath = "$contentType/$($bin.Name)"; SaveType = "Manual"; CreatedAt = $saveCreatedAt })
        }

        if ($saves.Count -eq 0) {
            Write-Host ($msg.SkipEmptyNative -f $fileId)
            continue
        }

        if (-not $hasCommunityComponent -and $existingEntry) {
            $hasCommunityComponent = Test-IsCommunityEntry $existingEntry
        }

        if ($existingEntry) {
            $fileName          = $existingEntry.FileName
            $ownerId           = if ($existingEntry.PSObject.Properties['OwnerId']) { $existingEntry.OwnerId } else { $null }
            $authorDisplayName = $existingEntry.AuthorDisplayName
            $createdAtTop      = $existingEntry.CreatedAt
            $logAction         = $msg.ActionUpdated
        } else {
            $fileName          = if ($hasCommunityComponent) { "$communityTag $fileId" } else { $fileId }
            $ownerId           = $defaultOwnerId
            $authorDisplayName = ""
            $createdAtTop      = Get-IsoNow
            $logAction         = $msg.ActionNew
        }

        if ([string]::IsNullOrEmpty($ownerId) -and -not [string]::IsNullOrEmpty($defaultOwnerId)) {
            $ownerId = $defaultOwnerId
        }

        if ($info -and $info.name) {
            $fileName = "$communityTag $($info.name)"
            if ($info.author) { $authorDisplayName = $info.author }
        }

        $kind = if ($hasCommunityComponent) { "community" } else { "native" }
        Write-Host "  $logAction ($kind): $fileId -> '$fileName' ($($saves.Count) save(s))"
        if ($hasCommunityComponent) {
            $logLines.Add("[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$logAction] Map: $fileName ($fileId)")
        }

        $fileObject = [ordered]@{
            FileId      = $fileId
            FileName    = $fileName
            ContentType = $contentType
        }
        
        if (-not [string]::IsNullOrEmpty($ownerId)) {
            $fileObject["OwnerId"] = $ownerId
        }

        $fileObject["AuthorDisplayName"] = $authorDisplayName
        $fileObject["CreatedAt"]         = $createdAtTop
        $fileObject["Saves"]             = $saves

        $newFiles.Add($fileObject)
    }
}

$newFileIds = @($newFiles | ForEach-Object { $_.FileId })
foreach ($old in $existingById.Values) {
    if ((Test-IsCommunityEntry $old) -and ($newFileIds -notcontains $old.FileId)) {
        Write-Host ($msg.ActionRemoved -f $($old.FileId))
        $logLines.Add("[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [REMOVED] Map: $($old.FileName) ($($old.FileId))")
    }
}
Write-Host ""

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Part 4: Write Manifest & Logs                                                           ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$manifestObject = [ordered]@{
    Version              = $manifestVersion
    HasSyncedFromBackend = $hasSyncedFromBackend
    Files                = $newFiles
}

$jsonCompact = $manifestObject | ConvertTo-Json -Depth 10 -Compress
$json = Format-Json -Json $jsonCompact

if ($logLines.Count -gt 0) {
    $logPath = Join-Path $root "maploader-log.txt"
    $logLines | Add-Content -Path $logPath -Encoding UTF8
}

[System.IO.File]::WriteAllText($manifestPath, $json, $manifestEncoding)

$newNativeCount = @($newFiles | Where-Object { -not (Test-IsCommunityEntry $_) }).Count
Write-Host ""
Write-Host "$($msg.DoneSuccess) $manifestPath"
Write-Host ($msg.TotalEntries -f $($newFiles.Count), $newNativeCount, $($newFiles.Count - $newNativeCount))

if ($processedPackFiles.Count -gt 0) {
    Write-Host ""
    $cleanupAnswer = Read-Host ($msg.PackCleanupPrompt -f $processedPackFiles.Count)
    foreach ($packFile in $processedPackFiles) {
        if ($cleanupAnswer -match '^[Yy]') {
            Remove-Item -Path $packFile -Force
            Write-Host ($msg.PackDeleted -f (Split-Path -Leaf $packFile))
        } else {
            $packsBackupDir = Join-Path $backupRoot "Packs"
            if (-not (Test-Path $packsBackupDir)) { New-Item -Path $packsBackupDir -ItemType Directory | Out-Null }
            $destPath = Join-Path $packsBackupDir (Split-Path -Leaf $packFile)
            if (Test-Path $destPath) { Remove-Item -Path $destPath -Force }
            Move-Item -Path $packFile -Destination $destPath -Force
            Write-Host ($msg.PackMoved -f (Split-Path -Leaf $packFile))
        }
    }
}

pause