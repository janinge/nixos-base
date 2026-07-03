{ nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/tailscale.nix
    ../modules/coredns.nix
    ../modules/nomad.nix
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
      "--accept-dns=false"
      "--accept-routes"
      "--advertise-exit-node"
      "--advertise-routes=${cfg.routedSubnet}"
    ];
  };

  networking.nat = {
    enable = true;
    externalInterface = cfg.publicIf;
    internalInterfaces = [ "tailscale0" ];
  };

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes;
    jobSecrets = [
      "bulwark.env"
      "stalwart_fallback_admin_secret"
      "stalwart_pg_password"
      "stalwart_s3_access_key"
      "stalwart_s3_secret_key"
    ];
  };

  cluster.nomad.server.enable = true;

  cluster.patroni = {
    enable = true;
    extraClientCidrs = [ "192.168.0.0/16" ];
    postgis.enable = true;
  };

}
