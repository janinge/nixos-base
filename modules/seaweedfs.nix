{ config, lib, pkgs, nodes, hostName, ... }:

with lib;

let
  cfg = config.services.seaweedfs;
  nodeCfg = nodes.${hostName};
  
  # Find master nodes (nodes with isRegistry = true)
  masterNodes = lib.filter (n: n ? "isRegistry" && n.isRegistry) (lib.attrValues nodes);
  masterAddresses = lib.map (n: "${n.serviceIp}:9333") masterNodes;
in
{
  options.services.seaweedfs = {
    enable = mkEnableOption "SeaweedFS distributed file system";

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
        default = 8080;
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
    };
  };

  config = mkIf cfg.enable {
    
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
    ] ++ optional cfg.volume.enable
      "d ${cfg.volume.dataDir} 0750 seaweedfs seaweedfs -"
    ++ optional cfg.filer.enable
      "d ${cfg.filer.dataDir} 0750 seaweedfs seaweedfs -";

    # Master server service
    systemd.services.seaweedfs-master = mkIf cfg.master.enable {
      description = "SeaweedFS Master Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "seaweedfs";
        Group = "seaweedfs";
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
        ExecStart = ''
          ${pkgs.seaweedfs}/bin/weed filer \
            -ip=${nodeCfg.serviceIp} \
            -port=${toString cfg.filer.port} \
            -master=${concatStringsSep "," masterAddresses} \
            -dataCenter=${cfg.volume.dataCenter}
        '';
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    environment.systemPackages = [ pkgs.seaweedfs ];
  };
}