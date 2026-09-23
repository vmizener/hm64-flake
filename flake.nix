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
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      projectNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./projects)
      );

      mkAllPackages =
        system:
        let
          pkgs = pkgsFor system;
          mkAppImage = pkgs.callPackage ./lib/mk-appimage.nix { };
          mkLauncher = pkgs.callPackage ./lib/mk-launcher.nix { };
        in
        builtins.foldl' (
          acc: pname:
          let
            project = import (./projects + "/${pname}");
          in
          acc
          // {
            "${pname}-appimage" = mkAppImage {
              inherit pname;
              inherit (project)
                releaseInfo
                repo
                ;
              extraPkgs = project.extraPkgs or (_: [ ]);
            };
            "${pname}-launcher" = mkLauncher {
              inherit pname;
              inherit (project)
                launcherName
                appimageSymlink
                ;
            };
          }
        ) { } projectNames;
      mkTests =
        system:
        import ./tests {
          inherit home-manager self;
          pkgs = pkgsFor system;
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
          pkgs = pkgsFor system;
          projectPackages = mkAllPackages system;
          tests = mkTests system;
        in
        projectPackages
        // {
          default = projectPackages.shipofharkinian-appimage;

          all-checks = pkgs.linkFarm "all-checks" (
            tests.all
            // {
              package-builds = pkgs.linkFarm "package-builds" projectPackages;
            }
          );
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          projectPackages = mkAllPackages system;
          tests = mkTests system;
          gitHooks = mkGitHooks system;
        in
        {
          pre-commit-check = gitHooks;
          package-builds = pkgs.linkFarm "package-builds" projectPackages;
        }
        // tests.fast
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          gitHooks = mkGitHooks system;
        in
        {
          default = pkgs.mkShell {
            inherit (gitHooks) shellHook;
            buildInputs = gitHooks.enabledPackages;
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      homeManagerModules =
        let
          hmModule = import ./lib/hm-module.nix {
            inherit self;
            projectsDir = ./projects;
          };
        in
        nixpkgs.lib.genAttrs projectNames (_: hmModule)
        // {
          default = hmModule;
        };
    };
}
