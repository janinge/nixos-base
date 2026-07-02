{ ... }:
let
  macShareSettings = {
    "fruit:zero_file_id" = "yes";
    "vfs objects" = "catia fruit streams_xattr";
  };

  mediaWriterSettings = {
    "force user" = "rebe";
    "force group" = "media";
    "create mask" = "0664";
    "directory mask" = "0775";
  };
in
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
        "fruit:aapl" = "yes";
        "fruit:copyfile" = "yes";
        "fruit:nfs_aces" = "no";
      };
      "Music" = macShareSettings // {
        "path" = "/srv/music";
        "valid users" = "@media";
        "public" = "no";
        "writeable" = "yes";
        "force user" = "rebe";
        "fruit:time machine" = "yes";
      };
      "Juice" = macShareSettings // mediaWriterSettings // {
        "path" = "/mnt/juicefs/external/music";
        "comment" = "JuiceFS external music";
        "guest ok" = "yes";
        "public" = "yes";
        "browseable" = "yes";
        "read only" = "yes";
        "write list" = "@media";
        "strict locking" = "no";
        "vfs objects" = "catia fruit streams_xattr readahead";
        "readahead:offset" = "1M";
        "readahead:length" = "4M";
      };
    };
  };

  systemd.services.samba-smbd = {
    after = [ "juicefs-external-juicefs.service" ];
    wants = [ "juicefs-external-juicefs.service" ];
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
