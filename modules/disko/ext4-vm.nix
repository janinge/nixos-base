{ config, lib, pkgs, modulesPath, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
  rootDevice = cfg.rootDevice or "/dev/vda";
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  disko.devices = {
    disk.main = {
      type = "disk";
      device = rootDevice;
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "pool";
            };
          };
        };
      };
    };

    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = cfg.swapSize or "8G";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };

          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "defaults"
                "noatime"
                "discard"
                "commit=60"
              ];
            };
          };
        };
      };
    };
  };

  boot.initrd.availableKernelModules = [ "virtio_blk" "virtio_pci" "ext4" "dm_mod" "dm_snapshot" ];

  boot.kernelModules = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64)
    cfg.kernelModules;

  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.loader.timeout = 2;
}
