{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/headscale.nix
    ../modules/nomad.nix
    ../modules/seaweedfs.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  
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

  services.seaweedfs = {
    master.enable = true;
    volume.enable = true;
  };

  networking = {
    nat = {
      enable = true;
      externalInterface = cfg.publicIf;
      internalInterfaces = [ "tailscale0" ];
    };
  };
}