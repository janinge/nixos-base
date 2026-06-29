{ nodes, hostName, sharedVolumes, ... }:
let
  cfg = nodes.${hostName};
in {
  imports = [
    ../modules/common.nix
    ../modules/power.nix
    ../modules/coredns.nix
    ../modules/nomad.nix
    ../modules/fruit-server.nix
    ../modules/sound-server.nix
  ];

  networking.hostName = hostName;
  networking.hostId = cfg.hostId;
  networking.useDHCP = false;
  networking.nameservers = [ "127.0.0.1" ];
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  networking.defaultGateway = "192.168.2.1";

  networking.interfaces.${cfg.publicIf} = {
    useDHCP = true;
    ipv4.addresses = [
      { address = "192.168.2.8"; prefixLength = 24; }
    ];
  };

  networking.bridges.${cfg.serviceBridge}.interfaces = [];
  networking.interfaces.${cfg.serviceBridge}.ipv4.addresses = [
    { address = cfg.serviceIp; prefixLength = 24; }
  ];

  boot.kernel.sysctl = {
    "net.ipv6.conf.default.accept_ra" = 1;
    "net.ipv6.conf.all.accept_ra" = 1;
    "net.ipv6.conf.all.accept_ra_rt_info_max_plen" = 64;
  };

  cluster.nomad.server.enable = true;

  cluster.nomad.client = {
    enable = true;
    hostVolumes = sharedVolumes // {
      # Node-specific volumes here, if any
    };
    jobSecrets = [ "authentik.env" ];
  };

  # Shared POSIX filesystem (data on Garage, metadata on Patroni). Requires the
  # one-time `juicefs format` bootstrap and the juicefs_meta_password sops secret.
  cluster.juicefs.enable = true;

}
