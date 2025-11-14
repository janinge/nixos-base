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

    # Configure PipeWire PulseAudio for system-wide mode
    extraConfig.pipewire-pulse."99-system-wide" = {
      "context.properties" = {
        # Disable PID file creation
        "pulse.properties" = {
          "server.daemonize" = false;
          "server.pid-file" = null;
        };
      };
      "pulse.properties" = {
        # Don't try to acquire org.pulseaudio.Server on D-Bus
        "server.dbus-name" = null;
      };
    };
  };

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

  systemd.services.pipewire = {
    environment = {
      # Disable D-Bus session dependencies for system-wide mode
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
    };
  };

  systemd.services.pipewire-pulse = {
    environment = {
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
    };
    serviceConfig = {
      # Fix PID file location for system service
      RuntimeDirectory = "pipewire";
      RuntimeDirectoryMode = "0755";
    };
  };

  systemd.services.wireplumber = {
    environment = {
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
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
      server = "127.0.0.1"
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
  ];

  systemd.services.owntone = {
    description = "OwnTone media server (forked-daapd)";
    after = [ "network.target" "sound.target" "pipewire.service" ];
    wants = [ "avahi-daemon.service" ];
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
