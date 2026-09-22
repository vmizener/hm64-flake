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
        programs.harbourmasters.shipofharkinian = {
          enable = true;
          gamepaths = [
            "/home/test/image1.z64"
            "/home/test/image2.z64"
          ];
        };
      }
    ];
  };
in
testHomeConfig.activationPackage
