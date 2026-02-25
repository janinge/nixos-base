{ config, lib, nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/power.nix
    ../modules/nomad.nix
    ../modules/fruit-server.nix
    ../modules/sound-server.nix
    ../modules/seaweedfs.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;

  networking.defaultGateway = "192.168.2.1";

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = true;
    ipv4.addresses = [
      { address = "192.168.2.8"; prefixLength = 24; }
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
  services.resolved.fallbackDns = [ "10.42.1.1" "45.90.28.186" "45.90.30.186" ];

  cluster.nomad.server.enable = true;

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes // {
      # Node-specific volumes here, if any
    };
    jobSecrets = [ "authentik.env" ];
  };

  services.seaweedfs = {
    master.enable = true;
    filer = {
      enable = true;
      store = "postgres2";
      postgres = {
        hostname = "postgres-cluster.service.consul";
        database = "seaweedfs_filer";
        username = "seaweedfs";
        passwordFile = config.sops.secrets.seaweedfs_postgres_password.path;
      };
    };

    volume = {
      enable = true;
      dataDir = "/var/lib/seaweedfs/volumes";
      rack = "nvme1";
      maxVolumes = 40;
    };

    mount = {
      mountPoint = "/mnt/seaweedfs";
      cacheSizeMB = 2000;
      allowOthers = true;
    };
  };
}
