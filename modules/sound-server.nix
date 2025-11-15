{ config, pkgs, lib, ... }:

{
  security.rtkit.enable = true;

  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    jack.enable = true;

    systemWide = true;

    extraConfig.pipewire-pulse."99-custom-pulse" = {
      "context.properties" = {
        "pulse.min.req" = 0;
        "pulse.default.req" = 0;
      };

      "pulse.properties" = {
        "pulse.runtime-dir" = "/run/pipewire";
      };

      "context.modules" = [
        {
          name = "libpipewire-module-protocol-pulse";
          args = {
            "pulse.min.req" = "256/48000";
            "pulse.default.req" = "960/48000";
            "pulse.min.quantum" = "256/48000";
            "pulse.max.quantum" = "8192/48000";
            # Listen on both Unix socket and TCP
            "server.address" = [
              "unix:native"
              "tcp:4713"
            ];
          };
        }
      ];
    };
  };

  # Disable default NixOS module configuration to avoid a conflict
  services.pipewire.extraConfig.pipewire-pulse."10-native-protocol" = null;

  systemd.user.services.pipewire.enable = false;
  systemd.user.services.pipewire-pulse.enable = false;
  systemd.user.services.wireplumber.enable = false;

  systemd.services.pipewire-pulse.serviceConfig = {
    Environment = [ "XDG_RUNTIME_DIR=/run/pipewire" ];
    RuntimeDirectory = "pipewire/pulse";
    RuntimeDirectoryMode = "0755";
  };

  systemd.services.pipewire.serviceConfig.Environment =
    [ "XDG_RUNTIME_DIR=/run/pipewire" ];

  systemd.services.wireplumber.serviceConfig.Environment =
    [ "XDG_RUNTIME_DIR=/run/pipewire" ];

  systemd.services.nqptp = {
    description = "Not Quite PTP";
    documentation = [ "man:nqptp(8)" ];
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.nqptp}/bin/nqptp";
      User = "nqptp";
      Group = "nqptp";

      # Capabilities required for network timing
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

      Restart = "on-failure";
      RestartSec = "5s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;

      RuntimeDirectory = "nqptp";
      RuntimeDirectoryMode = "0755";
    };
  };

  users.users.nqptp = {
    isSystemUser = true;
    group = "nqptp";
    description = "nqptp service user";
  };

  users.groups.nqptp = {};

  services.shairport-sync = {
    enable = true;
    package = pkgs.shairport-sync-airplay2;

    settings = {
      general = {
        name = "Hiss";
      };

      sessioncontrol = {
        volume_range_db = 30;
      };

      audio_backend = {
        backend = "pipewire";
      };
    };
  };

  # Shairport-sync starts after PipeWire and nqptp are ready
  systemd.services.shairport-sync = {
    after = [ "pipewire.service" "pipewire-pulse.service" "nqptp.service" ];
    wants = [ "pipewire-pulse.service" "nqptp.service" ];
    requires = [ "nqptp.service" ];
    serviceConfig = {
      SupplementaryGroups = [ "audio" "pipewire" ];
      RestartSec = "5s";
    };
  };

  users.users.owntone = {
    isSystemUser = true;
    group = "owntone";
    extraGroups = [ "audio" "pipewire" ];
    description = "OwnTone service user";
  };

  users.groups.owntone = {};

  environment.etc."owntone.conf".text = ''
    general {
      uid = "owntone"
      db_path = "/var/lib/owntone/cache.db"
      logfile = "/var/log/owntone.log"
      loglevel = "log"
    }

    library {
      name = "Hiss"
      directories = { "/srv/music" }
      follow_symlinks = true
    }

    audio {
      nickname = "Computer"
      type = "pulseaudio"
    }

    # DAAP/iTunes library sharing
    library {
      port = 3689
      name = "Hiss"
    }

    mpd {
      port = 6600
      clear_queue_on_stop_disable = false
    }
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/owntone 0750 owntone owntone -"
    "d /var/cache/owntone 0750 owntone owntone -"
    "d /var/log 0755 root root -"
    "f /var/log/owntone.log 0640 owntone owntone -"
    "d /run/pipewire 0755 root pipewire -"
    "d /run/pipewire/pulse 0755 pipewire pipewire -"
  ];

  systemd.services.owntone = {
    description = "OwnTone media server (forked-daapd)";
    after = [ "network.target" "sound.target" "pipewire.service" "pipewire-pulse.service" ];
    wants = [ "avahi-daemon.service" "pipewire-pulse.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.owntone}/bin/owntone -f -c /etc/owntone.conf";
      User = "owntone";
      Group = "owntone";
      SupplementaryGroups = [ "audio" "pipewire" ];

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/owntone" "/var/cache/owntone" "/var/log" ];

      BindReadOnlyPaths = [ "/srv/music" ];

      RuntimeDirectory = "owntone";
      RuntimeDirectoryMode = "0755";

      Restart = "on-failure";
      RestartSec = "10s";
    };

    environment = {
      # Ensure PipeWire socket is accessible
      PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
    };
  };

  environment.systemPackages = with pkgs; [
    jack2
    qjackctl
    zita-njbridge
    alsa-utils
    owntone
    nqptp
  ];
}
