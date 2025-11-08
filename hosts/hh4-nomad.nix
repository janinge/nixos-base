{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/power.nix
    ../modules/nomad-client.nix
    ../modules/fruit-server.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;

  services.nomad.settings.datacenter = cfg.datacenter;
  services.consul.extraConfig.datacenter = cfg.datacenter;

  services.tailscale.extraUpFlags = [ "--advertise-routes=${cfg.routedSubnet}" ];
}
