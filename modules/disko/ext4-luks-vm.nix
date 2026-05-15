{ config, lib, pkgs, modulesPath, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
  rootDevice = cfg.rootDevice or "/dev/vda";

  # Static network config for initrd — derived from the host's networking settings
  # so the SSH unlock port is reachable without a DHCP server.
  initrdAddresses = lib.attrByPath
    [ "networking" "interfaces" cfg.publicIf "ipv4" "addresses" ] [] config;
  defaultGateway = config.networking.defaultGateway or null;
  initrdGateway =
    if lib.isString defaultGateway then defaultGateway
    else if defaultGateway == null then null
    else defaultGateway.address or null;

  initrdUnlockShell = pkgs.writeShellScriptBin "initrd-luks-unlock-shell" ''
    echo "Waiting for LUKS passphrase prompt."
    echo "Enter the passphrase below; this shell exits when unlock is complete."
    exec ${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent --watch
  '';
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
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
    };

    lvm_vg.pool = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "2G";
          content.type = "swap";
        };

        root = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "defaults" "noatime" "discard" "commit=60" ];
          };
        };
      };
    };
  };

  boot.initrd = {
    availableKernelModules = [
      "virtio_blk" "virtio_pci" "virtio_net" "virtio_scsi"
      "ext4" "dm_mod" "dm_crypt" "dm_snapshot"
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
      users.root.shell = "${initrdUnlockShell}/bin/initrd-luks-unlock-shell";

      network = {
        enable = true;
        networks."10-${cfg.publicIf}" = {
          matchConfig.Name = cfg.publicIf;
          networkConfig.DHCP = if initrdAddresses == [] then "ipv4" else "no";
          address = map (a: "${a.address}/${toString a.prefixLength}") initrdAddresses;
          routes = lib.optional (initrdGateway != null)
            { Gateway = initrdGateway; };
        };
      };
    };
  };

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
