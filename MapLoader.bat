<# :
@echo off
title Splitgate MapLoader
setlocal
chcp 65001 >nul

set "BASEDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b %errorlevel%
#>

# ╔════════════════════════════════════════════════════════════════════════════════════════════════════════[─]═[□]═[×]═╗ 
# ║ Splitgate-MapLoader                                                                                                ║ 
# ╠══════════════════════════╦═════════════════════════════════════════════════════════════════════════════════════════╣ 
# ║ Script:                  ║ MapLoader                                                                               ║ 
# ║ Version:                 ║ 3.0.0                                                                                   ║ 
# ║ Author:                  ║ AI                                                                                      ║ 
# ╚══════════════════════════╩═════════════════════════════════════════════════════════════════════════════════════════╝ 
#
# NOTE ON BACKUPS: the backup step only ever copies native map/prefab
# subfolders - flat community .bin files are intentionally skipped, since
# they're just rebuilt from your Splitgate-CommunityMaps source whenever
# needed and aren't unique, irreplaceable data the way your own in-editor
# maps are. That also means the backup-timing concern from earlier versions
# doesn't apply anymore: whether a community .bin was added before or after
# you ran this script makes no difference to what gets backed up.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Prefix added to the display name of every community (flat .bin) map -
# these are the ones sitting directly in MapCreator/MapCreatorPrefab rather
# than in a subfolder, i.e. anything you imported rather than made yourself
# in-editor. Change freely - e.g. "[UGC]", "[Community]", "[SGAR]"
$communityTag = "[P]"

$root = $env:BASEDIR
$manifestPath = Join-Path $root "CloudSaveManifest.json"
$contentTypes = @("MapCreator", "MapCreatorPrefab")

function Get-IsoNow {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

# Splitgate manifests show up in the wild as either UTF-16LE with a
# BOM, or plain UTF-8 without one. Detect which, so we read/write
# using whatever the file actually is instead of assuming one.
function Get-ManifestEncoding {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode  # UTF-16LE with BOM
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return New-Object System.Text.UTF8Encoding($true)  # UTF-8 with BOM
    }
    return New-Object System.Text.UTF8Encoding($false)  # plain UTF-8, no BOM
}

# Encoding to use for a brand-new manifest (none exists yet). Plain
# UTF-8 without BOM appears to be the game's own default format.
$manifestEncoding = New-Object System.Text.UTF8Encoding($false)

# Windows PowerShell 5.1's ConvertTo-Json produces ugly, inconsistent
# indentation and double spaces after colons. This reformats compact
# JSON with clean, consistent 2-space indentation instead.
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

# Reads Info.json packed inside a .bin (flat community map), if present.
# Case-insensitive entry name match since ZIP entry names are case-sensitive
# by spec but different tools may have packed it as "info.json" or "Info.json".
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

# A community (flat) entry always has one Save with SaveId "custom-map" -
# that's our fixed convention for the flat file's own save slot. This stays
# true even if a native save gets added to the SAME entry later (which
# happens when you edit an imported map in-editor: the game adds a new
# subfolder-based save right into the existing Files[] entry instead of
# creating a separate one) - so this check, not path-depth, is what decides
# whether the mirror-delete / OwnerId-sampling logic should touch an entry.
function Test-IsCommunityEntry {
    param($ManifestEntry)
    if (-not $ManifestEntry.Saves) { return $false }
    return ($ManifestEntry.Saves | Where-Object { $_.SaveId -eq "custom-map" }).Count -gt 0
}

