{ config, lib, pkgs, ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";

        content = {
          type = "gpt";
          partitions = {
            GRUB = {
              size = "1M";
              type = "EF02";
            };

            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                extraArgs = [ "-n" "ESP" ];
              };
            };

            zfs = {
              end = "-16G";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };

            encryptedSwap = {
              size = "100%";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";

        # mode = "" -> single-disk pool
        mode = "";

        options = {
          ashift = "12";
          autotrim = "on";
        };

        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          compression = "on";
          devices = "off";
          dnodesize = "auto";
          #encryption = "on";
          #keyformat = "passphrase";
          #keylocation = "prompt";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };

        datasets = {
          "nixos" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };

          "nixos/nix" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/nix";
          };

          "nixos/root" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/";
          };

          "nixos/var" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };

          "nixos/var/lib" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var/lib";
          };

          "nixos/var/lib/containers" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };

          "nixos/var/lib/containers/storage" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };

          "nixos/var/lib/containers/storage/volumes" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var/lib/containers/storage/volumes";
          };

          "data" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };

          "data/home" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/home";
          };

          "reserved" = {
            type = "zfs_fs";
            options.mountpoint = "none";
            options.refreservation = "10G";
          };
        };
      };
    };
  };


  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "rpool/nixos/root";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "rpool/nixos/nix";
    fsType = "zfs";
  };

  fileSystems."/var/lib" = {
    device = "rpool/nixos/var/lib";
    fsType = "zfs";
  };

  fileSystems."/var/lib/containers/storage/volumes" = {
    device = "rpool/nixos/var/lib/containers/storage/volumes";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "rpool/data/home";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/ESP";
    fsType  = "vfat";
  };


  boot.supportedFilesystems = [ "zfs" ];

  boot.zfs.devNodes = "/dev/disk/by-id/";

  boot.kernelParams = [
    "zfs_arc_max=4294967296"
  ];

  services.zfs = {
    autoSnapshot.enable = true;
    autoScrub.enable = true;
  };
}