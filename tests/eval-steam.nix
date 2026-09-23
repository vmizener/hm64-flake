{
  pkgs,
  home-manager,
  self,
}:
let
  testHomeConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeManagerModules.default
      {
        home = {
          username = "test";
          homeDirectory = "/home/test";
          stateVersion = "25.05";
        };
        programs.harbourmasters = {
          steam = {
            enable = true;
            steampath = "/home/test/.steam/steam";
          };
          shipofharkinian = {
            enable = true;
            gamepaths = [
              "/home/test/image1.z64"
            ];
            steam.artwork.poster = ../projects/shipofharkinian/icon.png;
          };
          ghostship = {
            enable = true;
          };
        };
      }
    ];
  };
in
testHomeConfig.activationPackage
