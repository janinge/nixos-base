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

    extraConfig.pipewire-pulse."10-systemwide" = {
      "pulse.properties" = {
        "pulse.runtime-dir" = "/run/pipewire";
      };

      "pulse.rules" = [
        {
          matches = [ { "pulse.module.name" = "module-native-protocol-tcp"; } ];
          actions = {
            update-props = {
              "pulse.tcp.listen" = "127.0.0.1";
              "pulse.tcp.port" = 4713;
            };
          };
        }
      ];
    };
  };

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

  # Librespot for Spotify Connect
  users.users.librespot = {
    isSystemUser = true;
    group = "librespot";
    extraGroups = [ "audio" "pipewire" ];
    description = "Librespot Spotify Connect service user";
  };

  users.groups.librespot = {};

  systemd.services.librespot = {
    description = "Librespot Spotify Connect receiver";
    documentation = [ "https://github.com/librespot-org/librespot" ];
    after = [ "network.target" "sound.target" "pipewire.service" "pipewire-pulse.service" ];
    wants = [ "avahi-daemon.service" "pipewire-pulse.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.librespot.override { withPulseAudio = true; }}/bin/librespot \
          --name "Hiss" \
          --backend pulseaudio \
          --device-type speaker \
          --bitrate 320 \
          --cache /var/cache/librespot
      '';

      User = "librespot";
      Group = "librespot";
      SupplementaryGroups = [ "audio" "pipewire" ];

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;

      # Cache directory access
      CacheDirectory = "librespot";
      CacheDirectoryMode = "0750";

      Restart = "on-failure";
      RestartSec = "10s";
    };

    environment = {
      PULSE_SERVER = "/run/pipewire/pulse/native";
      PULSE_RUNTIME_PATH = "/run/pipewire/pulse";
    };
  };

  # OwnTone media server
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
    "d /var/cache/librespot 0750 librespot librespot -"
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
    zita-njbridge
    alsa-utils
    owntone
    nqptp
    (librespot.override {
      withPulseAudio = true;
      withDNS-SD = true;
      withMDNS = false;
      withAvahi = false;
    })
  ];
}
