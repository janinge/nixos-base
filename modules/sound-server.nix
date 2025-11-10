{ config, pkgs, lib, ... }:

{
  security.rtkit.enable = true;

  hardware.pulseaudio.enable = false;

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
    package = pkgs.shairport-sync-full; # includes AirPlay 2, PipeWire, etc., on recent Nixpkgs

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

  services.owntone = {
    enable = true;

    config = {
      "websocket" = {
        "enabled" = true;
      };

      "library" = {
        "name" = "Hiss";
      };

      "output" = {
        "pa" = {
          "enabled" = true;
        };
      };

      "raop" = {
        "enabled" = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    jack2
    qjackctl
    zita-njbridge
    alsa-utils
  ];
}