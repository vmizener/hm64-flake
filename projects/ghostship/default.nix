{
  displayName = "Ghostship";
  launcherName = "Ghostship";
  appimageSymlink = "ghostship.appimage";
  releaseInfo = import ./release-linux.nix;
  repo = "HarbourMasters/Ghostship";
  desktopFile = ./project.desktop;
  iconFile = ./project.png;
  extraPkgs = pkgs: [ pkgs.zenity ];
}
