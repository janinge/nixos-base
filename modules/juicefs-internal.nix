{ config, lib, pkgs, ... }:

let
  cfg = config.cluster.juicefs;

  # Metadata password is supplied out-of-band via META_PASSWORD (rendered from
  # sops) rather than embedded in the connection string. This keeps the secret
  # out of the process table / unit file and dodges URL-escaping pitfalls in the
  # PostgreSQL metaurl.
  metaEnv = config.sops.templates."juicefs.env".path;

  mountArgs = [
    "mount"
    cfg.metaUrl
    cfg.mountPoint
    "--cache-dir" cfg.cacheDir
    "--cache-size" (toString cfg.cacheSize)
  ]
  ++ lib.optionals cfg.allowOther [ "-o" "allow_other" ]
  ++ cfg.extraMountOptions;

  # Order after the local service-discovery stack so the .consul names used in
  # the metaurl (Patroni primary) and object store (Garage S3) resolve before we
  # try to mount.
  dnsDeps =
    lib.optional config.services.tailscale.enable "tailscale-online.service"
    ++ lib.optional config.services.consul.enable "consul.service"
    ++ lib.optional config.services.coredns.enable "coredns.service";
in
{
  options.cluster.juicefs = {
    enable = lib.mkEnableOption "JuiceFS POSIX mount of the shared cluster filesystem";

    name = lib.mkOption {
      type = lib.types.str;
      default = "juicefs-default";
      description = "Name of the JuiceFS filesystem (must match the one created with `juicefs format`).";
    };

    mountPoint = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/juicefs";
      description = "Host path where the JuiceFS filesystem is mounted.";
    };

    metaUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgres://juicefs@primary.postgres-cluster.service.consul:5432/juicefs?sslmode=disable";
      description = ''
        JuiceFS metadata engine URL (the Patroni primary). The password is NOT
        included here; it is provided via META_PASSWORD from sops. Object-store
        configuration (Garage bucket + S3 keys) is stored in the metadata engine
        at `juicefs format` time and is not needed for mounting.
      '';
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/juicefs";
      description = "Local directory used for the JuiceFS data block cache.";
    };

    cacheSize = lib.mkOption {
      type = lib.types.int;
      default = 10240;
      description = "Maximum local cache size in MiB.";
    };

    allowOther = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mount with the FUSE `allow_other` option so non-root processes can access the mount.";
    };

    extraMountOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--writeback" ];
      example = [ "--writeback" "--max-uploads=20" ];
      description = "Additional arguments passed verbatim to `juicefs mount`.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.juicefs;
      defaultText = lib.literalExpression "pkgs.juicefs";
      description = "JuiceFS package providing the `juicefs` CLI.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.metaUrl != "";
        message = "cluster.juicefs.metaUrl must not be empty.";
      }
    ];

    boot.kernelModules = [ "fuse" ];
    programs.fuse.userAllowOther = lib.mkIf cfg.allowOther true;

    environment.systemPackages = [ cfg.package ];

    sops.secrets.juicefs_meta_password = {
      mode = "0400";
      restartUnits = [ "juicefs-mount.service" ];
    };

    sops.templates."juicefs.env" = {
      content = ''
        META_PASSWORD=${config.sops.placeholder.juicefs_meta_password}
      '';
      mode = "0400";
      restartUnits = [ "juicefs-mount.service" ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.mountPoint} 0755 root root -"
      "d ${cfg.cacheDir} 0700 root root -"
    ];

    systemd.services.juicefs-mount = {
      description = "JuiceFS mount (${cfg.name}) at ${cfg.mountPoint}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ dnsDeps;
      wants = [ "network-online.target" ] ++ dnsDeps;

      # juicefs runs in the foreground by default (no `-d`), so systemd can
      # supervise it directly.
      serviceConfig = {
        Type = "simple";
        EnvironmentFile = metaEnv;
        ExecStart = lib.escapeShellArgs ([ "${cfg.package}/bin/juicefs" ] ++ mountArgs);
        ExecStop = lib.escapeShellArgs [ "${cfg.package}/bin/juicefs" "umount" cfg.mountPoint ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
      unitConfig.RequiresMountsFor = cfg.cacheDir;
    };
  };
}
