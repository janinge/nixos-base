{ config, lib, pkgs, modulesPath, nodes, hostName, ... }:
let
  rootDevice = nodes.${hostName}.rootDevice or "/dev/nvme0n1";
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
            size = "1G";
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

  boot.initrd.availableKernelModules = [ 
    "virtio_blk" "virtio_pci" "nvme" "ena" "ext4" "dm_mod" "dm_snapshot" 
  ];

  boot.kernelModules = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64) [ "kvm-intel" ];

  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "console=ttyS0" # EC2 System Log
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  boot.loader.timeout = 2;
}
