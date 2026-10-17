#!/usr/bin/env python3
import os
import glob
import re
import json
import sqlite3
try:
    import yaml
except ImportError:
    yaml = None

def scan_all():
    mapping = {}

    home = os.path.expanduser("~")
    app_dir = os.path.join(home, ".local/share/applications")
    lutris_dir = os.path.join(home, ".local/share/lutris/games")
    lutris_db = os.path.join(home, ".local/share/lutris/pga.db")

    # 1. Index Lutris desktop files by slug and gameid
    lutris_dt_by_slug = {}
    lutris_dt_by_id = {}
    if os.path.exists(app_dir):
        for dt in glob.glob(os.path.join(app_dir, "net.lutris.*.desktop")):
            base = os.path.basename(dt)[:-8]  # remove .desktop
            # Format: net.lutris.<slug>-<id>
            m = re.match(r"^net\.lutris\.(.*?)(?:-(\d+))?$", base)
            if m:
                slug = m.group(1).lower()
                gid = m.group(2)
                lutris_dt_by_slug[slug] = base
                if gid:
                    lutris_dt_by_id[gid] = base

    # 2. Index Lutris Database (pga.db)
    if os.path.exists(lutris_db):
        try:
            conn = sqlite3.connect(lutris_db)
            cur = conn.cursor()
            cur.execute("SELECT id, name, slug FROM games")
            for gid, name, slug in cur.fetchall():
                if slug:
                    s_low = slug.lower()
                    dt_id = lutris_dt_by_slug.get(s_low) or lutris_dt_by_id.get(str(gid)) or f"net.lutris.{s_low}-{gid}"
                    icon_name = f"lutris_{s_low}"
                    entry = {"desktopId": dt_id, "icon": icon_name, "name": name or slug}
                    mapping[s_low] = entry
                    if name:
                        mapping[name.lower()] = entry
            conn.close()
        except Exception:
            pass

    # 3. Index Lutris Game YAML configs (maps exact Windows executable path/filename to game)
    if yaml and os.path.exists(lutris_dir):
        for yf in glob.glob(os.path.join(lutris_dir, "*.yml")):
            try:
                with open(yf, "r", encoding="utf-8", errors="ignore") as fp:
                    data = yaml.safe_load(fp) or {}
                    exe = data.get("game", {}).get("exe", "")
                    if exe:
                        base_exe = os.path.basename(exe).lower()
                        fname = os.path.basename(yf)[:-4]  # remove .yml
                        # Extract slug: deltarune-1782315772 -> deltarune
                        slug_cand = re.sub(r"-\d+$", "", fname).lower()
                        dt_id = lutris_dt_by_slug.get(slug_cand) or f"net.lutris.{fname}"
                        icon_name = f"lutris_{slug_cand}"
                        entry = {"desktopId": dt_id, "icon": icon_name, "exe": exe}
                        mapping[base_exe] = entry
                        no_ext = re.sub(r"\.exe$", "", base_exe)
                        mapping[no_ext] = entry
            except Exception:
                pass

    # 4. Scan all .desktop files across user and system directories
    for p in ["/usr/share/applications", app_dir]:
        if not os.path.exists(p):
            continue
        for dt in glob.glob(os.path.join(p, "*.desktop")):
            try:
                with open(dt, "r", encoding="utf-8", errors="ignore") as fp:
                    content = fp.read()
                    base_id = os.path.basename(dt)[:-8]
                    name = ""
                    icon = ""
                    exec_line = ""
                    for line in content.splitlines():
                        if line.startswith("Name=") and not name:
                            name = line[5:].strip()
                        elif line.startswith("Icon=") and not icon:
                            icon = line[5:].strip()
                        elif line.startswith("Exec=") and not exec_line:
                            exec_line = line[5:].strip()

                    entry = {"desktopId": base_id, "icon": icon, "name": name}
                    if name:
                        mapping[name.lower()] = entry

                    # Match Windows .exe in Exec line
                    exe_match = re.search(r'([a-zA-Z0-9_\-\s\(\)]+\.exe)', exec_line, re.IGNORECASE)
                    if exe_match:
                        exe_name = exe_match.group(1).lower()
                        mapping[exe_name] = entry
                        mapping[re.sub(r"\.exe$", "", exe_name)] = entry

                    # Match Steam App ID in Exec line
                    steam_match = re.search(r'rungameid[/%](\d+)', exec_line)
                    if steam_match:
                        sid = steam_match.group(1)
                        mapping[f"steam_app_{sid}"] = entry
                        mapping[sid] = entry
            except Exception:
                pass

    # 5. Scan Steam libraryfolders and appmanifest files
    steam_roots = [
        os.path.join(home, ".local/share/Steam"),
        os.path.join(home, ".steam/steam"),
    ]
    for sroot in steam_roots:
        vdf = os.path.join(sroot, "steamapps", "libraryfolders.vdf")
        if os.path.exists(vdf):
            try:
                with open(vdf, "r", encoding="utf-8", errors="ignore") as fp:
                    vdf_text = fp.read()
                    lpaths = re.findall(r'"path"\s+"([^"]+)"', vdf_text)
                    for lp in lpaths:
                        for acf in glob.glob(os.path.join(lp, "steamapps", "appmanifest_*.acf")):
                            try:
                                with open(acf, "r", encoding="utf-8", errors="ignore") as afp:
                                    ac_text = afp.read()
                                    m_id = re.search(r'"appid"\s+"(\d+)"', ac_text)
                                    m_name = re.search(r'"name"\s+"([^"]+)"', ac_text)
                                    if m_id and m_name:
                                        sid = m_id.group(1)
                                        sname = m_name.group(1)
                                        icon_file = f"steam_icon_{sid}"
                                        entry = {
                                            "desktopId": f"steam_app_{sid}",
                                            "icon": icon_file,
                                            "name": sname,
                                        }
                                        mapping[f"steam_app_{sid}"] = entry
                                        mapping[sid] = entry
                                        mapping[sname.lower()] = entry
                            except Exception:
                                pass
            except Exception:
                pass


    return mapping

if __name__ == "__main__":
    try:
        data = scan_all()
        print(json.dumps(data, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({}))
