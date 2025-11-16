{ config, lib, pkgs, nodes, hostName, ... }:

with lib;

let
  cfg = config.services.seaweedfs;
  nodeCfg = nodes.${hostName};
  
  # Find master nodes (nodes with isRegistry = true)
  masterNodes = lib.filter (n: n ? "isRegistry" && n.isRegistry) (lib.attrValues nodes);
  masterAddresses = lib.map (n: "${n.serviceIp}:9333") masterNodes;
  filerAddresses = lib.map (n: "${n.serviceIp}:8888") masterNodes;

  # Use proper TOML format
  tomlFormat = pkgs.formats.toml {};

  # Filer configuration
  filerConfig = {
    leveldb2 = {
      enabled = true;
      dir = cfg.filer.dbDir;
    };
  };

  filerToml = tomlFormat.generate "filer.toml" filerConfig;

  # Determine if any component is enabled
  isEnabled = cfg.master.enable || cfg.volume.enable || cfg.filer.enable || (cfg.mount != null);
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
    };

    mount = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          mountPoint = mkOption {
            type = types.str;
            description = "Local path to mount the filer";
            example = "/mnt/seaweedfs";
          };

          filerAddress = mkOption {
            type = types.str;
            default = "${nodeCfg.serviceIp}:${toString cfg.filer.port}";
            description = "Filer address to connect to";
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
        };
      });
      default = null;
      description = "FUSE mount configuration";
    };
  };

  config = mkIf isEnabled {
    
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
      "d ${cfg.filer.dbDir} 0750 seaweedfs seaweedfs -"
      "L+ /etc/seaweedfs/filer.toml - - - - ${filerToml}"
    ] ++ optionals (cfg.mount != null) [
      "d ${cfg.mount.mountPoint} 0755 seaweedfs seaweedfs -"
      "d ${cfg.mount.cacheDir} 0750 seaweedfs seaweedfs -"
    ];

    # Master server service
    systemd.services.seaweedfs-master = mkIf cfg.master.enable {
      description = "SeaweedFS Master Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

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
            ${optionalString (cfg.master.peers != []) 
              "-peers=${concatStringsSep "," cfg.master.peers}"} \
            -defaultReplication=001
        '';
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Volume server service
    systemd.services.seaweedfs-volume = mkIf cfg.volume.enable {
      description = "SeaweedFS Volume Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ optional cfg.master.enable "seaweedfs-master.service";

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
      after = [ "network.target" "seaweedfs-master.service" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
        WorkingDirectory = "/var/lib/seaweedfs";
        ExecStart = ''
          ${pkgs.seaweedfs}/bin/weed filer \
            -ip=${nodeCfg.serviceIp} \
            -port=${toString cfg.filer.port} \
            -master=${concatStringsSep "," masterAddresses} \
            -dataCenter=${cfg.volume.dataCenter} \
            -defaultReplicaPlacement=001 \
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
      after = [ "network.target" ];
      requires = mkIf cfg.filer.enable [ "seaweedfs-filer.service" ];

      # Add fuse to the PATH
      path = [ pkgs.fuse ];

      serviceConfig = {
        Type = "forking";
        User = "seaweedfs";
        Group = "seaweedfs";
        ExecStart = ''
          ${pkgs.seaweedfs}/bin/weed mount \
            -filer='${concatStringsSep "," filerAddresses}' \
            -dir=${cfg.mount.mountPoint} \
            -cacheDir=${cfg.mount.cacheDir} \
            -cacheCapacityMB=${toString cfg.mount.cacheSizeMB} \
            ${optionalString cfg.mount.allowOthers "-allowOthers"} \
            ${optionalString cfg.mount.readOnly "-readOnly"} \
            -dirAutoCreate
        '';
        ExecStop = "${pkgs.fuse}/bin/fusermount -u ${cfg.mount.mountPoint}";
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