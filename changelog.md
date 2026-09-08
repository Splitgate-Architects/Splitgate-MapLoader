# Changelog

## v3.0.0
- **Polyglot Scripting:** Combined PowerShell and Batch logic into a single `.bat` executable. This eliminates the need for separate launcher and script files, making distribution and execution significantly easier for end users.

## v2.0.0
- **Flat Community Maps:** Community maps are now loaded directly as flat `.bin` files from the root `MapCreator` and `MapCreatorPrefab` folders, no longer requiring individual subfolders.
- **Embedded Metadata:** Extracts map name and author directly from the `Info.json` packed inside the community `.bin` archive.
- **Optimized Backups:** The backup process now exclusively copies native map/prefab subfolders; flat community `.bin` files are intentionally skipped to save time and storage space.
- **Automated Sync & Logging:** Automatically removes deleted community `.bin` files from the manifest and logs all import/removal actions to a `manifest-log.csv` file.

## v1.1.0
- **OwnerId Fix:** New entries now derive their default `OwnerId` exclusively from your own native maps, preventing incorrect assignments from community maps.
- **Manifest Encoding:** Auto-detects and preserves the original `CloudSaveManifest.json` encoding (UTF-16LE with BOM or plain UTF-8).
- **Script Split:** Distributed the tool as two separate files (`.bat` and `.ps1`).
- **Separated Assets:** Starter maps were removed from the main package and made available separately as `CustomMaps.zip`.

## v1.0.0 - Initial Release
- **Automated Manifests:** Scans folders and generates `CloudSaveManifest.json` based on actual contents.
- **Non-Destructive Updates:** Preserves existing `FileName`, `OwnerId`, `AuthorDisplayName`, and `CreatedAt` values; only creates defaults for genuinely new folders.
- **Safe Failure Mode:** Aborts with a clear error if the existing JSON cannot be parsed.
- **Community Support:** Uses `custom-map.json` to override display names and prefixes imported maps with a `[P]` tag.
- **Interactive Backups:** Prompts for a Y/N backup before running, saving snapshots to a dated `Backup/` folder.
- **Staging Workflow:** Added dedicated `CustomMaps/` and `CustomPrefabs/` folders for staging new content before importing.
- **Clean JSON Output:** Custom formatting ensures consistent 2-space indentation.