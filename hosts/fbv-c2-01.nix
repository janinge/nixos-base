{ lib, nodes, hostName, sharedVolumes, pkgs, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/nomad.nix
  ];

  # Override the devices list directly; disko adds /dev/sda via the EF02 partition
  # and device = "nodev" doesn't clear it — only forcing the list does.
  boot.loader.grub.devices = lib.mkForce [ "nodev" ];

  # Hypervisor specific tuning
  boot.kernelParams = [
    "clocksource=acpi_pm" # Bhyve often struggles with TSC sync; acpi_pm is more stable than HPET
    "clearcpuid=514"      # Helps with some Ryzen-specific sleep state issues in VMs
  ];

  # Ensure we don't try to load intel-specific modules
  boot.blacklistedKernelModules = [ "kvm_intel" ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;

  networking.defaultGateway = "192.168.11.1";

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = true;
    ipv4.addresses = [
      { address = "192.168.11.8"; prefixLength = 24; }
    ];
  };

  networking.bridges.${cfg.serviceBridge}.interfaces = [];
  networking.interfaces.${cfg.serviceBridge}.ipv4.addresses = [
    { address = cfg.serviceIp; prefixLength = 24; }
  ];

  boot.kernel.sysctl = {
    "net.ipv6.conf.default.accept_ra" = 1;
    "net.ipv6.conf.all.accept_ra" = 1;
    "net.ipv6.conf.all.accept_ra_rt_info_max_plen" = 64;
  };

  services.resolved.enable = true;
  services.resolved.settings.Resolve.FallbackDNS = [ "10.42.1.1" "45.90.28.186" "45.90.30.186" ];

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--accept-routes"
      "--advertise-exit-node"
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes // {
      # Node-specific volumes here, if any
    };
    jobSecrets = [ "authentik.env" ];
  };

  services.juicefsMounts.external-juicefs = {
    enable = true;
    fsName = "external-juicefs";
    mountPoint = "/mnt/juicefs/external";
    cacheDir = "/var/cache/juicefs/external";
    cacheSizeMiB = 10240;
    postgresPasswordSecret = "juicefs_external_postgres_password";
    s3EnvSecret = "juicefs_external_s3.env";

    metadata = {
      host = "primary.postgres-cluster.service.consul";
      port = 5432;
      database = "juicefs_external";
      username = "juicefs_external";
      sslmode = "disable";
    };

    nomad = {
      hostVolumes = {
        external-juicefs-p2p = {
          subPath = "p2p";
        };
        external-juicefs-music = {
          subPath = "music";
        };
      };
    };
  };

  nix.settings.trusted-users = [ "root" "janinge" ];
}
