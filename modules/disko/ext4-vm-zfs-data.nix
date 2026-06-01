{ config, lib, pkgs, modulesPath, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
  rootDevice = cfg.rootDevice or "/dev/vda";
  dataDevice = cfg.dataDevice or "/dev/vdb";
  arcMax = 256 * 1024 * 1024;

  initrdUnlockShell = pkgs.writeShellScriptBin "initrd-zfs-unlock-shell" ''
    echo "Waiting for ZFS passphrase prompts."
    echo "Enter the requested passphrase below; this shell exits when unlock is complete."
    exec ${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent --watch
  '';
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  disko.devices = {
    disk = {
      main = {
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

      data = {
        type = "disk";
        device = dataDevice;
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "dpool";
              };
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
            size = "4G";
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

    zpool = {
      dpool = {
        type = "zpool";
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
          encryption = "on";
          keyformat = "passphrase";
          keylocation = "prompt";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };

        datasets = {
          "nix" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/nix";
          };

          "garage" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var/lib/garage";
          };
        };
      };
    };
  };

  fileSystems."/nix" = {
    device = "dpool/nix";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/var/lib/garage" = {
    device = "dpool/garage";
    fsType = "zfs";
    options = [ "nofail" ];
  };

  boot.initrd = {
    availableKernelModules = [
      "virtio_blk"
      "virtio_pci"
      "virtio_net"
      "ext4"
      "dm_mod"
      "dm_snapshot"
    ];

    network.ssh = {
      enable = true;
      port = 36023;
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
      authorizedKeys = config.users.users.janinge.openssh.authorizedKeys.keys;
    };

    systemd = {
      enable = true;
      storePaths = [ initrdUnlockShell ];
      users.root.shell = "${initrdUnlockShell}/bin/initrd-zfs-unlock-shell";

      network = {
        enable = true;
        networks."10-${cfg.publicIf}" = {
          matchConfig.Name = cfg.publicIf;
          networkConfig.DHCP = "ipv4";
        };
      };
    };
  };

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs = {
    devNodes = "/dev/disk/by-partuuid/";
    requestEncryptionCredentials = [ "dpool" ];
  };

  boot.kernelModules = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64) [ "kvm-intel" ];

  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zfs_arc_max=${toString arcMax}"
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  boot.kernel.sysctl = {
    "module.zfs.parameters.zfs_arc_max" = toString arcMax;
    "module.zfs.parameters.zfs_prefetch_disable" = "1";
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.loader.timeout = 2;

  nix.settings = {
    max-jobs = 1;
    cores = 1;
  };

  services.zfs = {
    autoSnapshot.enable = true;
    autoScrub.enable = true;
  };
}
