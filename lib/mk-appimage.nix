{
  appimageTools,
  fetchzip,
  stdenvNoCC,
}:
{
  pname,
  releaseInfo,
  repo,
  url ? "https://github.com/${repo}/releases/download/${releaseInfo.version}/${releaseInfo.name}-Linux.zip",
  extraPkgs ? (_: [ ]),
}:
appimageTools.wrapType2 {
  inherit pname extraPkgs;
  inherit (releaseInfo) version;
  src = stdenvNoCC.mkDerivation {
    pname = "${pname}-appimage";
    inherit (releaseInfo) version;
    src = fetchzip {
      inherit (releaseInfo) name hash;
      inherit url;
      stripRoot = false;
    };
    dontConfigure = true;
    installPhase = ''
      runHook preInstall
      appimage="$(find . -type f -iname '*.appimage' -print -quit)"
      if [ -z "$appimage" ]; then
        echo "AppImage missing from source archive" >&2
        exit 1
      fi
      install -Dm755 "$appimage" "$out"
      runHook postInstall
    '';
  };
}
