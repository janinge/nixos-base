{ config, lib, nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/nomad.nix
    ../modules/seaweedfs.nix
    ../modules/coredns.nix
    ../modules/patroni.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;

  networking.defaultGateway = "185.218.124.1";
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = cfg.publicIf;
  };

  networking.nameservers = [ "213.136.95.10" "213.136.95.11" "2a02:c207::1:53" ];

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = false;
    ipv4.addresses = [
      { address = "185.218.124.67"; prefixLength = 23; }
    ];
    ipv6.addresses = [
      { address = "2a02:c207:2293:7431::1"; prefixLength = 64; }
    ];
  };

  networking.bridges.${cfg.serviceBridge}.interfaces = [];
  networking.interfaces.${cfg.serviceBridge}.ipv4.addresses = [
    { address = cfg.serviceIp; prefixLength = 24; }
  ];

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };

  cluster.nomad.server.enable = true;

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes // {
      # Node-specific volumes here, if any
    };
    jobSecrets = [ "authentik.env" ];
  };

  cluster.patroni.enable = true;

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
      rack = "qemu1";
      maxVolumes = 20;
    };

    mount = {
      mountPoint = "/mnt/seaweedfs";
      cacheSizeMB = 2000;
      allowOthers = true;
    };
  };

  networking = {
    nat = {
      enable = true;
      externalInterface = cfg.publicIf;
      internalInterfaces = [ "tailscale0" ];
    };
  };
}
