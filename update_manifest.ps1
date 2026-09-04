# ============================================================
#  update_manifest.ps1  (v3)
#  Scans the MapCreator and MapCreatorPrefab folders next to
#  this script and rebuilds CloudSaveManifest.json from their
#  contents. Existing entries keep their FileName, OwnerId,
#  AuthorDisplayName and CreatedAt values; only new folders
#  get fresh defaults.
#
#  v2: aborts loudly instead of silently overwriting with bad
#  data if the existing manifest can't be parsed, and always
#  writes a timestamped backup before touching the real file.
#
#  v3: if a folder contains a "custom-map.json" file (with
#  "name" and "author" fields), that file becomes the source
#  of truth for FileName/AuthorDisplayName, and the name gets
#  prefixed with $communityTag to mark it as non-original content.
#
#  v4: asks at startup whether to back up the current state into
#  Backup/<yyyy-MM-dd>-Backup/ (MapCreator, MapCreatorPrefab, and
#  the manifest itself), overwritten if run again the same day.
#
#  v5: drop new content into CustomMaps/ or CustomPrefabs/ (auto-
#  created next to this script) instead of directly into the live
#  MapCreator/MapCreatorPrefab folders. The script backs up the
#  live folders first (a true "before" snapshot), then moves the
#  staged content in, then regenerates the manifest as usual.
#
#  v6: guided flow in clear parts - (1) first run just creates the
#  staging folders and stops with instructions, (2) backup prompt,
#  (3) a Y/N loop confirming your files are actually staged before
#  continuing, (4) import, (5) rebuild the manifest.
# ============================================================

$ErrorActionPreference = "Stop"

# Prefix added to the name of any map that has a custom-map.json
# (i.e. anything you imported rather than made yourself in-editor).
# Change freely - e.g. "[UGC]", "[Community]", "[SGAR]"
$communityTag = "[P]"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $root "CloudSaveManifest.json"
$customMapsDir = Join-Path $root "CustomMaps"
$customPrefabsDir = Join-Path $root "CustomPrefabs"

# ============================================================
#  PART 1 - First-run setup
#  Creates the staging folders if they don't exist yet and, if
#  this is genuinely the first run, stops here with instructions
#  instead of doing anything else.
# ============================================================
$isFirstRun = -not (Test-Path $customMapsDir)

if (-not (Test-Path $customMapsDir))    { New-Item -Path $customMapsDir -ItemType Directory | Out-Null }
if (-not (Test-Path $customPrefabsDir)) { New-Item -Path $customPrefabsDir -ItemType Directory | Out-Null }

if ($isFirstRun) {
    Write-Host ""
    Write-Host "=================================================================="
    Write-Host " First run - setup complete"
    Write-Host "=================================================================="
    Write-Host ""
    Write-Host " I created two folders next to this script:"
    Write-Host "   CustomMaps\      -> put new MAPS here (one subfolder per map)"
    Write-Host "   CustomPrefabs\   -> put new PREFABS here (one subfolder per prefab)"
    Write-Host ""
    Write-Host " Each map/prefab needs its own folder, e.g.:"
    Write-Host "   CustomMaps\my-new-map\custom-map.bin"
    Write-Host "   CustomMaps\my-new-map\custom-map.json   (optional: name + author)"
    Write-Host ""
    Write-Host " Go ahead and add your maps/prefabs now, then run this script again."
    Write-Host "=================================================================="
    pause
    exit 0
}

