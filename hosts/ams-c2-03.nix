{ nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/tailscale.nix
    ../modules/coredns.nix
    ../modules/nomad.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;
  networking.nameservers = [ "127.0.0.1" ];
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  # OpenStack supplies the public address, gateway and metadata routes by DHCP.
  # The encrypted VM layout also uses DHCP in the initrd for SSH unlocking.
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

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes;
    jobSecrets = [ "directus.env" ];
    jobSecretsFile = ../secrets/kata.yaml;
  };

  networking.nat = {
    enable = true;
    externalInterface = cfg.publicIf;
    internalInterfaces = [ "tailscale0" ];
  };
}
