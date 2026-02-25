{ config, lib, pkgs, nodes, hostName, ... }:

with lib;

let
  cfg = config.services.seaweedfs;
  nodeCfg = nodes.${hostName};

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
    if (nodeCfg ? "weedFiler" && nodeCfg.weedFiler) then
      localFilerNodes ++ remoteFilerNodes
    else
      sameDcFilerNodes ++ otherDcFilerNodes
  );

  orderedFilerAddresses =
    if cfg.mount != null && cfg.mount.filerServers != null then
      cfg.mount.filerServers
    else
      discoveredFilerAddresses;

  # Determine if any component is enabled
  isEnabled = cfg.master.enable || cfg.volume.enable || cfg.filer.enable || (cfg.mount != null);

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

      dbDir = mkOption {
        type = types.str;
        default = "/var/lib/seaweedfs/filer/leveldb2";
        description = "Directory for LevelDB database";
      };

      store = mkOption {
        type = types.enum [ "leveldb2" "postgres2" ];
        default = "leveldb2";
        description = "Metadata backend used by SeaweedFS filer";
      };

      postgres = {
        hostname = mkOption {
          type = types.str;
          default = "postgres-cluster.service.consul";
          description = "PostgreSQL writer endpoint hostname (typically Consul DNS)";
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

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to a file containing the PostgreSQL password";
        };

        sslmode = mkOption {
          type = types.str;
          default = "require";
          description = "PostgreSQL SSL mode";
        };

        connectionMaxIdle = mkOption {
          type = types.int;
          default = 2;
          description = "Maximum idle PostgreSQL connections";
        };

        connectionMaxOpen = mkOption {
          type = types.int;
          default = 100;
          description = "Maximum open PostgreSQL connections";
        };

        createTable = mkOption {
          type = types.bool;
          default = true;
          description = "Automatically create filer metadata tables";
        };
      };

      defaultReplicaPlacement = mkOption {
        type = types.str;
        default = "100";
        description = "Default replication placement for filer metadata";
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
  };

  config = mkIf isEnabled {
    assertions = [
      {
        assertion = !(cfg.filer.enable && cfg.filer.store == "postgres2") || cfg.filer.postgres.passwordFile != null;
        message = "services.seaweedfs.filer.postgres.passwordFile must be set when services.seaweedfs.filer.store = \"postgres2\".";
      }
    ];

    sops.secrets.seaweedfs_postgres_password = mkIf (cfg.filer.enable && cfg.filer.store == "postgres2") {
      sopsFile = ../secrets/secrets.yaml;
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
    ] ++ optionals (cfg.filer.enable && cfg.filer.store == "leveldb2") [
      "d ${cfg.filer.dbDir} 0750 seaweedfs seaweedfs -"
    ] ++ optionals (cfg.mount != null) [
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
          ${pkgs.seaweedfs}/bin/weed master \
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
          ${pkgs.seaweedfs}/bin/weed volume \
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
      after = [ "network.target" "seaweedfs-master.service" ] ++ tailscaleDependency;
      wants = tailscaleDependency;

      preStart = ''
        install -d -m 0755 -o root -g root /etc/seaweedfs
      '' + (if cfg.filer.store == "postgres2" then ''
        db_password="$(${pkgs.coreutils}/bin/cat "${cfg.filer.postgres.passwordFile}")"
        escaped_db_password="$(${pkgs.coreutils}/bin/printf '%s' "$db_password" | ${pkgs.gnused}/bin/sed -e 's/[\\"]/\\&/g')"

        cat > /etc/seaweedfs/filer.toml <<EOF2
[postgres2]
enabled = true
hostname = "${cfg.filer.postgres.hostname}"
port = ${toString cfg.filer.postgres.port}
username = "${cfg.filer.postgres.username}"
password = "$escaped_db_password"
database = "${cfg.filer.postgres.database}"
sslmode = "${cfg.filer.postgres.sslmode}"
connection_max_idle = ${toString cfg.filer.postgres.connectionMaxIdle}
connection_max_open = ${toString cfg.filer.postgres.connectionMaxOpen}
createTable = ${if cfg.filer.postgres.createTable then "true" else "false"}
EOF2
      '' else ''
        cat > /etc/seaweedfs/filer.toml <<EOF2
[leveldb2]
enabled = true
dir = "${cfg.filer.dbDir}"
EOF2
      '') + ''
        chown root:seaweedfs /etc/seaweedfs/filer.toml
        chmod 0640 /etc/seaweedfs/filer.toml
      '';

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        WorkingDirectory = "/var/lib/seaweedfs";
        PermissionsStartOnly = true;
        ExecStart = ''
          ${pkgs.seaweedfs}/bin/weed filer \
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
          ${pkgs.seaweedfs}/bin/weed mount \
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

    environment.systemPackages = [ pkgs.seaweedfs ] ++ optional (cfg.mount != null) pkgs.fuse;
  };
}
