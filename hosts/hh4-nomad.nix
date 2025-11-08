{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/power.nix
    ../modules/headscale.nix
    ../modules/nomad-server.nix
    ../modules/fruit-server.nix
  ];

  networking.hostName = hostName;

  services.nomad.settings.datacenter = cfg.datacenter;
  services.consul.extraConfig.datacenter = cfg.datacenter;

  services.tailscale.extraUpFlags = [ "--advertise-routes=${cfg.routedSubnet}" ];
}
