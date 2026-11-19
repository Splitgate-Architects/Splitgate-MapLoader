#!/usr/bin/env bash
# Splitgate MapLoader for linux (and mac)
# needs python3, nothing else
# usage: ./MapLoader_v3.1.0_linux.sh [--lang en|de|es|fr] [path to CloudSave folder]

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is needed but not found."
    exit 1
fi

# folder this script sits in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# python code lives in a variable so this stays one file
read -r -d '' PYCODE <<'PY'
import sys, os, io, re, json, glob, shutil, zipfile
from datetime import datetime, timezone
from collections import Counter

COMMUNITY_TAG = "[P]"
CONTENT_TYPES = ["MapCreator", "MapCreatorPrefab", "CustomModes"]
MARKERS = [
    ("world.cf1047", "MapCreator"),
    ("prefab.cf1047_prefab", "MapCreatorPrefab"),
    ("payload.json", "CustomModes"),
]
PACK_EXTS = (".sgmaps", ".sgprefabs", ".sgmixed")

script_dir = sys.argv[1]
LANGS = {
    "en": {
        "AutoPathFound": "Automatically found Splitgate CloudSave folder:",
        "PathNotFound": "Splitgate CloudSave folder not found in AppData.",
        "UsingCurrentDir": "Using current directory as base:",
        "SkipEmptyNative": "  Skipping {0} (folder exists but has no .bin files inside - likely an unsaved/empty draft)",
        "FolderCreated": "Automatically created missing folder:",
        "BackupPrompt": "Do you want to back up your current MapCreator / MapCreatorPrefab folders (and the manifest) first? (Y/N)",
        "BackupExists": "A backup for today already exists, overwriting it:",
        "BackupNative": "Backing up native maps only ...",
        "SkipBackupFolder": "Skipping backup of {0} (no native map folders)",
        "BackupManifest": "Backed up CloudSaveManifest.json",
        "BackupDone": "Backup done:",
        "BackupSkipped": "Skipping backup.",
        "ReadingManifest": "Reading existing manifest...",
        "ParseError": "[ABORTED] Could not parse the existing CloudSaveManifest.json as JSON.",
        "MissingFields": "[ABORTED] The existing manifest parsed, but is missing expected fields (Version/Files).",
        "ParsedOk": "  Parsed OK: Version={0}, {1} existing entries.",
        "NoManifest": "No existing manifest found. Creating a new one automatically.",
        "NoOwnerIdNote": "Note: No existing OwnerId found anywhere. New entries will be created without an OwnerId field.",
        "ActionUpdated": "UPDATED",
        "ActionNew": "NEW",
        "ActionRemoved": "REMOVED (community): {0} - .bin no longer found, dropping it from the manifest",
        "DoneSuccess": "Done. Manifest updated:",
        "TotalEntries": "Total entries: {0} ({1} native, {2} community)",
        "FirstRunBackup": "First run detected - it's strongly recommended to back up before continuing.",
        "PackScanning": "Scanning for pack files (.sgmaps / .sgprefabs / .sgmixed) and loose/misplaced .bin files...",
        "PackFound": "Found pack: {0}",
        "PackItemImported": "    Imported: {0} -> {1}",
        "PackItemMoved": "    Moved: {0} ({1} -> {2})",
        "PackItemSkipped": "    Skipped: {0} (already exists in {1})",
        "PackItemUnknown": "    Skipped: {0} (couldn't determine type - no World.cf1047 / Prefab.cf1047_prefab / payload.json found)",
        "LooseBinFound": "Found loose .bin in CloudSave root: {0}",
        "MisplacedBinFound": "Found misplaced .bin in {1}: {0}",
        "NoPacksFound": "No pack files or loose/misplaced .bin files found.",
        "PackCleanupPrompt": "Delete the {0} processed pack file(s) now that they've been unpacked? (Y/N - 'N' moves them to Backup/Packs/ instead)",
        "PackDeleted": "Deleted: {0}",
        "PackMoved": "Moved to Backup/Packs/: {0}",
    },
    "de": {
        "AutoPathFound": "Splitgate CloudSave-Ordner automatisch gefunden:",
        "PathNotFound": "Splitgate CloudSave-Ordner im AppData-Verzeichnis nicht gefunden.",
        "UsingCurrentDir": "Aktuelles Verzeichnis wird als Basis verwendet:",
        "SkipEmptyNative": "  Ueberspringe {0} (Ordner existiert, enthaelt aber keine .bin-Dateien - vermutlich ein leerer Entwurf)",
        "FolderCreated": "Fehlender Ordner automatisch erstellt:",
        "BackupPrompt": "Moechtest du deine aktuellen MapCreator / MapCreatorPrefab Ordner (und das Manifest) zuerst sichern? (J/N)",
        "BackupExists": "Ein Backup fuer heute existiert bereits und wird ueberschrieben:",
        "BackupNative": "Nur native Maps werden gesichert...",
        "SkipBackupFolder": "Backup von {0} uebersprungen (keine nativen Map-Ordner)",
        "BackupManifest": "CloudSaveManifest.json gesichert.",
        "BackupDone": "Backup abgeschlossen:",
        "BackupSkipped": "Backup uebersprungen.",
        "ReadingManifest": "Lese bestehendes Manifest...",
        "ParseError": "[ABGEBROCHEN] Die bestehende CloudSaveManifest.json konnte nicht als JSON geparst werden.",
        "MissingFields": "[ABGEBROCHEN] Das Manifest wurde geparst, aber erwartete Felder (Version/Files) fehlen.",
        "ParsedOk": "  Erfolgreich geparst: Version={0}, {1} bestehende Eintraege.",
        "NoManifest": "Kein bestehendes Manifest gefunden. Ein neues wird automatisch erstellt.",
        "NoOwnerIdNote": "Hinweis: Keine OwnerId gefunden. Neue Eintraege werden ohne OwnerId-Feld erstellt.",
        "ActionUpdated": "AKTUALISIERT",
        "ActionNew": "NEU",
        "ActionRemoved": "ENTFERNT (Community): {0} - .bin nicht mehr gefunden, wird aus dem Manifest geloescht",
        "DoneSuccess": "Fertig. Manifest aktualisiert:",
        "TotalEntries": "Gesamteintraege: {0} ({1} nativ, {2} Community)",
        "FirstRunBackup": "Erster Start erkannt - es wird dringend empfohlen, ein Backup zu erstellen, bevor du fortfaehrst.",
        "PackScanning": "Suche nach Pack-Dateien (.sgmaps / .sgprefabs / .sgmixed) und losen/falsch platzierten .bin-Dateien...",
        "PackFound": "Pack gefunden: {0}",
        "PackItemImported": "    Importiert: {0} -> {1}",
        "PackItemMoved": "    Verschoben: {0} ({1} -> {2})",
        "PackItemSkipped": "    Uebersprungen: {0} (existiert bereits in {1})",
        "PackItemUnknown": "    Uebersprungen: {0} (Typ konnte nicht ermittelt werden - keine World.cf1047 / Prefab.cf1047_prefab / payload.json gefunden)",
        "LooseBinFound": "Lose .bin im CloudSave-Root gefunden: {0}",
        "MisplacedBinFound": "Falsch platzierte .bin in {1} gefunden: {0}",
        "NoPacksFound": "Keine Pack-Dateien oder lose/falsch platzierte .bin-Dateien gefunden.",
        "PackCleanupPrompt": "Die {0} verarbeitete(n) Pack-Datei(en) loeschen, da sie nun entpackt sind? (J/N - bei 'N' werden sie stattdessen nach Backup/Packs/ verschoben)",
        "PackDeleted": "Geloescht: {0}",
        "PackMoved": "Verschoben nach Backup/Packs/: {0}",
    },
    "es": {
        "AutoPathFound": "Carpeta CloudSave de Splitgate encontrada automaticamente:",
        "PathNotFound": "Carpeta CloudSave de Splitgate no encontrada en AppData.",
        "UsingCurrentDir": "Usando el directorio actual como base:",
        "SkipEmptyNative": "  Omitiendo {0} (la carpeta existe pero no tiene archivos .bin dentro - probablemente un borrador vacio)",
        "FolderCreated": "Carpeta faltante creada automaticamente:",
        "BackupPrompt": "Deseas hacer una copia de seguridad de tus carpetas MapCreator / MapCreatorPrefab (y el manifiesto) primero? (S/N)",
        "BackupExists": "Ya existe una copia de seguridad para hoy, sobrescribiendo:",
        "BackupNative": "Haciendo copia de seguridad solo de los mapas nativos...",
        "SkipBackupFolder": "Omitiendo copia de seguridad de {0} (no hay carpetas de mapas nativos)",
        "BackupManifest": "CloudSaveManifest.json respaldado.",
        "BackupDone": "Copia de seguridad completada:",
        "BackupSkipped": "Copia de seguridad omitida.",
        "ReadingManifest": "Leyendo el manifiesto existente...",
        "ParseError": "[CANCELADO] No se pudo analizar el CloudSaveManifest.json existente como JSON.",
        "MissingFields": "[CANCELADO] El manifiesto fue analizado, pero faltan campos esperados (Version/Files).",
        "ParsedOk": "  Analizado correctamente: Version={0}, {1} entradas existentes.",
        "NoManifest": "No se encontro ningun manifiesto existente. Creando uno nuevo automaticamente.",
        "NoOwnerIdNote": "Nota: No se encontro ningun OwnerId. Las nuevas entradas se crearan sin el campo OwnerId.",
        "ActionUpdated": "ACTUALIZADO",
        "ActionNew": "NUEVO",
        "ActionRemoved": "ELIMINADO (comunidad): {0} - .bin ya no se encuentra, eliminandolo del manifiesto",
        "DoneSuccess": "Hecho. Manifiesto actualizado:",
        "TotalEntries": "Entradas totales: {0} ({1} nativos, {2} comunidad)",
        "FirstRunBackup": "Primera ejecucion detectada: se recomienda encarecidamente hacer una copia de seguridad antes de continuar.",
        "PackScanning": "Buscando archivos de paquetes (.sgmaps / .sgprefabs / .sgmixed) y archivos .bin sueltos/mal ubicados...",
        "PackFound": "Paquete encontrado: {0}",
        "PackItemImported": "    Importado: {0} -> {1}",
        "PackItemMoved": "    Movido: {0} ({1} -> {2})",
        "PackItemSkipped": "    Omitido: {0} (ya existe en {1})",
        "PackItemUnknown": "    Omitido: {0} (no se pudo determinar el tipo - no se encontro World.cf1047 / Prefab.cf1047_prefab / payload.json)",
        "LooseBinFound": "Archivo .bin suelto encontrado en la raiz de CloudSave: {0}",
        "MisplacedBinFound": "Archivo .bin mal ubicado encontrado en {1}: {0}",
        "NoPacksFound": "No se encontraron archivos de paquetes ni archivos .bin sueltos/mal ubicados.",
        "PackCleanupPrompt": "Eliminar los {0} archivo(s) de paquete procesado(s) ahora que se han descomprimido? (S/N - 'N' los mueve a Backup/Packs/ en su lugar)",
        "PackDeleted": "Eliminado: {0}",
        "PackMoved": "Movido a Backup/Packs/: {0}",
    },
    "fr": {
        "AutoPathFound": "Dossier CloudSave de Splitgate trouve automatiquement :",
        "PathNotFound": "Dossier CloudSave de Splitgate introuvable dans AppData.",
        "UsingCurrentDir": "Utilisation du repertoire actuel comme base :",
        "SkipEmptyNative": "  Ignore {0} (le dossier existe mais ne contient aucun fichier .bin - probablement un brouillon vide)",
        "FolderCreated": "Dossier manquant cree automatiquement :",
        "BackupPrompt": "Voulez-vous sauvegarder vos dossiers MapCreator / MapCreatorPrefab (et le manifeste) d'abord ? (O/N)",
        "BackupExists": "Une sauvegarde pour aujourd'hui existe deja, ecrasement en cours :",
        "BackupNative": "Sauvegarde des cartes natives uniquement...",
        "SkipBackupFolder": "Saut de la sauvegarde de {0} (aucun dossier de carte native)",
        "BackupManifest": "CloudSaveManifest.json sauvegarde.",
        "BackupDone": "Sauvegarde terminee :",
        "BackupSkipped": "Sauvegarde ignoree.",
        "ReadingManifest": "Lecture du manifeste existant...",
        "ParseError": "[ANNULE] Impossible d'analyser le fichier CloudSaveManifest.json existant en tant que JSON.",
        "MissingFields": "[ANNULE] Le manifeste a ete analyse, mais les champs attendus (Version/Files) sont manquants.",
        "ParsedOk": "  Analyse avec succes : Version={0}, {1} entrees existantes.",
        "NoManifest": "Aucun manifeste existant trouve. Creation automatique d'un nouveau.",
        "NoOwnerIdNote": "Remarque : Aucun OwnerId trouve. Les nouvelles entrees seront creees sans champ OwnerId.",
        "ActionUpdated": "MIS A JOUR",
        "ActionNew": "NOUVEAU",
        "ActionRemoved": "SUPPRIME (communaute) : {0} - .bin introuvable, suppression du manifeste",
        "DoneSuccess": "Termine. Manifeste mis a jour :",
        "TotalEntries": "Total des entrees : {0} ({1} natives, {2} communaute)",
        "FirstRunBackup": "Premier lancement detecte - il est fortement recommande de faire une sauvegarde avant de continuer.",
        "PackScanning": "Recherche de fichiers de packs (.sgmaps / .sgprefabs / .sgmixed) et de fichiers .bin en vrac/mal places...",
        "PackFound": "Pack trouve : {0}",
        "PackItemImported": "    Importe : {0} -> {1}",
        "PackItemMoved": "    Deplace : {0} ({1} -> {2})",
        "PackItemSkipped": "    Ignore : {0} (existe deja dans {1})",
        "PackItemUnknown": "    Ignore : {0} (impossible de determiner le type - aucun World.cf1047 / Prefab.cf1047_prefab / payload.json trouve)",
        "LooseBinFound": "Fichier .bin en vrac trouve dans la racine de CloudSave : {0}",
        "MisplacedBinFound": "Fichier .bin mal place trouve dans {1} : {0}",
        "NoPacksFound": "Aucun fichier de pack ou fichier .bin en vrac/mal place trouve.",
        "PackCleanupPrompt": "Supprimer le(s) {0} fichier(s) de pack traite(s) maintenant qu'ils ont ete decompresses ? (O/N - 'N' les deplace vers Backup/Packs/ a la place)",
        "PackDeleted": "Supprime : {0}",
        "PackMoved": "Deplace vers Backup/Packs/ : {0}",
    },
}
YES_LETTERS = {"en": "", "de": "Jj", "es": "Ss", "fr": "Oo"}

