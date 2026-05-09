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
    ../modules/seaweedfs.nix
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
    runtime = "kata-docker";
    hostVolumes = sharedVolumes;
    jobSecrets = [ "gitea.env" ];
  };

  cluster.nomadKata.enable = true;

  sops.secrets."gitea.env".sopsFile = ../secrets/kata.yaml;

  services.seaweedfs = {
    filer = {
      enable = true;
      postgres = {
        database = "seaweedfs_filer";
        username = "seaweedfs";
      };
    };

    mount = {
      mountPoint = "/mnt/seaweedfs";
      cacheSizeMB = 4000;
      allowOthers = true;
    };
  };

  nix.settings.trusted-users = [ "janinge" ];
}
