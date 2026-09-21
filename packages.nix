{ pkgs }:
let
  releaseInfo = import ./release-linux.nix;

  sohAppImage = pkgs.appimageTools.wrapType2 {
    pname = "shipofharkinian";
    inherit (releaseInfo) version;
    src = pkgs.stdenvNoCC.mkDerivation {
      pname = "shipofharkinian-appimage";
      inherit (releaseInfo) version;
      src = pkgs.fetchzip {
        inherit (releaseInfo) name hash url;
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
    extraPkgs = pkgs: [
      pkgs.zenity
    ];
  };
  sohLauncher =
    {
      datadir ? "\${XDG_DATA_HOME:-$HOME/.local/share}/shipofharkinian",
    }:
    pkgs.writeShellScriptBin "ShipOfHarkinian" ''
      set -eu

      datadir="${datadir}"
      appimage="$datadir/soh.appimage"

      if [ ! -x "$appimage" ]; then
        echo "AppImage missing in data dir; run home manager activation first" >&2
        exit 1
      fi
      cd "$datadir"
      export APPIMAGE="$appimage"
      exec "$appimage" "$@"
    '';
in
{
  inherit sohAppImage sohLauncher;
}
