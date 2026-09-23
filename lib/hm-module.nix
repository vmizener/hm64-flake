{
  self,
  projectsDir,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  projectNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir projectsDir)
  );

  mkLauncher = pkgs.callPackage ./mk-launcher.nix { };
  mkSteamShortcut = pkgs.callPackage ./mk-steam-shortcut.nix { };

  mkProjectOptions =
    pname:
    let
      project = import (projectsDir + "/${pname}");
      inherit (project) displayName;
      defaultArtwork = project.steamArtwork or { };
      mkArtworkOption =
        slot: desc:
        lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = defaultArtwork.${slot} or null;
          description = ''
            Optional path to the Steam ${desc} image (${slot}) for ${displayName}.
          '';
        };
    in
    {
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
      steam = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.programs.harbourmasters.steam.enable;
          defaultText = lib.literalExpression "config.programs.harbourmasters.steam.enable";
          description = ''
            Whether to add ${displayName} to the local Steam installation as a non-Steam game.
          '';
        };
        artwork = {
          poster = mkArtworkOption "poster" "vertical library capsule/poster (600x900)";
          hero = mkArtworkOption "hero" "top hero banner (1920x620)";
          logo = mkArtworkOption "logo" "transparent title logo";
          grid = mkArtworkOption "grid" "horizontal wide capsule/banner (920x430)";
          icon = mkArtworkOption "icon" "square shortcut icon";
        };
      };
    };

  mkProjectConfig =
    pname:
    let
      project = import (projectsDir + "/${pname}");
      inherit (project) displayName;
      cfg = config.programs.harbourmasters.${pname};
      launcher = mkLauncher {
        inherit pname;
        inherit (project) launcherName appimageSymlink;
        inherit (cfg) datadir;
      };
      steamShortcutUpdater = mkSteamShortcut {
        inherit pname;
        appName = displayName;
        exePath = "${cfg.datadir}/${project.launcherName}";
        startDir = cfg.datadir;
        inherit (config.programs.harbourmasters.steam) steampath;
        inherit (cfg.steam) artwork;
      };
    in
    lib.mkIf cfg.enable {
      home.packages = [ launcher ];

      home.activation.${pname} = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datadir="${cfg.datadir}"
        mkdir -p "$datadir"
        ln -sfn "${lib.getExe cfg.package}" "$datadir/${project.appimageSymlink}"
        ln -sfn "${lib.getExe launcher}" "$datadir/${project.launcherName}"

        ${lib.concatMapStringsSep "\n" (path: ''
          source=${lib.escapeShellArg path}
          target=$datadir/$(basename "$source")
          if [ ! -f "$source" ]; then
            echo "Image path does not exist: $source" >&2
            exit 1
          fi
          ln -sfn "$source" "$target"
        '') cfg.gamepaths}

        ${lib.optionalString cfg.steam.enable ''
          ${lib.getExe steamShortcutUpdater}
        ''}
      '';

      xdg.dataFile = {
        "applications/${pname}.desktop".source = project.desktopFile;
        "icons/hicolor/512x512/apps/${pname}.png".source = project.iconFile;
      };
    };
in
{
  options.programs.harbourmasters = {
    steam = {
      enable = lib.mkEnableOption "Steam non-Steam game shortcut and artwork integration for HarbourMasters projects";
      steampath = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.dataHome}/Steam";
        defaultText = "$XDG_DATA_HOME/Steam";
        description = ''
          Directory containing the local Steam installation data (including `userdata/`).
        '';
      };
    };
  }
  // lib.genAttrs projectNames mkProjectOptions;

  config = lib.mkMerge (map mkProjectConfig projectNames);
}
