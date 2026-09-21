{
  description = "Ship of Harkinian home-manager flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      git-hooks-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPackages =
        system:
        import ./packages.nix {
          pkgs = import nixpkgs { inherit system; };
        };
      mkTests =
        system:
        import ./tests {
          inherit home-manager self;
          pkgs = import nixpkgs { inherit system; };
        };
      mkGitHooks =
        system:
        git-hooks-nix.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          syspkgs = mkPackages system;
          tests = mkTests system;
        in
        rec {
          default = shipofharkinian-appimage;
          shipofharkinian-appimage = syspkgs.sohAppImage;
          shipofharkinian-launcher = syspkgs.sohLauncher { };

          all-checks = pkgs.linkFarm "all-checks" (
            tests.all
            // {
              package-builds = syspkgs.sohLauncher { };
            }
          );
        }
      );

      checks = forAllSystems (
        system:
        let
          syspkgs = mkPackages system;
          tests = mkTests system;
          gitHooks = mkGitHooks system;
        in
        {
          pre-commit-check = gitHooks;
          package-builds = syspkgs.sohLauncher { };
        }
        // tests.fast
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          gitHooks = mkGitHooks system;
        in
        {
          default = pkgs.mkShell {
            inherit (gitHooks) shellHook;
            buildInputs = gitHooks.enabledPackages;
          };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);

      homeManagerModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.shipofharkinian;
          syspkgs = mkPackages pkgs.stdenv.hostPlatform.system;
        in
        {
          options.programs.shipofharkinian = {
            enable = lib.mkEnableOption "Ship of Harkinian";
            datadir = lib.mkOption {
              type = lib.types.str;
              default = "${config.xdg.dataHome}/shipofharkinian";
              defaultText = "$XDG_DATA_HOME/shipofharkinian";
              description = ''
                Directory to write SoH assets (e.g. the AppImage).
              '';
            };
            gamepaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                Absolute paths to legal image dumps to include with SoH.
                Images are copied into the SoH data directory.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [
              (syspkgs.sohLauncher { inherit (cfg) datadir; })
            ];

            home.activation.shipofharkinian = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              datadir="${cfg.datadir}"
              mkdir -p "$datadir"
              ln -sfn "${lib.getExe syspkgs.sohAppImage}" "$datadir/soh.appimage"

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
              "applications/shipofharkinian.desktop".source = ./soh.desktop;
              "icons/hicolor/512x512/apps/shipofharkinian.png".source = ./soh.png;
            };
          };
        };
    };
}
