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
  # Keep the provider's eth0 name in both the initrd and the running system.
  networking.usePredictableInterfaceNames = false;
  networking.nameservers = [ "127.0.0.1" ];
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  networking.defaultGateway = "136.148.219.1";
  networking.defaultGateway6 = {
    address = "2a13:7c82:126::1";
    interface = cfg.publicIf;
  };

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = false;
    ipv4.addresses = [
      { address = "136.148.219.92"; prefixLength = 24; }
    ];
    ipv6.addresses = [
      { address = "2a13:7c82:126:2b::"; prefixLength = 56; }
    ];
  };

  networking.bridges.${cfg.serviceBridge}.interfaces = [];
  networking.interfaces.${cfg.serviceBridge}.ipv4.addresses = [
    { address = cfg.serviceIp; prefixLength = 24; }
  ];

  # About 2 GiB logical swap on this 4 GiB VM, allocated in RAM on demand.
  # Prefer compressed RAM over the encrypted disk swap retained as a fallback.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

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
