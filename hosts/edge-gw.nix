{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/power.nix
    ../modules/headscale.nix
    ../modules/coredns.nix
    ../modules/nomad-server.nix
    ../modules/seaweedfs.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;

  networking.interfaces.${cfg.publicIf}.useDHCP = true;

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

  services.seaweedfs = {
    enable = true;
    master = {
      enable = true;
      port = 9333;
      volumeSizeLimitMB = 30000;
    };
    volume = {
      enable = true;
      port = 8080;
      dataDir = "/var/lib/seaweedfs/volumes";
      maxVolumes = 100;
    };
    filer = {
      enable = true;
      port = 8888;
    };
  };

  services.traefik.dynamicConfigOptions.http.routers.seaweedfs = {
    entryPoints = [ "tailnet" ];
    service = "seaweedfs";
    rule = "Host(`seaweedfs.h00t.works`)";
    tls = { certResolver = "letsencrypt"; };
  };

  services.traefik.dynamicConfigOptions.http.services.seaweedfs = {
    loadBalancer = {
      servers = [
        { url = "http://${cfg.serviceIp}:9333"; }
      ];
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