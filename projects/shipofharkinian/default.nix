{
  displayName = "Ship of Harkinian";
  launcherName = "ShipOfHarkinian";
  appimageSymlink = "soh.appimage";
  releaseInfo = import ./release-linux.nix;
  repo = "HarbourMasters/Shipwright";
  desktopFile = ./soh.desktop;
  iconFile = ./soh.png;
  extraPkgs = pkgs: [ pkgs.zenity ];
}
