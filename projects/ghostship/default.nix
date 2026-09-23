{
  displayName = "Ghostship";
  launcherName = "Ghostship";
  appimageSymlink = "ghostship.appimage";
  releaseInfo = import ./release-linux.nix;
  repo = "HarbourMasters/Ghostship";
  desktopFile = ./project.desktop;
  iconFile = ./icon.png;
  steamArtwork = {
    icon = ./icon.png;
  };
  extraPkgs = pkgs: [ pkgs.zenity ];
}
