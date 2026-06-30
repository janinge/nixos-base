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

  services.juicefsMounts.external-juicefs = {
    enable = true;
    fsName = "external-juicefs";
    mountPoint = "/mnt/juicefs/external";
    cacheDir = "/var/cache/juicefs/external";
    cacheSizeMiB = 10240;
    postgresPasswordSecret = "juicefs_external_postgres_password";
    s3EnvSecret = "juicefs_external_s3.env";

    metadata = {
      host = "primary.postgres-cluster.service.consul";
      port = 5432;
      database = "juicefs_external";
      username = "juicefs_external";
      sslmode = "disable";
    };

    nomad = {
      hostVolumes = {
        external-juicefs-p2p = {
          subPath = "p2p";
        };
        external-juicefs-music = {
          subPath = "music";
        };
      };
    };
  };

}
