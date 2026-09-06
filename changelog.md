# Changelog

## v1.1.0

### Fixed
- **OwnerId handling:** The default `OwnerId` assigned to brand-new entries is
  now derived only from your own native maps (folders without a
  `custom-map.json`). Previously it was taken from whichever `OwnerId`
  appeared most often overall, so importing a community map before adding
  a new map of your own could cause the wrong `OwnerId` to be assigned.
- **Manifest encoding:** The importer now auto-detects whether
  `CloudSaveManifest.json` is UTF-16LE (with BOM) or plain UTF-8 (no BOM) -
  both occur depending on setup - and reads/writes using whichever encoding
  the file actually uses. Previously the script always assumed UTF-16,
  which made it fail completely on manifests using the other encoding.

### Changed
- `update_manifest.ps1` and `update_manifest.bat` are now distributed as two
  separate files instead of one bundle - **both are required** to run the tool.
- Starter maps are no longer bundled inside the main MapLoader package. They're
  now available separately as `CustomMaps.zip`.

---

## v1.0.0 - Initial Release

- **Automated manifest generation:** Scans `MapCreator` / `MapCreatorPrefab`
  folders and builds `CloudSaveManifest.json` from their actual contents -
  one `FileId` per subfolder, one `Saves` entry per `.bin` file inside it.
- **Non-destructive updates:** Existing entries keep their `FileName`,
  `OwnerId`, `AuthorDisplayName`, and `CreatedAt` values; only genuinely new
  folders get fresh defaults.
- **Safe failure mode:** Aborts with a clear error instead of silently
  overwriting the manifest if the existing file can't be parsed.
- **Community map support:** An optional `custom-map.json` (`name` +
  `author`) per folder overrides the display name/author and prefixes the
  name with a `[P]` tag, so imported maps are clearly distinguishable from
  your own.
- **Backup on demand:** A Y/N prompt at startup saves a dated snapshot
  (`Backup/<yyyy-MM-dd>-Backup/`) of the live folders and manifest before
  anything is touched.
- **Staging workflow:** Dedicated `CustomMaps/` and `CustomPrefabs/` folders
  let you drop in new content before it's moved into the live save folders -
  so the backup step always captures a true "before" state.
- **Guided flow:** First run just creates the staging folders with
  instructions; every run after that walks through backup → confirm staged
  content is ready → import → manifest rebuild.
- **Clean JSON output:** Custom formatting produces consistent 2-space
  indentation with a single space after colons, regardless of whether the
  input manifest was minified or already pretty-printed.
