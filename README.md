[![YouTube Video](https://raw.githubusercontent.com/CorellanStoma/Splitgate-MapLoader/refs/heads/master/assets/MapLoader.png)](https://www.youtube.com/watch?v=fHKV-zwphbo)

[Watch the Video Guide](https://www.youtube.com/watch?v=fHKV-zwphbo)

# Splitgate-MapLoader

A streamlined, automated utility designed to simplify loading custom maps and prefabs into Splitgate.

> [!CAUTION]
> The underlying code for this project was built by AI.

## Why is this script needed?
Adding custom maps to Splitgate manually is notoriously frustrating. Simply dropping a downloaded `.bin` map file into your game directory does not make it show up in-game; the game relies on a strict `CloudSaveManifest.json` file to recognize and list custom content in your menus. Modifying this JSON manually is error-prone and time-consuming.

This tool completely automates the process. Drop your `.bin` files straight into the game's own `MapCreator` folder, run the script, and it rebuilds a clean, correctly formatted `CloudSaveManifest.json` so the game immediately recognizes your new content.

## Features
* **No Staging Folders:** Just drop `.bin` files directly into the live `MapCreator` / `MapCreatorPrefab` folders - no separate import step, no intermediate copying.
* **Two-Way Sync:** Add a `.bin` file and it's added to the manifest. Delete a `.bin` file and run the script again - it's automatically removed from the manifest too. Your own native maps (the ones you build in the in-game editor) are never touched by this.
* **Automated Manifest Generation:** Scans your `MapCreator` / `MapCreatorPrefab` folders and dynamically rebuilds a clean, correctly formatted `CloudSaveManifest.json` - matching whatever encoding your manifest already uses.
* **Built-in Backups:** Prompts you to back up your own native map folders and manifest before making any changes, saving them to a timestamped `Backup/` directory. Downloaded community maps aren't included in the backup since they can always be re-downloaded.
* **One-Click Execution:** A single `.bat` file - no separate script files to keep track of, and it bypasses strict PowerShell execution policies automatically, meaning you just double-click and go.

## Where to Get Maps
Browse, search, and download community-made maps here:

**[Splitgate-CommunityMaps](https://splitgate-architects.github.io/Splitgate-CommunityMaps/)**

Every map on the site is a ready-to-use `.bin` file with the map name, author, and category already built in - just download and drop it in.

## Prerequisite
Before using this tool for the first time, **you must have created and saved at least one map of your own in the in-game Map Lab.** This is what makes your `OwnerId` show up in `CloudSaveManifest.json` in the first place - the script reads it from there and reuses it for every map you import. Without at least one native map already saved, there's nothing for it to read.

## How to Install & Use

**1. Get some maps**
* Head to [Splitgate-CommunityMaps](https://splitgate-architects.github.io/Splitgate-CommunityMaps/) and download the `.bin` file(s) for any maps you want to play.

**2. Install the loader**
* Download `MapLoader.bat` from this repository.
* Open File Explorer, paste the following into the address bar, and press Enter:
  ```
  %LOCALAPPDATA%\PortalWars2\Saved\Cloud\CloudSave
  ```
* Place `MapLoader.bat` directly into this `CloudSave` folder.

**3. Add your maps**
* Copy the `.bin` file(s) you downloaded directly into the `MapCreator` folder (for maps) or `MapCreatorPrefab` folder (for prefabs) inside `CloudSave`. No subfolder needed - just the `.bin` file itself.

**4. Run the loader**
* Double-click `MapLoader.bat`.
* When asked whether to back up your files, it's recommended to type `Y` - this backs up your own native maps and the current manifest into a timestamped `Backup\` folder.
* Once the script finishes, close the window.

**5. Play**
* Launch Splitgate and open the Lab / Customs menu - your new maps should already be there.

## Uninstalling Maps
Don't want a map anymore? Just:
1. Delete its `.bin` file from the `MapCreator` (or `MapCreatorPrefab`) folder.
2. Run `MapLoader.bat` again.
3. Close the window once it finishes.

The map's entry is automatically removed from `CloudSaveManifest.json` - no manual JSON editing required.