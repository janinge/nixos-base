{ config, pkgs, ... }:
{
  services.timesyncd.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      userServices = true;
      addresses = true;
      workstation = true;
    };
  };

  services.samba = {
    enable = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "hiss";
        "netbios name" = "hiss";
        "security" = "user";
        "use sendfile" = "yes";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      "music" = {
        "path" = "/srv/music";
        "valid users" = "@media";
        "public" = "no";
        "writeable" = "yes";
        "force user" = "rebe";
        "fruit:aapl" = "yes";
        "fruit:time machine" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  systemd.tmpfiles.rules = [
    "d /srv/timemachine 0770 tm tm -"
    "d /srv/music 0770 media media -"
  ];

}