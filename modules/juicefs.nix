{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.juicefsMounts;
  enabledMounts = filterAttrs (_: mount: mount.enable) cfg;
  enabledMountList = attrValues enabledMounts;
  hasEnabledMounts = enabledMountList != [];

  postgresMetaUrl = mount:
    "postgres://${mount.metadata.username}@${mount.metadata.host}:${toString mount.metadata.port}/${mount.metadata.database}?sslmode=${mount.metadata.sslmode}";

  unitName = name: "juicefs-${name}.service";
  envTemplateName = name: "juicefs-${name}.env";

  serviceDependencies =
    [ "network-online.target" ]
    ++ optional config.services.consul.enable "consul.service"
    ++ optional config.services.tailscale.enable "tailscale-online.service";

  mountSubmodule = { name, ... }: {
    options = {
      enable = mkEnableOption "JuiceFS FUSE mount";

      fsName = mkOption {
        type = types.str;
        default = name;
        description = "JuiceFS filesystem name used during format/bootstrap.";
      };

      mountPoint = mkOption {
        type = types.str;
        description = "Local mount path for the JuiceFS filesystem.";
      };

      cacheDir = mkOption {
        type = types.str;
        description = "Local JuiceFS data cache directory.";
      };

      cacheSizeMiB = mkOption {
        type = types.int;
        default = 10240;
        description = "JuiceFS data cache size in MiB.";
      };

      allowOther = mkOption {
        type = types.bool;
        default = true;
        description = "Allow non-root users and Nomad workloads to access the FUSE mount.";
      };

      readOnly = mkOption {
        type = types.bool;
        default = false;
        description = "Mount the JuiceFS filesystem read-only.";
      };

      extraMountOptions = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Additional raw arguments passed to `juicefs mount`.";
      };

      postgresPasswordSecret = mkOption {
        type = types.str;
        description = "SOPS secret name containing the PostgreSQL password for the JuiceFS metadata role.";
      };

      s3EnvSecret = mkOption {
        type = types.str;
        description = "SOPS secret name for an EnvironmentFile with JUICEFS_BUCKET_URL, ACCESS_KEY, SECRET_KEY, and optional SESSION_TOKEN.";
      };

      metadata = {
        host = mkOption {
          type = types.str;
          description = "PostgreSQL primary endpoint for JuiceFS metadata.";
        };

        port = mkOption {
          type = types.port;
          default = 5432;
          description = "PostgreSQL port for JuiceFS metadata.";
        };

        database = mkOption {
          type = types.str;
          description = "PostgreSQL database used for JuiceFS metadata.";
        };

        username = mkOption {
          type = types.str;
          description = "PostgreSQL role used for JuiceFS metadata.";
        };

        sslmode = mkOption {
          type = types.str;
          default = "disable";
          description = "PostgreSQL sslmode query parameter for the JuiceFS metadata URL.";
        };
      };

      nomad = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Publish this mount as a Nomad host volume.";
        };

        hostVolumeName = mkOption {
          type = types.str;
          default = name;
          description = "Nomad host volume name.";
        };

        readOnly = mkOption {
          type = types.bool;
          default = false;
          description = "Publish the Nomad host volume as read-only.";
        };
      };
    };
  };
in
{
  options.services.juicefsMounts = mkOption {
    type = types.attrsOf (types.submodule mountSubmodule);
    default = {};
    description = "JuiceFS FUSE mounts backed by PostgreSQL metadata and S3-compatible object storage.";
  };

  config = mkIf hasEnabledMounts (mkMerge [
    {
      assertions = concatLists (mapAttrsToList (name: mount: [
        {
          assertion = mount.cacheSizeMiB > 0;
          message = "services.juicefsMounts.${name}.cacheSizeMiB must be greater than zero.";
        }
      ]) enabledMounts);

      systemd.tmpfiles.rules = concatLists (mapAttrsToList (_: mount: [
        "d ${mount.mountPoint} 0755 root root -"
        "d ${mount.cacheDir} 0750 root root -"
      ]) enabledMounts);

      boot.kernelModules = [ "fuse" ];
      programs.fuse.userAllowOther = mkIf (any (mount: mount.allowOther) enabledMountList) true;

      environment.systemPackages = [
        pkgs.juicefs
        pkgs.fuse
      ];
    }

    {
      sops.secrets = mkMerge (mapAttrsToList (name: mount: {
        ${mount.postgresPasswordSecret} = {
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [ (unitName name) ];
        };
        ${mount.s3EnvSecret} = {
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [ (unitName name) ];
        };
      }) enabledMounts);

      sops.templates = mapAttrs' (name: mount:
        nameValuePair (envTemplateName name) {
          content = ''
            PGPASSWORD=${config.sops.placeholder.${mount.postgresPasswordSecret}}
          '';
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [ (unitName name) ];
        }
      ) enabledMounts;
    }

    {
      systemd.services = mapAttrs' (name: mount:
        let
          envFileName = envTemplateName name;
          s3EnvSecretPath = config.sops.secrets.${mount.s3EnvSecret}.path;
        in
        nameValuePair "juicefs-${name}" {
          description = "JuiceFS mount ${name}";
          wantedBy = [ "multi-user.target" ];
          after = serviceDependencies;
          wants = serviceDependencies;
          path = [
            pkgs.coreutils
            pkgs.juicefs
          ];

          script = ''
            : "''${PGPASSWORD:?PGPASSWORD must be set by ${envFileName}}"
            : "''${JUICEFS_BUCKET_URL:?JUICEFS_BUCKET_URL must be set by ${mount.s3EnvSecret}}"
            : "''${ACCESS_KEY:?ACCESS_KEY must be set by ${mount.s3EnvSecret}}"
            : "''${SECRET_KEY:?SECRET_KEY must be set by ${mount.s3EnvSecret}}"

            mount_args=(
              --bucket "$JUICEFS_BUCKET_URL"
              --cache-dir ${escapeShellArg mount.cacheDir}
              --cache-size ${toString mount.cacheSizeMiB}
              --no-usage-report
              ${optionalString mount.allowOther "-o allow_other"}
              ${optionalString mount.readOnly "--read-only"}
              ${concatStringsSep "\n              " (map escapeShellArg mount.extraMountOptions)}
            )

            if [ -n "''${SESSION_TOKEN:-}" ]; then
              mount_args+=(--session-token "$SESSION_TOKEN")
            fi

            exec ${pkgs.juicefs}/bin/juicefs mount \
              "''${mount_args[@]}" \
              ${escapeShellArg (postgresMetaUrl mount)} \
              ${escapeShellArg mount.mountPoint}
          '';

          serviceConfig = {
            Type = "simple";
            User = "root";
            Group = "root";
            EnvironmentFile = [
              config.sops.templates.${envFileName}.path
              s3EnvSecretPath
            ];
            ExecStop = "${pkgs.juicefs}/bin/juicefs umount ${mount.mountPoint}";
            KillMode = "process";
            Restart = "on-failure";
            RestartSec = "10s";
          };
        }
      ) enabledMounts;
    }

    {
      cluster.nomad.client.hostVolumes = mkMerge (mapAttrsToList (_: mount:
        mkIf mount.nomad.enable {
          ${mount.nomad.hostVolumeName} = {
            path = mount.mountPoint;
            readOnly = mount.nomad.readOnly;
            createDir = false;
          };
        }
      ) enabledMounts);
    }
  ]);
}
