# Editing Imported Maps

A short guide to what happens when you open a downloaded community map in
Splitgate's in-game editor - and how the MapLoader handles it.

## What Happens When You Edit and Save

When you open a `.bin` you downloaded (say, `codephoenix_shooting-range.bin`)
in the editor and save your changes, Splitgate does **not** overwrite the
original file or create a separate map. Instead, it adds your edit as a new
save history entry, stored in a new subfolder with the exact same name:

```
MapCreator/
├── codephoenix_shooting-range.bin        <- the original, unchanged
└── codephoenix_shooting-range/            <- new subfolder, created by the game
    └── a1b2c3d4-....bin                  <- your edited version
```

In `CloudSaveManifest.json`, this shows up as **one entry** with **two**
`Saves`:

```json
{
  "FileId": "codephoenix_shooting-range",
  "FileName": "[P] Shooting Range",
  "AuthorDisplayName": "Code Phoenix",
  "Saves": [
    { "SaveId": "a1b2c3d4-....", "RelativePath": "MapCreator/codephoenix_shooting-range/a1b2c3d4-....bin" },
    { "SaveId": "custom-map",    "RelativePath": "MapCreator/codephoenix_shooting-range.bin" }
  ]
}
```

MapLoader (v3.0.0+) recognizes this correctly: it merges both saves into the
same entry instead of creating two conflicting ones.

## Removing an Edited Map

Because there are now two things on disk sharing that name, what you delete
determines what happens:

| You delete... | Result |
|---|---|
| Only the `.bin` file | Your edited version stays; the original import is gone |
| Only the subfolder | The original import stays; your edit is gone |
| **Both** the `.bin` file and the subfolder | The entire entry is removed from the manifest on the next run |

Run `MapLoader.bat` after deleting to apply the change.

## A Note on Attribution

The map's display name and author are stored once, at the entry level - not
per save. So if you delete just the original `.bin` and keep your edited
version, it'll still show the original author's name and the `[P]` tag,
since MapLoader has no way to know you want to reassign ownership. If you'd
rather it show up as your own, edit `FileName` and `AuthorDisplayName` for
that entry in `CloudSaveManifest.json` by hand after running the script.