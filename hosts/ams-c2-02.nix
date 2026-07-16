{ nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/tailscale.nix
    ../modules/coredns.nix
    ../modules/nomad.nix
    ../modules/nomad-kata.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;
  networking.nameservers = [ "127.0.0.1" ];
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  boot.kernelParams = [ "net.ifnames=0" "biosdevname=0" ];

  networking.defaultGateway = "188.166.0.1";
  networking.defaultGateway6 = {
    address = "2a03:b0c0:2:f0::1";
    interface = cfg.publicIf;
  };

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = false;
    ipv4.addresses = [
      { address = "188.166.5.52"; prefixLength = 20; }
    ];
    ipv6.addresses = [
      { address = "2a03:b0c0:2:f0:0:1:b1e8:2001"; prefixLength = 64; }
    ];
  };

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
    runtime = "kata-docker";
    hostVolumes = sharedVolumes;
    jobSecrets = [ "gitea.env" "directus.env" "smf-dev.env" ];
    jobSecretsFile = ../secrets/kata.yaml;
  };

  cluster.nomadKata.enable = true;

  networking.nat = {
    enable = true;
    externalInterface = cfg.publicIf;
    internalInterfaces = [ "tailscale0" ];
  };
}
