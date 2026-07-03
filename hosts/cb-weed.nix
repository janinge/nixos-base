{ nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/nomad.nix
    ../modules/coredns.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;
  networking.nameservers = [ "127.0.0.1" ];
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  networking.defaultGateway = "185.218.124.1";
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = cfg.publicIf;
  };

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = false;
    ipv4.addresses = [
      { address = "185.218.124.67"; prefixLength = 23; }
    ];
    ipv6.addresses = [
      { address = "2a02:c207:2293:7431::1"; prefixLength = 64; }
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
    hostVolumes = sharedVolumes // {
      # Node-specific volumes here, if any
    };
    jobSecrets = [
      "authentik.env"
      "bulwark.env"
      "stalwart_fallback_admin_secret"
      "stalwart_pg_password"
      "stalwart_s3_access_key"
      "stalwart_s3_secret_key"
    ];
  };

  networking = {
    nat = {
      enable = true;
      externalInterface = cfg.publicIf;
      internalInterfaces = [ "tailscale0" ];
    };
  };
}
