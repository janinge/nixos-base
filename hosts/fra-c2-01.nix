{ nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/tailscale.nix
    ../modules/coredns.nix
    ../modules/nomad.nix
    ../modules/seaweedfs.nix
    ../modules/patroni.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;
  networking.nameservers = [ "127.0.0.1" ];
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  networking.defaultGateway = "37.114.41.1";
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = cfg.publicIf;
  };

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = false;
    ipv4.addresses = [
      { address = "37.114.41.108"; prefixLength = 24; }
    ];
    ipv6.addresses = [
      { address = "2a0e:97c0:3ea:201::1"; prefixLength = 64; }
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
      "--accept-dns=false"
      "--advertise-exit-node"
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };

  cluster.nomad.server.enable = true;

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes;
  };

  cluster.patroni = {
    enable = true;
    extraClientCidrs = [ "192.168.0.0/16" ];
  };

  services.seaweedfs = {
    master.enable = true;
    filer = {
      enable = true;
      postgres = {
        database = "seaweedfs_filer";
        username = "seaweedfs";
      };
    };
  };

  networking.nat = {
    enable = true;
    externalInterface = cfg.publicIf;
    internalInterfaces = [ "tailscale0" ];
  };
}
