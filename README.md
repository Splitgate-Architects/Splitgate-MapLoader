[![YouTube Video](https://raw.githubusercontent.com/CorellanStoma/Splitgate-MapLoader/refs/heads/master/assets/Map%20Loader.png)](https://youtu.be/Gx70ZBeIltw)

# Splitgate-MapLoader

A streamlined, automated utility designed to simplify loading custom maps and prefabs into Splitgate. 

> [!CAUTION]
> The underlying code for this project was built with the assistance of AI.

## Why is this script needed?
Adding custom maps to Splitgate manually is notoriously frustrating. Simply dropping a downloaded `.bin` map file into your game directory does not work; the game relies on a strict `CloudSaveManifest.json` file to recognize and list custom content in your menus. Modifying this JSON manually is error-prone and time-consuming. 

This tool completely automates the process. It safely moves your downloaded maps into the active game directories and perfectly reconstructs the manifest file so the game immediately recognizes your new content. 

## Features
* **Safe Staging Environment:** Introduces dedicated `CustomMaps/` and `CustomPrefabs/` folders so you can organize new downloads without directly touching live game files.
* **Automated Manifest Generation:** Scans your active maps and dynamically rebuilds a clean, correctly formatted `CloudSaveManifest.json`.
* **Built-in Backups:** Prompts you to back up your existing `MapCreator` folders and manifest before making any changes, saving them to a timestamped `Backup/` directory.
* **One-Click Execution:** The included batch file bypasses strict PowerShell execution policies automatically, meaning you just double-click and go.

## The Standardized Map Format
To make sharing and organizing maps as clean as possible, this tool encourages a standardized structure for distributing custom maps. Ideally, each published map folder should contain:

* `custom-map.bin` - The actual map data.
* `custom-map.json` - A metadata file containing the map name and author. *(If Splitgate has a future in modding, this could be expanded over time.)*
* `custom-map.jpg` or `.png` *(Optional but recommended)* - A preview image so users know what they are downloading.

**Why use `custom-map.json`?**
When the script rebuilds your manifest, it reads this metadata to correctly name the map and credit the author. Crucially, the script automatically applies a `[P]` prefix to any map imported using a JSON file. 

If you are a map creator importing 50+ custom maps, this feature is a lifesaver. The prefix ensures all downloaded public maps are visually separated in your Lab selection menu, preventing them from cluttering up your own original creations.

## How to Install & Use

**1. Installation**
* Open File Explorer on your PC.
* In the address bar at the top, paste the following path and press Enter:
  `%LOCALAPPDATA%\PortalWars2\Saved\Cloud\CloudSave`
* Copy the `update_manifest.bat` and `update_manifest.ps1` files directly into this `CloudSave` folder.

**2. Initial Setup**
* Double-click `update_manifest.bat`. 
* On the first run, the script will automatically create empty `CustomMaps` and `CustomPrefabs` staging folders and pause to let you add files. 

**3. Stage Your Content**
* Drop your downloaded custom map folders into the new `CustomMaps/` directory. 
* Ensure each folder contains the map's `.bin` file (and the `custom-map.json` if provided).

**4. Run the Importer**
* Double-click `update_manifest.bat` again. 

**5. Backup Your Files**
* The script will ask if you want to back up your current state. It is highly recommended to type `Y`. 
* This will safely copy your current `MapCreator`, `MapCreatorPrefab`, and `CloudSaveManifest.json` into a timestamped folder (e.g., `Backup\2026-09-04-Backup`).

**6. Confirm and Play**
* Type `Y` to confirm your files are staged. 
* The tool will automatically merge the maps into the live game directories and generate the new manifest. 
* Launch Splitgate and enjoy your custom maps!
