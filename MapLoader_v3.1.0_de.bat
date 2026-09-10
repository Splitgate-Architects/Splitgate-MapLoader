<# :
@echo off
title Splitgate MapLoader
setlocal
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b %errorlevel%
#>

# ╔════════════════════════════════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗ 
# ║ Splitgate-MapLoader                                                                                                ║ 
# ╠══════════════════════════╦═════════════════════════════════════════════════════════════════════════════════════════╣ 
# ║ Script:                  ║ MapLoader (German)                                                                      ║ 
# ║ Version:                 ║ 3.1.0                                                                                   ║ 
# ║ Author:                  ║ AI                                                                                      ║ 
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝ 


# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Localization (Centralized messages for easy translation)                                ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$msg = @{
    AutoPathFound    = "Splitgate CloudSave-Ordner automatisch gefunden:"
    PathNotFound     = "Splitgate CloudSave-Ordner im Standardpfad nicht gefunden."
    UsingCurrentDir  = "Verwende das aktuelle Skript-Verzeichnis als Basis:"
    FolderCreated    = "Fehlenden Ordner automatisch erstellt:"
    BackupPrompt     = "Möchtest du deine aktuellen MapCreator / MapCreatorPrefab Ordner (und das Manifest) zuerst sichern? (J/N)"
    BackupExists     = "Ein Backup für heute existiert bereits, es wird überschrieben:"
    BackupNative     = "Sichere nur native Maps..."
    SkipBackupFolder = "Übersichere Sicherung von {0} (keine nativen Map-Ordner)"
    BackupManifest   = "CloudSaveManifest.json gesichert."
    BackupDone       = "Backup abgeschlossen:"
    BackupSkipped    = "Backup übersprungen."
    ReadingManifest  = "Lese bestehendes Manifest..."
    ParseError       = "[ABGEBROCHEN] Das bestehende CloudSaveManifest.json konnte nicht als JSON geparst werden."
    MissingFields    = "[ABGEBROCHEN] Das Manifest wurde geparst, aber erwartete Felder (Version/Files) fehlen."
    ParsedOk         = "  Erfolgreich geparst: Version={0}, {1} bestehende Einträge."
    NoManifest       = "Kein bestehendes Manifest gefunden. Erstelle automatisch ein neues."
    NoOwnerIdNote    = "Hinweis: Keine OwnerId gefunden. Neue Einträge werden ohne OwnerId erstellt."
    ActionUpdated    = "AKTUALISIERT"
    ActionNew        = "NEU"
    ActionRemoved    = "ENTFERNT (Community): {0} - .bin nicht mehr gefunden, aus dem Manifest entfernt"
    DoneSuccess      = "Fertig. Manifest aktualisiert:"
    TotalEntries     = "Gesamteinträge: {0} ({1} native, {2} Community)"
}

# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Configuration & Environment Setup                                                       ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$communityTag = "[P]"
$contentTypes = @("MapCreator", "MapCreatorPrefab")

# --- Automatic Path Detection ---
$defaultGamePath = Join-Path $env:LOCALAPPDATA "PortalWars2\Saved\Cloud\CloudSave"

if (Test-Path $defaultGamePath) {
    $root = $defaultGamePath
    Write-Host "$($msg.AutoPathFound)" -ForegroundColor Green
    Write-Host "  $root" -ForegroundColor Cyan
} else {
    $root = $PSScriptRoot
    Write-Host "$($msg.PathNotFound)" -ForegroundColor Yellow
    Write-Host "$($msg.UsingCurrentDir) $root" -ForegroundColor Yellow
}
Write-Host ""

$manifestPath = Join-Path $root "CloudSaveManifest.json"

# --- Folder Safety: Check and create if missing ---
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
            $entry = $zip.Entries | Where-Object { $_.Name -ieq "info.json" } | Select-Object -First 1
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
        Write-Warning "  Could not read Info.json from $(Split-Path -Leaf $BinPath): $($_.Exception.Message)"
        return $null
    }
}

function Test-IsCommunityEntry {
    param($ManifestEntry)
    if (-not $ManifestEntry.Saves) { return $false }
    return ($ManifestEntry.Saves | Where-Object { $_.SaveId -eq "custom-map" }).Count -gt 0
}


# ╔══════════════════════════╦═════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗
# ║ Splitgate-MapLoader      ║ Part 1: Backup                                                                          ║
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝

$answer = Read-Host "$($msg.BackupPrompt)"
if ($answer -match '^[Yy]') {
    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $backupRoot = Join-Path $root "Backup"
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
            $nativeFolders = Get-ChildItem -Path $source -Directory
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
} else {
    Write-Host "$($msg.BackupSkipped)"
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

        # Auto-repair OwnerId if it was missing previously but found later
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
            # Log as standard text instead of CSV
            $logLines.Add("[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$logAction] Map: $fileName ($fileId)")
        }

        $fileObject = [ordered]@{
            FileId            = $fileId
            FileName          = $fileName
            ContentType       = $contentType
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
        # Log removal as standard text
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

$backupRoot = Join-Path $root "Backup"
if (-not (Test-Path $backupRoot)) {
    New-Item -Path $backupRoot -ItemType Directory | Out-Null
}

if ($logLines.Count -gt 0) {
    # Write log to main folder as a simple txt file
    $logPath = Join-Path $root "maploader-log.txt"
    $logLines | Add-Content -Path $logPath -Encoding UTF8
}

[System.IO.File]::WriteAllText($manifestPath, $json, $manifestEncoding)

$newNativeCount = @($newFiles | Where-Object { -not (Test-IsCommunityEntry $_) }).Count
Write-Host ""
Write-Host "$($msg.DoneSuccess) $manifestPath"
Write-Host ($msg.TotalEntries -f $($newFiles.Count), $newNativeCount, $($newFiles.Count - $newNativeCount))
pause