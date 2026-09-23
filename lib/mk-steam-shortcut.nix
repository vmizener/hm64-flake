{
  python3,
  writeScriptBin,
}:
{
  pname,
  appName,
  exePath,
  startDir,
  steampath,
  artwork ? { },
}:
let
  pythonEnv = python3.withPackages (ps: [ ps.vdf ]);
  toStr = val: if val == null then "" else toString val;
in
writeScriptBin "update-steam-shortcut-${pname}" ''
  #!${pythonEnv}/bin/python3
  import os
  import pathlib
  import zlib
  import vdf

  app_name = ${builtins.toJSON appName}
  exe_path = ${builtins.toJSON exePath}
  start_dir = ${builtins.toJSON startDir}
  steam_datadir = pathlib.Path(${builtins.toJSON steampath})

  artwork = {
      "p": ${builtins.toJSON (toStr (artwork.poster or null))},
      "_hero": ${builtins.toJSON (toStr (artwork.hero or null))},
      "_logo": ${builtins.toJSON (toStr (artwork.logo or null))},
      "": ${builtins.toJSON (toStr (artwork.grid or null))},
      "_icon": ${builtins.toJSON (toStr (artwork.icon or null))},
  }

  userdata_dir = steam_datadir / "userdata"
  if not userdata_dir.is_dir():
      print(f"Steam userdata directory not found at {userdata_dir}; skipping Steam shortcut for {app_name}.")
      raise SystemExit(0)

  user_dirs = [
      d for d in sorted(userdata_dir.iterdir())
      if d.is_dir() and d.name.isdigit() and d.name != "0"
  ]
  if not user_dirs:
      print(f"No Steam user profiles found in {userdata_dir}; skipping Steam shortcut for {app_name}.")
      raise SystemExit(0)

  quoted_exe = f'"{exe_path}"'
  quoted_start_dir = f'"{start_dir}"'
  unsigned_appid = (zlib.crc32((quoted_exe + app_name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000
  signed_appid = unsigned_appid - 0x100000000
  icon_path = artwork["_icon"]

  for user_dir in user_dirs:
      config_dir = user_dir / "config"
      config_dir.mkdir(parents=True, exist_ok=True)
      shortcuts_path = config_dir / "shortcuts.vdf"

      data = {"shortcuts": {}}
      if shortcuts_path.is_file() and shortcuts_path.stat().st_size > 0:
          try:
              with shortcuts_path.open("rb") as f:
                  loaded = vdf.binary_load(f)
              if isinstance(loaded, dict):
                  data = loaded
          except Exception as exc:
              print(f"Warning: failed to parse {shortcuts_path} ({exc}); starting fresh.")

      shortcuts_key = next((k for k in data if k.lower() == "shortcuts"), "shortcuts")
      shortcuts = data.setdefault(shortcuts_key, {})

      target_idx = None
      for idx, entry in shortcuts.items():
          if not isinstance(entry, dict):
              continue
          entry_name = entry.get("AppName") or entry.get("appname")
          entry_exe = entry.get("Exe") or entry.get("exe")
          if (
              entry.get("appid") == signed_appid
              or entry_name == app_name
              or entry_exe == quoted_exe
          ):
              target_idx = idx
              break

      if target_idx is None:
          numeric_keys = [int(k) for k in shortcuts if str(k).isdigit()]
          target_idx = str(max(numeric_keys, default=-1) + 1)
          shortcuts[target_idx] = {
              "appid": signed_appid,
              "AppName": app_name,
              "Exe": quoted_exe,
              "StartDir": quoted_start_dir,
              "icon": icon_path,
              "ShortcutPath": "",
              "LaunchOptions": "",
              "IsHidden": 0,
              "AllowDesktopConfig": 1,
              "AllowOverlay": 1,
              "OpenVR": 0,
              "Devkit": 0,
              "DevkitGameID": "",
              "DevkitOverrideAppID": 0,
              "LastPlayTime": 0,
              "FlatpakAppID": "",
              "tags": {},
          }
      else:
          entry = shortcuts[target_idx]
          entry["appid"] = signed_appid
          entry["AppName"] = app_name
          entry["Exe"] = quoted_exe
          entry["StartDir"] = quoted_start_dir
          entry["icon"] = icon_path

      tmp_path = shortcuts_path.with_suffix(".vdf.tmp")
      with tmp_path.open("wb") as f:
          vdf.binary_dump(data, f)
      tmp_path.replace(shortcuts_path)

      grid_dir = config_dir / "grid"
      grid_dir.mkdir(parents=True, exist_ok=True)
      for suffix, src in artwork.items():
          if not src:
              continue
          src_ext = pathlib.Path(src).suffix or ".png"
          for old_ext in (".png", ".jpg", ".jpeg"):
              candidate = grid_dir / f"{unsigned_appid}{suffix}{old_ext}"
              if candidate.is_symlink() or candidate.exists():
                  candidate.unlink()
          dest = grid_dir / f"{unsigned_appid}{suffix}{src_ext}"
          os.symlink(src, dest)
''
