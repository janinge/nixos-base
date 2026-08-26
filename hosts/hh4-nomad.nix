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

  # Keep mDNS on the physical LAN. In particular, do not let Avahi browse or
  # publish on Nomad's bridge and its dynamically-created workload interfaces.
  services.avahi = {
    allowInterfaces = [ cfg.publicIf ];
    ipv4 = true;
    reflector = false;
  };

  # Contain the failure mode where avahi-daemon spins indefinitely, and make
  # service recovery reliable if it exits or leaves a stale runtime PID file.
  systemd.services.avahi-daemon = {
    preStart = ''
      rm -f /run/avahi-daemon/pid
    '';

    serviceConfig = {
      Restart = "always";
      RestartSec = "2s";
      TimeoutStopSec = "5s";
      SendSIGKILL = true;
      FinalKillSignal = "SIGKILL";
      CPUQuota = "50%";
      LimitCORE = "infinity";
    };
  };

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
    jobSecrets = [
      "authentik.env"
      "bulwark.env"
      "stalwart_fallback_admin_secret"
      "stalwart_pg_password"
      "stalwart_s3_access_key"
      "stalwart_s3_secret_key"
    ];
  };

}
