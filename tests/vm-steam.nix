{
  pkgs,
  home-manager,
  self,
}:
let
  testdir = "/home/test";
  datadir = "${testdir}/games/shipofharkinian";
  imgname = "test-image.z64";
  testimg = "${testdir}/${imgname}";
  steamUserConfig = "${testdir}/.local/share/Steam/userdata/12345678/config";
in
pkgs.testers.runNixOSTest {
  name = "shipofharkinian-steam-hm-test";
  nodes.machine =
    { ... }:
    {
      imports = [ home-manager.nixosModules.home-manager ];
      virtualisation.qemu.options = [
        "-machine"
        "accel=tcg" # Run without hardware KVM
      ];
      users.users.test = {
        isNormalUser = true;
        home = "${testdir}";
        uid = 1000;
      };
      # Pre-populate the dummy ROM and mock Steam userdata directory so Home Manager activation succeeds on boot
      systemd.tmpfiles.rules = [
        "d ${testdir} 0700 test users - -"
        "f ${testimg} 0644 test users - MOCK_ROM"
        "d ${testdir}/.local 0755 test users - -"
        "d ${testdir}/.local/share 0755 test users - -"
        "d ${testdir}/.local/share/Steam 0755 test users - -"
        "d ${testdir}/.local/share/Steam/userdata 0755 test users - -"
        "d ${testdir}/.local/share/Steam/userdata/12345678 0755 test users - -"
        "d ${steamUserConfig} 0755 test users - -"
      ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.test = {
          imports = [ self.homeManagerModules.default ];
          home.stateVersion = "25.05";
          programs.harbourmasters.shipofharkinian = {
            enable = true;
            datadir = "${datadir}";
            gamepaths = [ "${testimg}" ];
            steam.enable = true;
          };
        };
      };
    };

  testScript = ''
    start_all()

    with subtest("Wait for Home Manager activation to finish"):
        machine.wait_for_unit("home-manager-test.service")

    with subtest("Verify stable launcher symlink in datadir"):
        machine.succeed("test -L ${datadir}/ShipOfHarkinian")
        machine.succeed("test -x ${datadir}/ShipOfHarkinian")

    with subtest("Verify Steam shortcuts.vdf and grid artwork"):
        machine.succeed("test -s ${steamUserConfig}/shortcuts.vdf")
        machine.succeed("ls ${steamUserConfig}/grid/*_logo.png")
        machine.succeed("ls ${steamUserConfig}/grid/*_icon.png")
        machine.fail("ls ${steamUserConfig}/grid/*_hero*")
        machine.fail("ls ${steamUserConfig}/grid/*p.png")
  '';
}
