{
  displayName = "Ship of Harkinian";
  launcherName = "ShipOfHarkinian";
  appimageSymlink = "soh.appimage";
  releaseInfo = import ./release-linux.nix;
  repo = "HarbourMasters/Shipwright";
  desktopFile = ./project.desktop;
  iconFile = ./icon.png;
  steamArtwork = {
    icon = ./icon.png;
    logo = ./logo.png;
  };
  extraPkgs = pkgs: [ pkgs.zenity ];
}