# --- language: --lang xx, MAPLOADER_LANG, or system LANG ---
args = sys.argv[2:]
lang = os.environ.get("MAPLOADER_LANG") or os.environ.get("LANG", "")[:2]
arg_path = None
i = 0
while i < len(args):
    if args[i] in ("--lang", "-l") and i + 1 < len(args):
        lang = args[i + 1]
        i += 2
        continue
    arg_path = args[i]
    i += 1
lang = lang.lower()[:2]
if lang not in LANGS:
    lang = "en"
M = LANGS[lang]
YES = re.compile(r"^[Yy" + YES_LETTERS[lang] + "]")
home = os.path.expanduser("~")

# colors, only if we are in a terminal
def color(code, text):
    return "\033[%sm%s\033[0m" % (code, text) if sys.stdout.isatty() else text
def cyan(t): return color("36", t)
def green(t): return color("32", t)
def yellow(t): return color("33", t)
def red(t): return color("31", t)

def ask(prompt):
    try:
        return input(prompt + " ")
    except EOFError:
        return ""

def iso_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (datetime.now(timezone.utc).microsecond // 1000)

def iso_from_file(path):
    d = datetime.fromtimestamp(os.path.getmtime(path), timezone.utc)
    return d.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (d.microsecond // 1000)

# --- find the game folder ---
def find_game_path():
    rel = "pfx/drive_c/users/steamuser/AppData/Local/PortalWars2/Saved/Cloud/CloudSave"
    steam_dirs = [
        home + "/.steam/steam",
        home + "/.steam/root",
        home + "/.local/share/Steam",
        home + "/.var/app/com.valvesoftware.Steam/.local/share/Steam",
        home + "/snap/steam/common/.local/share/Steam",
    ]
    for s in steam_dirs:
        for hit in glob.glob(s + "/steamapps/compatdata/*/" + rel):
            return hit
    # native/other layouts
    for p in [home + "/.local/share/PortalWars2/Saved/Cloud/CloudSave",
              home + "/Library/Application Support/PortalWars2/Saved/Cloud/CloudSave"]:
        if os.path.isdir(p):
            return p
    return None

if arg_path:
    root = os.path.abspath(os.path.expanduser(arg_path))
    print(cyan("Using given path: " + root))
elif os.path.exists(os.path.join(script_dir, "CloudSaveManifest.json")):
    root = script_dir
    print(cyan(M["UsingCurrentDir"] + " " + root))
elif os.path.exists(os.path.join(os.path.dirname(script_dir), "CloudSaveManifest.json")):
    root = os.path.dirname(script_dir)
    print(cyan(M["UsingCurrentDir"] + " " + root))
else:
    found = find_game_path()
    if found:
        root = found
        print(green(M["AutoPathFound"]))
        print(cyan("  " + root))
    else:
        root = script_dir
        print(yellow(M["PathNotFound"]))
        print(yellow(M["UsingCurrentDir"] + " " + root))
        print(yellow("Tip: pass the CloudSave path as an argument."))
print("")

manifest_path = os.path.join(root, "CloudSaveManifest.json")

for name in CONTENT_TYPES:
    d = os.path.join(root, name)
    if not os.path.isdir(d):
        os.makedirs(d)
        print(cyan(M["FolderCreated"] + " " + name))
print("")

# --- helpers ---
def read_manifest_text(path):
    # keep the same encoding the game used
    data = open(path, "rb").read()
    if data[:2] == b"\xff\xfe":
        return data.decode("utf-16"), "utf-16"
    if data[:3] == b"\xef\xbb\xbf":
        return data[3:].decode("utf-8"), "utf-8-sig"
    return data.decode("utf-8"), "utf-8"

def write_manifest_text(path, text, enc):
    if enc == "utf-16":
        raw = b"\xff\xfe" + text.encode("utf-16-le")
    elif enc == "utf-8-sig":
        raw = b"\xef\xbb\xbf" + text.encode("utf-8")
    else:
        raw = text.encode("utf-8")
    open(path, "wb").write(raw)

def type_from_zip(z):
    names = [os.path.basename(n.replace("\\", "/")).lower() for n in z.namelist()]
    for marker, t in MARKERS:
        if marker in names:
            return t
    return None

def type_from_bytes(b):
    try:
        with zipfile.ZipFile(io.BytesIO(b)) as z:
            return type_from_zip(z)
    except Exception:
        return None

def type_from_file(p):
    try:
        with zipfile.ZipFile(p) as z:
            return type_from_zip(z)
    except Exception:
        return None

def info_from_bin(p):
    try:
        with zipfile.ZipFile(p) as z:
            for n in z.namelist():
                if os.path.basename(n.replace("\\", "/")).lower() == "info.json":
                    return json.loads(z.read(n).decode("utf-8-sig"))
    except Exception as e:
        print(yellow("  Could not read info.json from %s: %s" % (os.path.basename(p), e)))
    return None

def save_routed(root, ctype, item, data):
    d = os.path.join(root, ctype)
    os.makedirs(d, exist_ok=True)
    dest = os.path.join(d, item + ".bin")
    if os.path.exists(dest):
        print(M["PackItemSkipped"].format(item, ctype))
        return
    open(dest, "wb").write(data)
    print(M["PackItemImported"].format(item, ctype))

def expand_pack(pack_path, root):
    ext = os.path.splitext(pack_path)[1].lower()
    fallback = {".sgmaps": "MapCreator", ".sgprefabs": "MapCreatorPrefab"}.get(ext)
    with zipfile.ZipFile(pack_path) as z:
        entries = [i for i in z.infolist() if not i.filename.endswith("/")]
        norm = lambda i: i.filename.replace("\\", "/")
        has_nested = any(norm(i).lower().endswith(".bin") for i in entries)
        has_folders = any("/" in norm(i) for i in entries)
        if not has_nested and has_folders:
            # one folder per item
            groups = {}
            for i in entries:
                if "/" in norm(i):
                    groups.setdefault(norm(i).split("/")[0], []).append(i)
            for item, items in groups.items():
                buf = io.BytesIO()
                with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as nz:
                    nz.comment = b"Packed by CreativeCore1047"
                    for i in items:
                        nz.writestr(os.path.basename(norm(i)), z.read(i))
                data = buf.getvalue()
                ctype = type_from_bytes(data) or fallback
                if not ctype:
                    print(M["PackItemUnknown"].format(item))
                    continue
                save_routed(root, ctype, item, data)
        else:
            # every file in the pack is its own .bin
            for i in entries:
                item = os.path.splitext(os.path.basename(norm(i)))[0]
                data = z.read(i)
                if len(data) < 4 or data[:2] != b"PK":
                    continue
                ctype = type_from_bytes(data) or fallback
                if not ctype:
                    print(M["PackItemUnknown"].format(item))
                    continue
                save_routed(root, ctype, item, data)

def is_community(entry):
    return any(s.get("SaveId") == "custom-map" for s in (entry.get("Saves") or []))

def list_files(d, ext=None):
    out = []
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        if os.path.isfile(p) and (ext is None or n.lower().endswith(ext)):
            out.append(n)
    return out

def list_dirs(d):
    return [n for n in sorted(os.listdir(d)) if os.path.isdir(os.path.join(d, n))]

# --- part 1: backup ---
backup_root = os.path.join(root, "Backup")
first_run = not os.path.exists(backup_root)
if first_run:
    print(cyan(M["FirstRunBackup"]))
    answer = ask(M["BackupPrompt"])
else:
    answer = "N"

if YES.match(answer):
    dest = os.path.join(backup_root, datetime.now().strftime("%Y-%m-%d") + "-Backup")
    os.makedirs(backup_root, exist_ok=True)
    if os.path.exists(dest):
        print(M["BackupExists"] + " " + dest)
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in CONTENT_TYPES:
        src = os.path.join(root, name)
        if not os.path.isdir(src):
            continue
        folders = list_dirs(src)
        if not folders:
            print(M["SkipBackupFolder"].format(name))
            continue
        print(M["BackupNative"])
        for f in folders:
            shutil.copytree(os.path.join(src, f), os.path.join(dest, name, f))
    if os.path.exists(manifest_path):
        shutil.copy2(manifest_path, os.path.join(dest, "CloudSaveManifest.json"))
        print(M["BackupManifest"])
    print(M["BackupDone"] + " " + dest)
elif first_run:
    print(M["BackupSkipped"])
os.makedirs(backup_root, exist_ok=True)
print("")

# --- part 2: read the manifest ---
existing_by_id = {}
manifest_version = 1
synced = True
enc = "utf-8"

if os.path.exists(manifest_path):
    print(M["ReadingManifest"])
    try:
        text, enc = read_manifest_text(manifest_path)
        existing = json.loads(text)
    except Exception as e:
        print("")
        print(red(M["ParseError"]))
        print(red("Error: %s" % e))
        sys.exit(1)
    if existing:
        if existing.get("Version") is not None:
            manifest_version = existing["Version"]
        if existing.get("HasSyncedFromBackend") is not None:
            synced = existing["HasSyncedFromBackend"]
        for f in existing.get("Files") or []:
            existing_by_id[f["FileId"]] = f
    print(M["ParsedOk"].format(manifest_version, len(existing_by_id)))
else:
    print(M["NoManifest"])

default_owner = None
if existing_by_id:
    native = [e["OwnerId"] for e in existing_by_id.values() if not is_community(e) and e.get("OwnerId")]
    anyone = [e["OwnerId"] for e in existing_by_id.values() if e.get("OwnerId")]
    pool = native or anyone
    if pool:
        default_owner = Counter(pool).most_common(1)[0][0]
if not default_owner:
    print(yellow(M["NoOwnerIdNote"]))
print("")

# --- part 2.5: packs and loose files ---
print(M["PackScanning"])
found_any = False
processed_packs = []

scan_dirs = [root] + [os.path.join(root, t) for t in CONTENT_TYPES]
for loc in scan_dirs:
    if not os.path.isdir(loc):
        continue
    for n in list_files(loc):
        if n.lower().endswith(PACK_EXTS):
            found_any = True
            print(M["PackFound"].format(n))
            p = os.path.join(loc, n)
            try:
                expand_pack(p, root)
                processed_packs.append(p)
            except Exception as e:
                print(red("  Could not read pack %s: %s" % (n, e)))

# loose bins in the root
for n in list_files(root, ".bin"):
    found_any = True
    print(M["LooseBinFound"].format(n))
    p = os.path.join(root, n)
    ctype = type_from_file(p)
    if not ctype:
        print(M["PackItemUnknown"].format(n[:-4]))
        continue
    dest = os.path.join(root, ctype, n)
    if os.path.exists(dest):
        print(M["PackItemSkipped"].format(n[:-4], ctype))
    else:
        shutil.move(p, dest)
        print(M["PackItemImported"].format(n[:-4], ctype))

# bins sitting in the wrong folder
for cur in CONTENT_TYPES:
    d = os.path.join(root, cur)
    if not os.path.isdir(d):
        continue
    for n in list_files(d, ".bin"):
        p = os.path.join(d, n)
        detected = type_from_file(p)
        if detected and detected != cur:
            found_any = True
            print(M["MisplacedBinFound"].format(n, cur))
            dest = os.path.join(root, detected, n)
            if os.path.exists(dest):
                print(M["PackItemSkipped"].format(n[:-4], detected))
            else:
                shutil.move(p, dest)
                print(M["PackItemMoved"].format(n[:-4], cur, detected))

if not found_any:
    print(M["NoPacksFound"])
print("")

# --- part 3: build the manifest ---
new_files = []
log_lines = []
stamp = lambda: datetime.now().strftime("%Y-%m-%d %H:%M:%S")

for ctype in CONTENT_TYPES:
    cdir = os.path.join(root, ctype)
    if not os.path.isdir(cdir):
        continue
    native_folders = list_dirs(cdir)
    flat_bins = {n[:-4]: n for n in list_files(cdir, ".bin")}
    all_ids = list(dict.fromkeys(native_folders + list(flat_bins.keys())))

    for fid in all_ids:
        old = existing_by_id.get(fid)
        saves = []
        has_comm = False
        info = None

        if fid in native_folders:
            fpath = os.path.join(cdir, fid)
            for bn in list_files(fpath, ".bin"):
                sid = bn[:-4]
                created = None
                if old:
                    for s in old.get("Saves") or []:
                        if s.get("SaveId") == sid:
                            created = s.get("CreatedAt")
                if not created:
                    created = iso_from_file(os.path.join(fpath, bn))
                saves.append({"SaveId": sid, "RelativePath": "%s/%s/%s" % (ctype, fid, bn),
                              "SaveType": "Manual", "CreatedAt": created})

        if fid in flat_bins:
            has_comm = True
            bp = os.path.join(cdir, flat_bins[fid])
            info = info_from_bin(bp)
            created = None
            if old:
                for s in old.get("Saves") or []:
                    if s.get("SaveId") == "custom-map":
                        created = s.get("CreatedAt")
                        break
            if not created:
                created = iso_from_file(bp)
            saves.append({"SaveId": "custom-map", "RelativePath": "%s/%s" % (ctype, flat_bins[fid]),
                          "SaveType": "Manual", "CreatedAt": created})

        if not saves:
            print(M["SkipEmptyNative"].format(fid))
            continue

        if not has_comm and old:
            has_comm = is_community(old)

        if old:
            fname = old.get("FileName")
            owner = old.get("OwnerId")
            author = old.get("AuthorDisplayName")
            created_top = old.get("CreatedAt")
            action = M["ActionUpdated"]
        else:
            fname = ("%s %s" % (COMMUNITY_TAG, fid)) if has_comm else fid
            owner = default_owner
            author = ""
            created_top = iso_now()
            action = M["ActionNew"]

        if not owner and default_owner:
            owner = default_owner

        if info and info.get("name"):
            fname = "%s %s" % (COMMUNITY_TAG, info["name"])
            if info.get("author"):
                author = info["author"]

        kind = "community" if has_comm else "native"
        print("  %s (%s): %s -> '%s' (%d save(s))" % (action, kind, fid, fname, len(saves)))
        if has_comm:
            log_lines.append("[%s] [%s] Map: %s (%s)" % (stamp(), action, fname, fid))

        entry = {"FileId": fid, "FileName": fname, "ContentType": ctype}
        if owner:
            entry["OwnerId"] = owner
        entry["AuthorDisplayName"] = author
        entry["CreatedAt"] = created_top
        entry["Saves"] = saves
        new_files.append(entry)

new_ids = {f["FileId"] for f in new_files}
for old in existing_by_id.values():
    if is_community(old) and old["FileId"] not in new_ids:
        print(M["ActionRemoved"].format(old["FileId"]))
        log_lines.append("[%s] [REMOVED] Map: %s (%s)" % (stamp(), old.get("FileName"), old["FileId"]))
print("")

# --- part 4: write it all out ---
manifest = {"Version": manifest_version, "HasSyncedFromBackend": synced, "Files": new_files}
# windows style line endings, same as the original script
text = json.dumps(manifest, indent=2, ensure_ascii=False).replace("\n", "\r\n")

if log_lines:
    with open(os.path.join(root, "maploader-log.txt"), "a", encoding="utf-8") as lf:
        lf.write("\n".join(log_lines) + "\n")

write_manifest_text(manifest_path, text, enc)

native_count = sum(1 for f in new_files if not is_community(f))
print("")
print(green(M["DoneSuccess"] + " " + manifest_path))
print(M["TotalEntries"].format(len(new_files), native_count, len(new_files) - native_count))

if processed_packs:
    print("")
    ans = ask(M["PackCleanupPrompt"].format(len(processed_packs)))
    for p in processed_packs:
        n = os.path.basename(p)
        if YES.match(ans):
            os.remove(p)
            print(M["PackDeleted"].format(n))
        else:
            pd = os.path.join(backup_root, "Packs")
            os.makedirs(pd, exist_ok=True)
            shutil.move(p, os.path.join(pd, n))
            print(M["PackMoved"].format(n))
PY

python3 -c "$PYCODE" "$SCRIPT_DIR" "$@"
status=$?

# keep the window open if double clicked
if [ -t 0 ] && [ -z "$MAPLOADER_NO_PAUSE" ]; then
    read -r -p "Press Enter to close ..." _
fi
exit $status
