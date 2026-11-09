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
  missingname = "missing-image.z64";
  missingimg = "${testdir}/${missingname}";
in
pkgs.testers.runNixOSTest {
  name = "shipofharkinian-hm-test";
  nodes.machine = { ... }: {
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
    # Pre-populate a dummy ROM while leaving missingimg absent to test warning + skip
    systemd.tmpfiles.rules = [
      "d ${testdir} 0700 test users - -"
      "f ${testimg} 0644 test users - MOCK_ROM"
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
          gamepaths = [
            testimg
            missingimg
          ];
        };
      };
    };
  };

  testScript = ''
    start_all()

    with subtest("Wait for Home Manager activation to finish"):
        machine.wait_for_unit("home-manager-test.service")

    with subtest("Verify file locations and links in custom datadir"):
        datadir = "${datadir}"
        machine.succeed(f"test -L {datadir}/soh.appimage")
        machine.succeed(f"test -x {datadir}/soh.appimage")
        machine.succeed(f"test -L {datadir}/${imgname}")
        machine.succeed(f"cmp -s ${testimg} {datadir}/${imgname}")
        machine.succeed(f"test ! -e {datadir}/${missingname} && test ! -L {datadir}/${missingname}")
        machine.succeed("journalctl -u home-manager-test.service | grep -F 'Warning: image path does not exist, skipping: ${missingimg}'")

    with subtest("Verify launcher script in PATH points to custom datadir"):
        machine.succeed("su - test -c 'which ShipOfHarkinian'")
        machine.succeed("grep -F '${datadir}' $(su - test -c 'which ShipOfHarkinian')")
        machine.succeed("test -f ${testdir}/.local/share/applications/shipofharkinian.desktop")

    with subtest("Verify dangling symlinks are cleaned up on re-activation"):
        datadir = "${datadir}"
        machine.succeed(f"ln -s /nonexistent/missing.z64 {datadir}/${missingname}")
        machine.succeed(f"ln -s /nonexistent/stale.z64 {datadir}/stale-rom.z64")
        machine.succeed("rm ${testimg}")
        machine.succeed("systemctl restart home-manager-test.service")
        machine.succeed(f"test ! -L {datadir}/${missingname}")
        machine.succeed(f"test ! -L {datadir}/stale-rom.z64")
        machine.succeed(f"test ! -L {datadir}/${imgname}")
        machine.succeed(f"test -L {datadir}/soh.appimage && test -e {datadir}/soh.appimage")
  '';
}
