{ config, lib, pkgs, pkgs-unstable, nodes, hostName, ... }:

with lib;

let
  cfg = config.services.seaweedfs;
  seaweedfsPkg = pkgs-unstable.seaweedfs;
  pgbouncerCfg = config.services.postgresPrimaryPgbouncer;
  nodeCfg = nodes.${hostName};
  masterNodeEnabled = nodeCfg ? weedMaster && nodeCfg.weedMaster;
  filerNodeEnabled = nodeCfg ? weedFiler && nodeCfg.weedFiler;
  site = nodeCfg.datacenter or "default";

  masterNodes = lib.filter (n: n ? "weedMaster" && n.weedMaster) (lib.attrValues nodes);
  filerNodesWithNames = lib.filter
    (entry: entry.node ? "weedFiler" && entry.node.weedFiler)
    (lib.mapAttrsToList (name: node: { inherit name node; }) nodes);

  masterAddresses = lib.map (n: "${n.serviceIp}:9333") masterNodes;

  sortNodeEntriesByName = lib.sort (a: b: a.name < b.name);

  localFilerNodes = sortNodeEntriesByName (lib.filter (entry: entry.name == hostName) filerNodesWithNames);
  remoteFilerNodes = sortNodeEntriesByName (lib.filter (entry: entry.name != hostName) filerNodesWithNames);

  sameDcFilerNodes = sortNodeEntriesByName
    (lib.filter (entry: (entry.node.datacenter or null) == (nodeCfg.datacenter or null)) filerNodesWithNames);
  otherDcFilerNodes = sortNodeEntriesByName
    (lib.filter (entry: (entry.node.datacenter or null) != (nodeCfg.datacenter or null)) filerNodesWithNames);

  discoveredFilerAddresses = map (entry: "${entry.node.serviceIp}:8888") (
    if filerNodeEnabled then
      localFilerNodes ++ remoteFilerNodes
    else
      sameDcFilerNodes ++ otherDcFilerNodes
  );

  orderedFilerAddresses =
    if cfg.mount != null && cfg.mount.filerServers != null then
      cfg.mount.filerServers
    else
      discoveredFilerAddresses;

  s3Args = [
    "-ip.bind=${cfg.s3.bindIp}"
    "-port=${toString cfg.s3.port}"
    "-filer=${cfg.s3.filer}"
  ] ++ optional (cfg.s3.domainNames != [])
    "-domainName=${concatStringsSep "," cfg.s3.domainNames}";

  seaweedS3Health = pkgs.writeShellApplication {
    name = "seaweed-s3-health";
    runtimeInputs = with pkgs; [
      awscli2
      coreutils
    ];
    text = ''
      timeout_seconds=${toString cfg.s3Health.timeoutSeconds}
      workroot=/run/seaweed-s3-health

      if [ "''${1:-}" != "--run" ]; then
        workdir="$(mktemp -d "$workroot/check.XXXXXXXXXX")"
        trap 'rm -rf "$workdir"' EXIT

        status=0
        timeout --kill-after=1s "''${timeout_seconds}s" "$0" --run "$workdir" "$@" || status=$?
        exit "$status"
      fi
      shift
      workdir=''${1:?missing workdir}
      shift

      endpoint=${escapeShellArg cfg.s3Health.endpoint}
      secret_file=${escapeShellArg config.sops.secrets."seaweed_s3_health.env".path}
      key_prefix=${escapeShellArg cfg.s3Health.keyPrefix}

      AWS_ACCESS_KEY_ID="''${AWS_ACCESS_KEY_ID:-}"
      AWS_SECRET_ACCESS_KEY="''${AWS_SECRET_ACCESS_KEY:-}"
      SEAWEED_S3_HEALTH_BUCKET="''${SEAWEED_S3_HEALTH_BUCKET:-}"
      AWS_DEFAULT_REGION="''${AWS_DEFAULT_REGION:-us-east-1}"

      # shellcheck disable=SC1090
      . "$secret_file"

      : "''${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set in $secret_file}"
      : "''${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set in $secret_file}"
      : "''${SEAWEED_S3_HEALTH_BUCKET:?SEAWEED_S3_HEALTH_BUCKET must be set in $secret_file}"

      export AWS_ACCESS_KEY_ID
      export AWS_SECRET_ACCESS_KEY
      export AWS_DEFAULT_REGION
      export AWS_EC2_METADATA_DISABLED=true

      body_file="$workdir/body"
      result_file="$workdir/result"
      object_key="$key_prefix/$(hostname)-$$-$(date +%s%N)"
      created=0

      # shellcheck disable=SC2329
      cleanup() {
        if [ "$created" -eq 1 ]; then
          aws --endpoint-url "$endpoint" s3api delete-object \
            --bucket "$SEAWEED_S3_HEALTH_BUCKET" \
            --key "$object_key" \
            --no-cli-pager >/dev/null 2>&1 || true
        fi
        rm -rf "$workdir"
      }
      trap cleanup EXIT

      printf 'seaweed-s3-health %s %s\n' "$(hostname)" "$(date --iso-8601=ns)" > "$body_file"

      aws --endpoint-url "$endpoint" s3api put-object \
        --bucket "$SEAWEED_S3_HEALTH_BUCKET" \
        --key "$object_key" \
        --body "$body_file" \
        --no-cli-pager >/dev/null
      created=1

      aws --endpoint-url "$endpoint" s3api get-object \
        --bucket "$SEAWEED_S3_HEALTH_BUCKET" \
        --key "$object_key" \
        "$result_file" \
        --no-cli-pager >/dev/null

      cmp -s "$body_file" "$result_file"

      aws --endpoint-url "$endpoint" s3api delete-object \
        --bucket "$SEAWEED_S3_HEALTH_BUCKET" \
        --key "$object_key" \
        --no-cli-pager >/dev/null
      created=0

      echo "seaweed-s3-health ok"
    '';
  };

  # Determine if any component is enabled
  isEnabled = cfg.master.enable || cfg.volume.enable || cfg.filer.enable || cfg.s3.enable || (cfg.mount != null) || cfg.s3Health.enable;
  filerPostgresHost =
    if pgbouncerCfg.enable then
      pgbouncerCfg.listenAddress
    else
      cfg.filer.postgres.hostname;
  filerPostgresPort =
    if pgbouncerCfg.enable then
      pgbouncerCfg.listenPort
    else
      cfg.filer.postgres.port;

  # Helper to manage tailscale dependency
  tailscaleDependency = optional config.services.tailscale.enable "tailscale-online.service";
