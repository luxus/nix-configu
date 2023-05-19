{
  config,
  inputs,
  lib,
  nixos-hardware,
  pkgs,
  ...
}: {
  imports = [
    nixos-hardware.common-cpu-intel
    nixos-hardware.common-pc-ssd

    ../common/core
    ../common/hardware/intel.nix
    ../common/hardware/physical.nix
    ../common/initrd-ssh.nix
    ../common/efi.nix
    ../common/zfs.nix

    ../../users/root

    ./fs.nix
    ./net.nix
  ];

  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" "r8169"];

  extra.microvms = {
    vms.test = {
      id = 11;
      system = "x86_64-linux";
      autostart = true;
      zfs = {
        enable = true;
        pool = "rpool";
        dataset = "safe/vms/test";
        mountpoint = "/persist/vms/test";
      };
    };
  };
}
