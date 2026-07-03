{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/nomad.nix
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
      "--accept-routes"
      "--advertise-exit-node"
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };

  networking = {
    nat = {
      enable = true;
      externalInterface = cfg.publicIf;
      internalInterfaces = [ "tailscale0" ];
    };
  };

  # Overflow (hot-spare) Nomad client: tier=overflow is derived from
  # cluster/nodes.nix, so jobs only spill here as a last resort. Rootless
  # Podman runtime (default). Note this node is aarch64 — amd64-only images
  # are simply infeasible here and skipped. No host volumes attached.
  cluster.nomad.client.enable = true;
}