in
{
  options.services.seaweedfs = {
    master = {
      enable = mkEnableOption "SeaweedFS master server";

      port = mkOption {
        type = types.port;
        default = 9333;
        description = "Port for master server";
      };

      volumeSizeLimitMB = mkOption {
        type = types.int;
        default = 30000;
        description = "Default volume size limit in MB";
      };

      peers = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of other master peers for HA setup";
      };

      consul = {
        enable = mkOption {
          type = types.bool;
          default = config.services.consul.enable;
          description = "Register the master in the local Consul agent.";
        };

        serviceName = mkOption {
          type = types.str;
          default = "seaweedfs-master";
          description = ''
            Consul service name for master discovery. Consumers can resolve
            <site>.<service>.service.consul for site-local lookup and
            <service>.service.consul for global fallback.
          '';
        };

        extraTags = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional Consul tags appended to the standard master tags.";
        };
      };
    };

    volume = {
      enable = mkEnableOption "SeaweedFS volume server";

      port = mkOption {
        type = types.port;
        default = 1133;
        description = "Port for volume server";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/seaweedfs/volumes";
        description = "Directory to store volume data";
      };

      maxVolumes = mkOption {
        type = types.int;
        default = 100;
        description = "Maximum number of volumes";
      };

      rack = mkOption {
        type = types.nullOr types.str;
        default = nodeCfg.datacenter or null;
        description = "Rack identifier for data placement";
      };

      dataCenter = mkOption {
        type = types.str;
        default = nodeCfg.datacenter or "default";
        description = "Data center identifier";
      };
    };

    filer = {
      enable = mkEnableOption "SeaweedFS filer server";

      port = mkOption {
        type = types.port;
        default = 8888;
        description = "Port for filer server";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/seaweedfs/filer";
        description = "Directory to store filer metadata";
      };

      postgres = {
        hostname = mkOption {
          type = types.str;
          default = "primary.postgres-cluster.service.consul";
          description = "PostgreSQL writer endpoint hostname (typically a Consul DNS tag-filtered primary service).";
        };

        port = mkOption {
          type = types.port;
          default = 5432;
          description = "PostgreSQL port";
        };

        database = mkOption {
          type = types.str;
          default = "seaweedfs_filer";
          description = "PostgreSQL database used for filer metadata";
        };

        username = mkOption {
          type = types.str;
          default = "seaweedfs";
          description = "PostgreSQL username used for filer metadata";
        };

        sslmode = mkOption {
          type = types.str;
          default = "disable";
          description = "PostgreSQL SSL mode. Use \"disable\" unless PostgreSQL TLS is configured.";
        };

        connectionMaxIdle = mkOption {
          type = types.int;
          default = 2;
          description = "Maximum idle PostgreSQL connections";
        };

        connectionMaxOpen = mkOption {
          type = types.int;
          default = 32;
          description = "Maximum open PostgreSQL connections";
        };
      };

      defaultReplicaPlacement = mkOption {
        type = types.str;
        default = "100";
        description = "Default replication placement for filer metadata";
      };

      consul = {
        enable = mkOption {
          type = types.bool;
          default = config.services.consul.enable;
          description = "Register the filer in the local Consul agent.";
        };

        serviceName = mkOption {
          type = types.str;
          default = "seaweedfs-filer";
          description = ''
            Consul service name for filer discovery. Consumers can resolve
            <site>.<service>.service.consul for site-local lookup and
            <service>.service.consul for global fallback.
          '';
        };

        extraTags = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional Consul tags appended to the standard filer tags.";
        };
      };
    };

    mount = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          mountPoint = mkOption {
            type = types.str;
            description = "Local path to mount the filer";
            example = "/mnt/seaweedfs";
          };

          filerServers = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = "Optional explicit list of filer servers in host:port format";
          };

          allowOthers = mkOption {
            type = types.bool;
            default = true;
            description = "Allow other users to access the mount";
          };

          readOnly = mkOption {
            type = types.bool;
            default = false;
            description = "Mount as read-only";
          };

          cacheDir = mkOption {
            type = types.str;
            default = "/var/cache/seaweedfs-mount";
            description = "Directory for local file cache";
          };

          cacheSizeMB = mkOption {
            type = types.int;
            default = 1000;
            description = "Cache size in MB";
          };

          dataCenter = mkOption {
            type = types.str;
            default = nodeCfg.datacenter or "default";
            description = ''
              Data center label used to prefer nearby volume servers when
              reading. Should match the -dataCenter value used by the volume
              servers at this site so that cross-WAN reads are avoided.
            '';
          };

          rack = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Rack label used to further prefer volume servers on the same
              rack within the data center. Leave null to rely on dataCenter
              locality only.
            '';
          };
        };
      });
      default = null;
      description = "FUSE mount configuration";
    };

    s3 = {
      enable = mkOption {
        type = types.bool;
        default = cfg.filer.enable;
        description = "Enable a host-native SeaweedFS S3 gateway backed by the local filer.";
      };

      bindIp = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "IP address the S3 gateway binds to.";
      };

      port = mkOption {
        type = types.port;
        default = 8333;
        description = "HTTP port for the S3 gateway.";
      };

      filer = mkOption {
        type = types.str;
        default = "127.0.0.1:8888";
        description = "Filer address passed to weed s3.";
      };

      domainNames = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Optional bucket virtual-host domain suffixes passed as -domainName.";
      };

      consul = {
        enable = mkOption {
          type = types.bool;
          default = config.services.consul.enable;
          description = "Register the S3 gateway in the local Consul agent.";
        };

        serviceName = mkOption {
          type = types.str;
          default = "seaweedfs-s3";
          description = "Consul service name for S3 gateway discovery.";
        };

        extraTags = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional Consul tags appended to the standard S3 tags.";
        };
      };
    };

    s3Health = {
      enable = mkOption {
        type = types.bool;
        default = cfg.s3.enable;
        description = "Install a Consul script-check compatible S3 PUT/GET/DELETE health check for the local SeaweedFS S3 gateway.";
      };

      endpoint = mkOption {
        type = types.str;
        default = "http://127.0.0.1:${toString cfg.s3.port}";
        description = "S3 endpoint checked by seaweed-s3-health.";
      };

      timeoutSeconds = mkOption {
        type = types.int;
        default = 8;
        description = "Wall-clock timeout for the whole S3 health check script.";
      };

      keyPrefix = mkOption {
        type = types.str;
        default = "nomad-health/seaweed-s3";
        description = "Object key prefix used for temporary S3 health check objects.";
      };
    };
  };

  config = mkIf isEnabled {
    services.postgresPrimaryPgbouncer.enable = mkDefault cfg.filer.enable;
    services.postgresPrimaryPgbouncer.users = mkIf cfg.filer.enable {
      "${cfg.filer.postgres.username}" = {
        passwordFile = config.sops.secrets.seaweedfs_postgres_password.path;
      };
    };

    assertions = [
      {
        assertion = cfg.master.enable == masterNodeEnabled;
        message = ''
          SeaweedFS master topology mismatch on ${hostName}: services.seaweedfs.master.enable
          must match cluster/nodes.nix weedMaster so Consul and Nomad metadata stay aligned.
        '';
      }
      {
        assertion = cfg.filer.enable == filerNodeEnabled;
        message = ''
          SeaweedFS filer topology mismatch on ${hostName}: services.seaweedfs.filer.enable
          must match cluster/nodes.nix weedFiler so Consul and Nomad metadata stay aligned.
        '';
      }
      {
        assertion = cfg.s3Health.timeoutSeconds > 0;
        message = "services.seaweedfs.s3Health.timeoutSeconds must be greater than zero.";
      }
      {
        assertion = !cfg.s3.enable || cfg.filer.enable;
        message = "services.seaweedfs.s3.enable requires services.seaweedfs.filer.enable.";
      }
      {
        assertion = !cfg.s3Health.enable || cfg.s3.enable;
        message = "services.seaweedfs.s3Health.enable requires services.seaweedfs.s3.enable.";
      }
    ];

    sops.secrets.seaweedfs_postgres_password = mkIf cfg.filer.enable {
      sopsFile = ../secrets/secrets.yaml;
      owner = "root";
      group = "seaweedfs";
      mode = "0440";
      restartUnits = [ "pgbouncer.service" "seaweedfs-filer.service" ];
    };

    sops.secrets."seaweed_s3_health.env" = mkIf cfg.s3Health.enable {
      sopsFile = ../secrets/secrets.yaml;
      owner = "consul";
      group = "consul";
      mode = "0440";
    };

    sops.templates."seaweedfs-filer.toml" = mkIf cfg.filer.enable {
      content = ''
        [postgres2]
        enabled = true
        hostname = "${filerPostgresHost}"
        port = ${toString filerPostgresPort}
        username = "${cfg.filer.postgres.username}"
        password = "${config.sops.placeholder.seaweedfs_postgres_password}"
        database = "${cfg.filer.postgres.database}"
        sslmode = "${cfg.filer.postgres.sslmode}"
        connection_max_idle = ${toString cfg.filer.postgres.connectionMaxIdle}
        connection_max_open = ${toString cfg.filer.postgres.connectionMaxOpen}
        pgbouncer_compatible = ${if pgbouncerCfg.enable then "true" else "false"}
        enableUpsert = false
        createTable = """
          CREATE TABLE IF NOT EXISTS "%s" (
            dirhash   BIGINT,
            name      VARCHAR(65535),
            directory VARCHAR(65535),
            meta      bytea,
            PRIMARY KEY (dirhash, name)
          );
        """
      '';
      owner = "root";
      group = "seaweedfs";
      mode = "0440";
    };

    # Create seaweedfs user and group
    users.groups.seaweedfs = {};
    users.users.seaweedfs = {
      isSystemUser = true;
      group = "seaweedfs";
      home = "/var/lib/seaweedfs";
      description = "SeaweedFS service user";
    };

    # Create data directories
    systemd.tmpfiles.rules = [
      "d /var/lib/seaweedfs 0750 seaweedfs seaweedfs -"
      "d /etc/seaweedfs 0755 root root -"
    ] ++ optional cfg.volume.enable
      "d ${cfg.volume.dataDir} 0750 seaweedfs seaweedfs -"
    ++ optionals cfg.filer.enable [
      "d ${cfg.filer.dataDir} 0750 seaweedfs seaweedfs -"
      "L+ /etc/seaweedfs/filer.toml - - - - ${config.sops.templates."seaweedfs-filer.toml".path}"
    ] ++ optional cfg.s3Health.enable
      "d /run/seaweed-s3-health 0750 consul consul 1h -"
    ++ optionals (cfg.mount != null) [
      "d ${cfg.mount.mountPoint} 0755 root root -"
      "d ${cfg.mount.cacheDir} 0750 root root -"
    ];

    # Master server service
    systemd.services.seaweedfs-master = mkIf cfg.master.enable {
      description = "SeaweedFS Master Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ tailscaleDependency;
      wants = tailscaleDependency;

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        WorkingDirectory = "/var/lib/seaweedfs";
        ExecStart = ''
          ${seaweedfsPkg}/bin/weed master \
            -ip=${nodeCfg.serviceIp} \
            -port=${toString cfg.master.port} \
            -volumeSizeLimitMB=${toString cfg.master.volumeSizeLimitMB} \
            ${optionalString (masterAddresses != [])
              "-peers=${concatStringsSep "," masterAddresses}"}
        '';
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Volume server service
    systemd.services.seaweedfs-volume = mkIf cfg.volume.enable {
      description = "SeaweedFS Volume Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ]
        ++ optional cfg.master.enable "seaweedfs-master.service"
        ++ tailscaleDependency;
      wants = tailscaleDependency;

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        WorkingDirectory = "/var/lib/seaweedfs";
        ExecStart = ''
          ${seaweedfsPkg}/bin/weed volume \
            -ip=${nodeCfg.serviceIp} \
            -port=${toString cfg.volume.port} \
            -dir=${cfg.volume.dataDir} \
            -max=${toString cfg.volume.maxVolumes} \
            -mserver=${concatStringsSep "," masterAddresses} \
            -dataCenter=${cfg.volume.dataCenter} \
            ${optionalString (cfg.volume.rack != null) "-rack=${cfg.volume.rack}"}
        '';
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Filer server service
    systemd.services.seaweedfs-filer = mkIf cfg.filer.enable {
      description = "SeaweedFS Filer Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "seaweedfs-master.service" ]
        ++ optional pgbouncerCfg.enable "pgbouncer.service"
        ++ tailscaleDependency;
      wants = optional pgbouncerCfg.enable "pgbouncer.service" ++ tailscaleDependency;
      requires = optional pgbouncerCfg.enable "pgbouncer.service";

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        WorkingDirectory = "/var/lib/seaweedfs";
        ExecStart = ''
          ${seaweedfsPkg}/bin/weed filer \
            -ip=${nodeCfg.serviceIp} \
            -port=${toString cfg.filer.port} \
            -master=${concatStringsSep "," masterAddresses} \
            -dataCenter=${cfg.volume.dataCenter} \
            ${optionalString (cfg.volume.rack != null) "-rack=${cfg.volume.rack}"} \
            -defaultReplicaPlacement=${cfg.filer.defaultReplicaPlacement} \
            -dirListLimit=100000
        '';
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # S3 gateway service
    systemd.services.seaweedfs-s3 = mkIf cfg.s3.enable {
      description = "SeaweedFS S3 Gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "seaweedfs-filer.service" ] ++ tailscaleDependency;
      wants = tailscaleDependency;
      requires = [ "seaweedfs-filer.service" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        WorkingDirectory = "/var/lib/seaweedfs";
        ExecStart = "${seaweedfsPkg}/bin/weed s3 ${escapeShellArgs s3Args}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    environment.etc = mkMerge [
      (mkIf (cfg.master.enable && cfg.master.consul.enable && config.services.consul.enable) {
        "consul.d/seaweedfs-master.json".text = builtins.toJSON {
          services = [
            {
              name = cfg.master.consul.serviceName;
              id = "${cfg.master.consul.serviceName}-${hostName}";
              address = nodeCfg.serviceIp;
              port = cfg.master.port;
              tags = unique ([ "seaweedfs" "master" site ] ++ cfg.master.consul.extraTags);
              meta = {
                site = site;
                host = hostName;
              };
              checks = [
                {
                  id = "${cfg.master.consul.serviceName}-${hostName}-tcp";
                  name = "SeaweedFS master TCP";
                  tcp = "${nodeCfg.serviceIp}:${toString cfg.master.port}";
                  interval = "10s";
                  timeout = "1s";
                }
              ];
            }
          ];
        };
      })

      (mkIf (cfg.filer.enable && cfg.filer.consul.enable && config.services.consul.enable) {
        "consul.d/seaweedfs-filer.json".text = builtins.toJSON {
          services = [
            {
              name = cfg.filer.consul.serviceName;
              id = "${cfg.filer.consul.serviceName}-${hostName}";
              address = nodeCfg.serviceIp;
              port = cfg.filer.port;
              tags = unique ([ "seaweedfs" "filer" site ] ++ cfg.filer.consul.extraTags);
              meta = {
                site = site;
                host = hostName;
              };
              checks = [
                {
                  id = "${cfg.filer.consul.serviceName}-${hostName}-tcp";
                  name = "SeaweedFS filer TCP";
                  tcp = "${nodeCfg.serviceIp}:${toString cfg.filer.port}";
                  interval = "10s";
                  timeout = "1s";
                }
              ];
            }
          ];
        };
      })

      (mkIf (cfg.s3.enable && cfg.s3.consul.enable && config.services.consul.enable) {
        "consul.d/seaweedfs-s3.json".text = builtins.toJSON {
          services = [
            {
              name = cfg.s3.consul.serviceName;
              id = "${cfg.s3.consul.serviceName}-${hostName}";
              address = nodeCfg.serviceIp;
              port = cfg.s3.port;
              tags = unique ([ "seaweedfs" "s3" site ] ++ cfg.s3.consul.extraTags);
              meta = {
                site = site;
                host = hostName;
              };
              checks = [
                {
                  id = "${cfg.s3.consul.serviceName}-${hostName}-tcp";
                  name = "SeaweedFS S3 TCP";
                  tcp = "${nodeCfg.serviceIp}:${toString cfg.s3.port}";
                  interval = "10s";
                  timeout = "1s";
                }
              ] ++ optional cfg.s3Health.enable {
                id = "${cfg.s3.consul.serviceName}-${hostName}-deep";
                name = "SeaweedFS S3 PUT/GET/DELETE";
                args = [ "/run/current-system/sw/bin/seaweed-s3-health" ];
                interval = "30s";
                timeout = "10s";
              };
            }
          ];
        };
      })
    ];

    services.consul.extraConfig = mkIf (cfg.s3Health.enable && config.services.consul.enable) {
      enable_local_script_checks = true;
    };

    # FUSE mount service
    systemd.services.seaweedfs-mount = mkIf (cfg.mount != null) {
      description = "SeaweedFS FUSE Mount";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ tailscaleDependency;
      wants = tailscaleDependency;
      requires = mkIf cfg.filer.enable [ "seaweedfs-filer.service" ];

      # Add fuse to the PATH
      path = [ pkgs.fuse ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        ExecStart = ''
          ${seaweedfsPkg}/bin/weed mount \
            -filer='${concatStringsSep "," orderedFilerAddresses}' \
            -dir=${cfg.mount.mountPoint} \
            -cacheDir=${cfg.mount.cacheDir} \
            -cacheCapacityMB=${toString cfg.mount.cacheSizeMB} \
            -dataCenter=${cfg.mount.dataCenter} \
            ${optionalString (cfg.mount.rack != null) "-rack=${cfg.mount.rack}"} \
            ${optionalString cfg.mount.allowOthers "-allowOthers"} \
            ${optionalString cfg.mount.readOnly "-readOnly"} \
            -dirAutoCreate
        '';
        ExecStop = "${pkgs.fuse}/bin/fusermount -u ${cfg.mount.mountPoint}";
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Enable FUSE support if mounting
    boot.kernelModules = mkIf (cfg.mount != null) [ "fuse" ];

    # Enable user_allow_other in /etc/fuse.conf if allowOthers is enabled
    programs.fuse.userAllowOther = mkIf (cfg.mount != null && cfg.mount.allowOthers) true;

    environment.systemPackages = [ seaweedfsPkg ]
      ++ optional (cfg.mount != null) pkgs.fuse
      ++ optional cfg.s3Health.enable seaweedS3Health;
  };
}
