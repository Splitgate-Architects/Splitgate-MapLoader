#!/usr/bin/env bash
# Splitgate MapLoader for linux (and mac)
# needs python3, nothing else
# usage: ./MapLoader_v3.1.0_linux.sh [path to CloudSave folder]

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
arg_path = sys.argv[2] if len(sys.argv) > 2 else None
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
    print(cyan("Using current directory as base: " + root))
elif os.path.exists(os.path.join(os.path.dirname(script_dir), "CloudSaveManifest.json")):
    root = os.path.dirname(script_dir)
    print(cyan("Using current directory as base: " + root))
else:
    found = find_game_path()
    if found:
        root = found
        print(green("Automatically found Splitgate CloudSave folder:"))
        print(cyan("  " + root))
    else:
        root = script_dir
        print(yellow("Splitgate CloudSave folder not found."))
        print(yellow("Using current directory as base: " + root))
        print(yellow("Tip: pass the CloudSave path as an argument."))
print("")

manifest_path = os.path.join(root, "CloudSaveManifest.json")

for name in CONTENT_TYPES:
    d = os.path.join(root, name)
    if not os.path.isdir(d):
        os.makedirs(d)
        print(cyan("Automatically created missing folder: " + name))
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
        print("  Skipping %s (already exists in %s)" % (item, ctype))
        return
    open(dest, "wb").write(data)
    print("  Imported %s -> %s" % (item, ctype))

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
                    print("  Unknown content type for %s, skipping" % item)
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
                    print("  Unknown content type for %s, skipping" % item)
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
    print(cyan("First run detected."))
    answer = ask("Do you want to back up your current MapCreator / MapCreatorPrefab folders (and the manifest) first? (Y/N)")
else:
    answer = "N"

if re.match(r"^[Yy]", answer):
    dest = os.path.join(backup_root, datetime.now().strftime("%Y-%m-%d") + "-Backup")
    os.makedirs(backup_root, exist_ok=True)
    if os.path.exists(dest):
        print("A backup for today already exists, overwriting it: " + dest)
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in CONTENT_TYPES:
        src = os.path.join(root, name)
        if not os.path.isdir(src):
            continue
        folders = list_dirs(src)
        if not folders:
            print("Skipping backup of %s (no native map folders)" % name)
            continue
        print("Backing up native maps only ...")
        for f in folders:
            shutil.copytree(os.path.join(src, f), os.path.join(dest, name, f))
    if os.path.exists(manifest_path):
        shutil.copy2(manifest_path, os.path.join(dest, "CloudSaveManifest.json"))
        print("Backed up CloudSaveManifest.json")
    print("Backup done: " + dest)
elif first_run:
    print("Skipping backup.")
os.makedirs(backup_root, exist_ok=True)
print("")

# --- part 2: read the manifest ---
existing_by_id = {}
manifest_version = 1
synced = True
enc = "utf-8"

if os.path.exists(manifest_path):
    print("Reading existing manifest ...")
    try:
        text, enc = read_manifest_text(manifest_path)
        existing = json.loads(text)
    except Exception as e:
        print("")
        print(red("Could not parse CloudSaveManifest.json, stopping so nothing gets broken."))
        print(red("Error: %s" % e))
        sys.exit(1)
    if existing:
        if existing.get("Version") is not None:
            manifest_version = existing["Version"]
        if existing.get("HasSyncedFromBackend") is not None:
            synced = existing["HasSyncedFromBackend"]
        for f in existing.get("Files") or []:
            existing_by_id[f["FileId"]] = f
    print("Parsed manifest: version %s, %d entries" % (manifest_version, len(existing_by_id)))
else:
    print("No manifest found, a new one will be created.")

default_owner = None
if existing_by_id:
    native = [e["OwnerId"] for e in existing_by_id.values() if not is_community(e) and e.get("OwnerId")]
    anyone = [e["OwnerId"] for e in existing_by_id.values() if e.get("OwnerId")]
    pool = native or anyone
    if pool:
        default_owner = Counter(pool).most_common(1)[0][0]
if not default_owner:
    print(yellow("No OwnerId found. Save at least one map of your own in the Map Lab first."))
print("")

# --- part 2.5: packs and loose files ---
print("Scanning for packs and loose .bin files ...")
found_any = False
processed_packs = []

scan_dirs = [root] + [os.path.join(root, t) for t in CONTENT_TYPES]
for loc in scan_dirs:
    if not os.path.isdir(loc):
        continue
    for n in list_files(loc):
        if n.lower().endswith(PACK_EXTS):
            found_any = True
            print("  Found pack: " + n)
            p = os.path.join(loc, n)
            try:
                expand_pack(p, root)
                processed_packs.append(p)
            except Exception as e:
                print(red("  Could not read pack %s: %s" % (n, e)))

# loose bins in the root
for n in list_files(root, ".bin"):
    found_any = True
    print("  Loose .bin found in root: " + n)
    p = os.path.join(root, n)
    ctype = type_from_file(p)
    if not ctype:
        print("  Unknown content type for %s, skipping" % n[:-4])
        continue
    dest = os.path.join(root, ctype, n)
    if os.path.exists(dest):
        print("  Skipping %s (already exists in %s)" % (n[:-4], ctype))
    else:
        shutil.move(p, dest)
        print("  Imported %s -> %s" % (n[:-4], ctype))

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
            print("  %s is in the wrong folder (%s)" % (n, cur))
            dest = os.path.join(root, detected, n)
            if os.path.exists(dest):
                print("  Skipping %s (already exists in %s)" % (n[:-4], detected))
            else:
                shutil.move(p, dest)
                print("  Moved %s: %s -> %s" % (n[:-4], cur, detected))

if not found_any:
    print("Nothing to import.")
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
            print("  Skipping %s (folder exists but has no .bin files inside - likely an unsaved/empty draft)" % fid)
            continue

        if not has_comm and old:
            has_comm = is_community(old)

        if old:
            fname = old.get("FileName")
            owner = old.get("OwnerId")
            author = old.get("AuthorDisplayName")
            created_top = old.get("CreatedAt")
            action = "UPDATED"
        else:
            fname = ("%s %s" % (COMMUNITY_TAG, fid)) if has_comm else fid
            owner = default_owner
            author = ""
            created_top = iso_now()
            action = "NEW"

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
        print("  REMOVED: %s" % old["FileId"])
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
print(green("Done! Manifest written to " + manifest_path))
print("Total entries: %d (native: %d, community: %d)" % (len(new_files), native_count, len(new_files) - native_count))

if processed_packs:
    print("")
    ans = ask("Delete the %d processed pack file(s)? (Y = delete, N = move to Backup/Packs)" % len(processed_packs))
    for p in processed_packs:
        n = os.path.basename(p)
        if re.match(r"^[Yy]", ans):
            os.remove(p)
            print("  Deleted " + n)
        else:
            pd = os.path.join(backup_root, "Packs")
            os.makedirs(pd, exist_ok=True)
            shutil.move(p, os.path.join(pd, n))
            print("  Moved %s to Backup/Packs" % n)
PY

python3 -c "$PYCODE" "$SCRIPT_DIR" "$@"
status=$?

# keep the window open if double clicked
if [ -t 0 ] && [ -z "$MAPLOADER_NO_PAUSE" ]; then
    read -r -p "Press Enter to close ..." _
fi
exit $status
