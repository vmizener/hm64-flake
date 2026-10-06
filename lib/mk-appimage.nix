{
  appimageTools,
  fetchurl,
  fetchzip,
  lib,
  stdenvNoCC,
}:
{
  pname,
  releaseInfo,
  repo,
  asset ? releaseInfo.asset or "${releaseInfo.name}-Linux.zip",
  url ? "https://github.com/${repo}/releases/download/${releaseInfo.version}/${asset}",
  extraPkgs ? (_: [ ]),
}:
let
  isZip = lib.hasSuffix ".zip" (lib.toLower asset);
  appimageSrc =
    if isZip then
      stdenvNoCC.mkDerivation {
        pname = "${pname}-appimage";
        inherit (releaseInfo) version;
        src = fetchzip {
          inherit (releaseInfo) hash;
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
      }
    else
      fetchurl {
        inherit (releaseInfo) hash;
        inherit url;
      };
in
appimageTools.wrapType2 {
  inherit pname extraPkgs;
  inherit (releaseInfo) version;
  src = appimageSrc;
}
