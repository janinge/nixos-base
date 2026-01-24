{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/headscale.nix
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

  cluster.nomad.server.enable = true;
  cluster.patroni.enable = true;

  services.seaweedfs = {
    master.enable = true;
    filer.enable = true;
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