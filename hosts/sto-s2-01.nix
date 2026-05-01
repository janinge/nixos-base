{ nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
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
      "--accept-routes"
      "--advertise-exit-node"
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };

  services.seaweedfs = {
    volume = {
      enable = true;
      dataDir = "/var/lib/seaweedfs/volumes";
      maxVolumes = 100;
      rack = "zfs1";
    };
  };

  systemd.services.seaweedfs-volume = {
    requires = [ "var-lib-seaweedfs-volumes.mount" ];
    after = [ "var-lib-seaweedfs-volumes.mount" ];
    unitConfig.RequiresMountsFor = "/var/lib/seaweedfs/volumes";
  };

  networking = {
    nat = {
      enable = true;
      externalInterface = cfg.publicIf;
      internalInterfaces = [ "tailscale0" ];
    };
  };
}
