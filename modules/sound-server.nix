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
  };

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
  ];
}
