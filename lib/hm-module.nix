{
  self,
  pname,
  projectDir,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  project = import projectDir;
  inherit (project) displayName;
  cfg = config.programs.harbourmasters.${pname};
  mkLauncher = pkgs.callPackage ./mk-launcher.nix { };
in
{
  options.programs.harbourmasters.${pname} = {
    enable = lib.mkEnableOption displayName;
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}."${pname}-appimage";
      defaultText = lib.literalExpression "pkgs.${pname}-appimage";
      description = ''
        The ${displayName} AppImage package to use.
      '';
    };
    datadir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/${pname}";
      defaultText = "$XDG_DATA_HOME/${pname}";
      description = ''
        Directory to write ${displayName} assets (e.g. the AppImage).
      '';
    };
    gamepaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Absolute paths to legal image dumps to include with ${displayName}.
        Images are copied into the ${displayName} data directory.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (mkLauncher {
        inherit pname;
        inherit (project) launcherName appimageSymlink;
        inherit (cfg) datadir;
      })
    ];

    home.activation.${pname} = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      datadir="${cfg.datadir}"
      mkdir -p "$datadir"
      ln -sfn "${lib.getExe cfg.package}" "$datadir/${project.appimageSymlink}"

      ${lib.concatMapStringsSep "\n" (path: ''
        source=${lib.escapeShellArg path}
        target=$datadir/$(basename "$source")
        if [ ! -f "$source" ]; then
          echo "Image path does not exist: $source" >&2
          exit 1
        fi
        ln -sfn "$source" "$target"
      '') cfg.gamepaths}
    '';
    xdg.dataFile = {
      "applications/${pname}.desktop".source = project.desktopFile;
      "icons/hicolor/512x512/apps/${pname}.png".source = project.iconFile;
    };
  };
}
