{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/power.nix
    ../modules/nomad-client.nix
    ../modules/fruit-server.nix
    ../modules/sound-server.nix
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

  services.resolved.enable = true;
  services.resolved.fallbackDns = [ "45.90.28.186" "45.90.30.186" ];

  services.nomad.settings.datacenter = cfg.datacenter;
  services.consul.extraConfig.datacenter = cfg.datacenter;

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };
}
