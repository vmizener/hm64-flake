{
  writeShellScriptBin,
}:
{
  pname,
  launcherName,
  appimageSymlink,
  datadir ? "\${XDG_DATA_HOME:-$HOME/.local/share}/${pname}",
}:
writeShellScriptBin launcherName ''
  set -eu

  datadir="${datadir}"
  appimage="$datadir/${appimageSymlink}"

  if [ ! -x "$appimage" ]; then
    echo "AppImage missing in data dir; run home manager activation first" >&2
    exit 1
  fi
  cd "$datadir"
  export APPIMAGE="$appimage"
  exec "$appimage" "$@"
''