# ============================================================
#  PART 2 - Backup
# ============================================================
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

    $foldersToBackup = @("MapCreator", "MapCreatorPrefab")
    foreach ($folderName in $foldersToBackup) {
        $source = Join-Path $root $folderName
        if (Test-Path $source) {
            Write-Host "Backing up $folderName ..."
            Copy-Item -Path $source -Destination (Join-Path $backupDest $folderName) -Recurse -Force
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

# ============================================================
#  PART 3 - Confirm the staged content is ready, then continue
# ============================================================
$ready = $false
do {
    $readyAnswer = Read-Host "Are your new maps/prefabs placed inside CustomMaps / CustomPrefabs now? (Y/N)"
    if ($readyAnswer -match '^[Yy]') {
        $ready = $true
    } else {
        Write-Host "Okay - go add them to CustomMaps\ and/or CustomPrefabs\ now, then answer again."
        Write-Host ""
    }
} while (-not $ready)
Write-Host ""

function Get-IsoNow {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

# Moves everything sitting in a staging folder (CustomMaps / CustomPrefabs)
# into the real live folder the game reads from. Merges into existing
# FileId folders if one with the same name already exists there.
function Import-StagedContent {
    param(
        [string]$StagingDir,
        [string]$LiveDir,
        [string]$Label
    )

    if (-not (Test-Path $StagingDir)) {
        New-Item -Path $StagingDir -ItemType Directory | Out-Null
        return
    }

    $staged = Get-ChildItem -Path $StagingDir -Directory
    if ($staged.Count -eq 0) {
        return
    }

    if (-not (Test-Path $LiveDir)) {
        New-Item -Path $LiveDir -ItemType Directory | Out-Null
    }

    foreach ($folder in $staged) {
        $destFolder = Join-Path $LiveDir $folder.Name
        if (-not (Test-Path $destFolder)) {
            New-Item -Path $destFolder -ItemType Directory | Out-Null
        }

        Write-Host "  Importing $Label`: $($folder.Name)"
        Get-ChildItem -Path $folder.FullName -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $destFolder $_.Name) -Force
        }

        Remove-Item -Path $folder.FullName -Recurse -Force
    }
}

# ============================================================
#  PART 4 - Import staged content into the live folders
# ============================================================
Write-Host "Checking CustomMaps / CustomPrefabs for new content ..."
Import-StagedContent -StagingDir (Join-Path $root "CustomMaps") -LiveDir (Join-Path $root "MapCreator") -Label "map"
Import-StagedContent -StagingDir (Join-Path $root "CustomPrefabs") -LiveDir (Join-Path $root "MapCreatorPrefab") -Label "prefab"
Write-Host ""

# ============================================================
#  PART 5 - Rebuild the manifest from the live folders
# ============================================================
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

# --- Load existing manifest (if present) so we can preserve metadata ---
$existingById = @{}
$manifestVersion = 1
$hasSyncedFromBackend = $true
$existing = $null

if (Test-Path $manifestPath) {
    Write-Host "Reading existing manifest..."
    try {
        $raw = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::Unicode)
        $existing = ConvertFrom-Json -InputObject $raw
    } catch {
        Write-Host ""
        Write-Host "[ABORTED] Could not parse the existing CloudSaveManifest.json as JSON." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Nothing was changed. Fix the JSON manually (or restore a backup) and run this again." -ForegroundColor Red
        pause
        exit 1
    }

    # Sanity-check what we parsed before trusting it
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

# --- Figure out a default OwnerId from whatever already exists ---
$defaultOwnerId = $null
if ($existingById.Count -gt 0) {
    $defaultOwnerId = ($existingById.Values | Group-Object OwnerId | Sort-Object Count -Descending | Select-Object -First 1).Name
}
if (-not $defaultOwnerId) {
    Write-Warning "No existing OwnerId found to use as default. New entries will get an empty OwnerId - fill it in manually if needed."
    $defaultOwnerId = ""
}

$contentTypes = @("MapCreator", "MapCreatorPrefab")
$newFiles = New-Object System.Collections.Generic.List[Object]

foreach ($contentType in $contentTypes) {
    $contentDir = Join-Path $root $contentType
    if (-not (Test-Path $contentDir)) {
        Write-Host "Skipping $contentType (folder not found)"
        continue
    }

    Get-ChildItem -Path $contentDir -Directory | ForEach-Object {
        $fileId = $_.Name
        $folderPath = $_.FullName

        $binFiles = Get-ChildItem -Path $folderPath -Filter "*.bin" -File
        if ($binFiles.Count -eq 0) {
            Write-Host "  Skipping $fileId (no .bin files inside)"
            return
        }

        $existingEntry = $existingById[$fileId]

        # --- Check for a custom-map.json in this folder (name/author override) ---
        $customInfo = $null
        $customJsonPath = Join-Path $folderPath "custom-map.json"
        if (Test-Path $customJsonPath) {
            try {
                $customRaw = [System.IO.File]::ReadAllText($customJsonPath)
                $customInfo = ConvertFrom-Json -InputObject $customRaw
                if (-not $customInfo.name) {
                    Write-Warning "  $fileId`: custom-map.json has no 'name' field, ignoring it."
                    $customInfo = $null
                }
            } catch {
                Write-Warning "  $fileId`: could not parse custom-map.json ($($_.Exception.Message)), ignoring it."
                $customInfo = $null
            }
        }

        # --- Build the Saves array from whatever .bin files actually exist ---
        $saves = New-Object System.Collections.Generic.List[Object]
        foreach ($bin in $binFiles) {
            $saveId = [System.IO.Path]::GetFileNameWithoutExtension($bin.Name)
            $relPath = "$contentType/$fileId/$($bin.Name)"

            $createdAt = $null
            if ($existingEntry) {
                $existingSave = $existingEntry.Saves | Where-Object { $_.SaveId -eq $saveId }
                if ($existingSave) { $createdAt = $existingSave.CreatedAt }
            }
            if (-not $createdAt) {
                $createdAt = $bin.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }

            $saves.Add([ordered]@{
                SaveId       = $saveId
                RelativePath = $relPath
                SaveType     = "Manual"
                CreatedAt    = $createdAt
            })
        }

        # --- Reuse metadata if the entry already existed, else set defaults ---
        if ($existingEntry) {
            $fileName          = $existingEntry.FileName
            $ownerId           = $existingEntry.OwnerId
            $authorDisplayName = $existingEntry.AuthorDisplayName
            $createdAtTop      = $existingEntry.CreatedAt
            $logPrefix         = "  Updated:"
        } else {
            $fileName          = $fileId
            $ownerId           = $defaultOwnerId
            $authorDisplayName = ""
            $createdAtTop      = Get-IsoNow
            $logPrefix         = "  NEW:    "
        }

        # --- custom-map.json (if present) wins over everything above for name/author ---
        if ($customInfo) {
            $fileName = "$communityTag $($customInfo.name)"
            if ($customInfo.author) { $authorDisplayName = $customInfo.author }
            $logPrefix = "$logPrefix (custom-map.json)"
        }

        Write-Host "$logPrefix $fileId -> '$fileName' ($($binFiles.Count) save(s))"

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

# --- Sanity check before overwriting anything ---
if ($existingById.Count -gt 0 -and $newFiles.Count -lt ($existingById.Count / 2)) {
    Write-Host ""
    Write-Host "[ABORTED] Safety check failed: found only $($newFiles.Count) entries on disk," -ForegroundColor Red
    Write-Host "but the existing manifest had $($existingById.Count). That looks like folders" -ForegroundColor Red
    Write-Host "are missing rather than genuinely removed. Nothing was written." -ForegroundColor Red
    pause
    exit 1
}

$manifestObject = [ordered]@{
    Version              = $manifestVersion
    HasSyncedFromBackend = $hasSyncedFromBackend
    Files                = $newFiles
}

$jsonCompact = $manifestObject | ConvertTo-Json -Depth 10 -Compress
$json = Format-Json -Json $jsonCompact

# --- Always back up the manifest before touching it (into Backup/, not loose) ---
if (Test-Path $manifestPath) {
    $backupRoot = Join-Path $root "Backup"
    if (-not (Test-Path $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory | Out-Null
    }
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $backupPath = Join-Path $backupRoot "CloudSaveManifest.$stamp.bak"
    Copy-Item -Path $manifestPath -Destination $backupPath -Force
    Write-Host "Manifest backup written: $backupPath"
}

# Write back as UTF-16LE with BOM, matching the original file format
[System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.Encoding]::Unicode)

Write-Host ""
Write-Host "Done. Manifest updated: $manifestPath"
Write-Host "Total entries: $($newFiles.Count)"
pause