# ╠════ PART 1: Backup ════════════════════════════════════════════════════════════════════════════════════════════════╣
# ║ Backs up native map/prefab subfolders and the manifest into a dated                                                ║
# ║ Backup/<yyyy-MM-dd>-Backup/ folder. Flat community .bin files are skipped                                          ║
# ║ on purpose - see the note at the top of this file.                                                                 ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
$answer = Read-Host "Do you want to back up your current MapCreator / MapCreatorPrefab folders (and the manifest) first? (Y/N)"
if ($answer -match '^[Yy]') {
    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $backupRoot = Join-Path $root "Backup"
    $backupDest = Join-Path $backupRoot "$dateStr-Backup"

    if (-not (Test-Path $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory | Out-Null
    }
    if (Test-Path $backupDest) {
        Write-Host "A backup for today already exists, overwriting it: $backupDest"
        Remove-Item -Path $backupDest -Recurse -Force
    }
    New-Item -Path $backupDest -ItemType Directory | Out-Null

    foreach ($folderName in $contentTypes) {
        $source = Join-Path $root $folderName
        if (Test-Path $source) {
            $nativeFolders = Get-ChildItem -Path $source -Directory
            if ($nativeFolders.Count -eq 0) {
                Write-Host "Skipping backup of $folderName (no native map folders - only community .bin files, which are skipped since they're reproducible from your map source)"
            } else {
                Write-Host "Backing up $folderName (native maps only - community .bin files are skipped) ..."
                $destFolder = Join-Path $backupDest $folderName
                New-Item -Path $destFolder -ItemType Directory | Out-Null
                foreach ($nativeFolder in $nativeFolders) {
                    Copy-Item -Path $nativeFolder.FullName -Destination (Join-Path $destFolder $nativeFolder.Name) -Recurse -Force
                }
            }
        } else {
            Write-Host "Skipping backup of $folderName (folder not found)"
        }
    }

    if (Test-Path $manifestPath) {
        Copy-Item -Path $manifestPath -Destination (Join-Path $backupDest "CloudSaveManifest.json") -Force
        Write-Host "Backed up CloudSaveManifest.json"
    }

    Write-Host "Backup done: $backupDest"
} else {
    Write-Host "Skipping backup."
}
Write-Host ""

# ╠════ PART 2: Read The Existing Manifest ════════════════════════════════════════════════════════════════════════════╣
# ║ Parsed with whatever encoding it actually has. Aborts loudly instead of                                            ║
# ║ silently continuing if it can't be parsed, so a bad file never gets                                                ║
# ║ overwritten with garbage.                                                                                          ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
$existingById = @{}
$manifestVersion = 1
$hasSyncedFromBackend = $true

if (Test-Path $manifestPath) {
    Write-Host "Reading existing manifest..."
    try {
        $manifestEncoding = Get-ManifestEncoding -Path $manifestPath
        $raw = [System.IO.File]::ReadAllText($manifestPath, $manifestEncoding)
        $existing = ConvertFrom-Json -InputObject $raw
    } catch {
        Write-Host ""
        Write-Host "[ABORTED] Could not parse the existing CloudSaveManifest.json as JSON." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Nothing was changed. Fix the JSON manually (or restore a backup) and run this again." -ForegroundColor Red
        pause
        exit 1
    }

    if ($null -eq $existing -or $null -eq $existing.Version -or $null -eq $existing.Files) {
        Write-Host ""
        Write-Host "[ABORTED] The existing manifest parsed, but is missing expected fields (Version/Files)." -ForegroundColor Red
        Write-Host "Nothing was changed. Please check CloudSaveManifest.json manually." -ForegroundColor Red
        pause
        exit 1
    }

    $manifestVersion = $existing.Version
    $hasSyncedFromBackend = $existing.HasSyncedFromBackend
    foreach ($f in $existing.Files) {
        $existingById[$f.FileId] = $f
    }
    Write-Host "  Parsed OK: Version=$manifestVersion, $($existingById.Count) existing entries."
} else {
    Write-Host "No existing manifest found, creating a new one."
}

# --- Figure out a default OwnerId from YOUR OWN native maps only ---
# Flat (community) entries belong to someone else, so they must never be
# used to guess your own OwnerId - only subfolder-based native entries count.
$defaultOwnerId = $null
if ($existingById.Count -gt 0) {
    $nativeOwnerIds = @($existingById.Values | Where-Object { -not (Test-IsCommunityEntry $_) } | ForEach-Object { $_.OwnerId })
    if ($nativeOwnerIds.Count -gt 0) {
        $defaultOwnerId = ($nativeOwnerIds | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
    } else {
        Write-Warning "Every existing entry looks like a community (flat) map - falling back to the most common OwnerId overall."
        $defaultOwnerId = ($existingById.Values | Group-Object OwnerId | Sort-Object Count -Descending | Select-Object -First 1).Name
    }
}
if (-not $defaultOwnerId) {
    Write-Warning "No existing OwnerId found to use as default. New entries will get an empty OwnerId - fill it in manually if needed."
    $defaultOwnerId = ""
}
Write-Host ""

# ╠════ PART 3: Scan MapCreator / MapCreatorPrefab ════════════════════════════════════════════════════════════════════╣
# ║ Subfolders = native maps, handled exactly as before. Flat .bin files placed                                        ║
# ║ directly in the folder = community maps: name/author come from an                                                 ║
# ║ Info.json packed inside the .bin itself.                                                                          ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
$newFiles = New-Object System.Collections.Generic.List[Object]
$logLines = New-Object System.Collections.Generic.List[Object]

foreach ($contentType in $contentTypes) {
    $contentDir = Join-Path $root $contentType
    if (-not (Test-Path $contentDir)) {
        Write-Host "Skipping $contentType (folder not found)"
        continue
    }

    # Collect FileIds from BOTH a native subfolder AND a flat community
    # .bin - they can be the SAME FileId (this happens when you edit an
    # imported map in-editor: the game adds the new native save right into
    # the existing entry instead of creating a separate one). Processing
    # them together, keyed by FileId, is what avoids ending up with two
    # Files[] entries sharing one FileId - which the game can't handle
    # sensibly either way.
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

        # --- native saves, if a subfolder exists for this FileId ---
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

        # --- flat community save, if a matching .bin sits directly in the folder ---
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

        # A FileId that HAS a flat community save now, or HAD one before (a
        # "custom-map" Save recorded in the existing manifest), stays
        # community-origin even if a native save got added alongside it
        # later - so it stays out of OwnerId sampling either way.
        if (-not $hasCommunityComponent -and $existingEntry) {
            $hasCommunityComponent = Test-IsCommunityEntry $existingEntry
        }

        if ($existingEntry) {
            $fileName          = $existingEntry.FileName
            $ownerId           = $existingEntry.OwnerId
            $authorDisplayName = $existingEntry.AuthorDisplayName
            $createdAtTop      = $existingEntry.CreatedAt
            $logAction         = "UPDATED"
        } else {
            $fileName          = if ($hasCommunityComponent) { "$communityTag $fileId" } else { $fileId }
            $ownerId           = $defaultOwnerId
            $authorDisplayName = ""
            $createdAtTop      = Get-IsoNow
            $logAction         = "NEW"
        }

        # Info.json packed inside the .bin (if present/parseable) wins for name/author
        if ($info -and $info.name) {
            $fileName = "$communityTag $($info.name)"
            if ($info.author) { $authorDisplayName = $info.author }
        }

        $kind = if ($hasCommunityComponent) { "community" } else { "native" }
        Write-Host "  $logAction ($kind): $fileId -> '$fileName' ($($saves.Count) save(s))"
        if ($hasCommunityComponent) {
            $logLines.Add("$(Get-IsoNow),$contentType,$fileId,$logAction")
        }

        $newFiles.Add([ordered]@{
            FileId            = $fileId
            FileName          = $fileName
            ContentType       = $contentType
            OwnerId           = $ownerId
            AuthorDisplayName = $authorDisplayName
            CreatedAt         = $createdAtTop
            Saves             = $saves
        })
    }
}

# --- Log any community maps that disappeared since the last run ---
$newFileIds = @($newFiles | ForEach-Object { $_.FileId })
foreach ($old in $existingById.Values) {
    if ((Test-IsCommunityEntry $old) -and ($newFileIds -notcontains $old.FileId)) {
        Write-Host "  REMOVED (community): $($old.FileId) - .bin no longer found, dropping it from the manifest"
        $logLines.Add("$(Get-IsoNow),$($old.ContentType),$($old.FileId),REMOVED")
    }
}
Write-Host ""

# --- Sanity check: only ever guards your NATIVE maps. Community (flat) maps ---
# are expected to shrink/grow freely as you add or remove them on purpose.
$oldNativeCount = @($existingById.Values | Where-Object { -not (Test-IsCommunityEntry $_) }).Count
$newNativeCount = @($newFiles | Where-Object { -not (Test-IsCommunityEntry $_) }).Count
if ($oldNativeCount -gt 0 -and $newNativeCount -lt ($oldNativeCount / 2)) {
    Write-Host ""
    Write-Host "[ABORTED] Safety check failed: found only $newNativeCount native map folders," -ForegroundColor Red
    Write-Host "but the existing manifest had $oldNativeCount. That looks like your MapCreator" -ForegroundColor Red
    Write-Host "drive/folder isn't fully there rather than genuinely emptied. Nothing was written." -ForegroundColor Red
    pause
    exit 1
}

# ╠════ PART 4: Write The Manifest ════════════════════════════════════════════════════════════════════════════════════╣
# ║ Clean 2-space JSON, written back using whatever encoding the original                                              ║
# ║ file had (or plain UTF-8 for a brand-new one). A dated manifest backup                                             ║
# ║ and the import/removal log both live under Backup/.                                                                ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
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
    $logPath = Join-Path $backupRoot "manifest-log.csv"
    if (-not (Test-Path $logPath)) {
        "Timestamp,ContentType,FileId,Action" | Set-Content -Path $logPath -Encoding UTF8
    }
    $logLines | Add-Content -Path $logPath -Encoding UTF8
}

if (Test-Path $manifestPath) {
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $backupPath = Join-Path $backupRoot "CloudSaveManifest.$stamp.bak"
    Copy-Item -Path $manifestPath -Destination $backupPath -Force
    Write-Host "Manifest backup written: $backupPath"
}

[System.IO.File]::WriteAllText($manifestPath, $json, $manifestEncoding)

Write-Host ""
Write-Host "Done. Manifest updated: $manifestPath"
Write-Host "Total entries: $($newFiles.Count)  ($newNativeCount native, $($newFiles.Count - $newNativeCount) community)"
pause