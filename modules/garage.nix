{ config, lib, pkgs, nodes, hostName, ... }:

let
  nodeCfg = nodes.${hostName};
  cfg = nodeCfg.garage or {};
  enabled = cfg.enable or false;
  s3Port = 3900;
  garageNodes = lib.filterAttrs (_: node: node.garage.enable or false) nodes;
  layoutNodes = lib.mapAttrs
    (name: node: {
      zone = node.garage.zone or node.datacenter;
      capacity = node.garage.capacity;
      rpcPublicAddr = "${node.serviceIp}:3901";
      serviceIp = node.serviceIp;
    })
    garageNodes;
in
{
  config = lib.mkIf enabled {
    users.groups.garage = {};
    users.users.garage = {
      isSystemUser = true;
      group = "garage";
      home = "/var/lib/garage";
      description = "Garage object storage service user";
    };

    sops.secrets = {
      garage_rpc_secret = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
      };

      garage_admin_token = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
      };

      garage_metrics_token = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
      };
    };

    sops.templates."garage.env" = {
      content = ''
        GARAGE_RPC_SECRET_FILE=${config.sops.secrets.garage_rpc_secret.path}
        GARAGE_ADMIN_TOKEN_FILE=${config.sops.secrets.garage_admin_token.path}
        GARAGE_METRICS_TOKEN_FILE=${config.sops.secrets.garage_metrics_token.path}
        GARAGE_LOG_TO_JOURNALD=true
      '';
      owner = "garage";
      group = "garage";
      mode = "0440";
    };

    services.garage = {
      enable = true;
      package = pkgs.garage_2;
      environmentFile = config.sops.templates."garage.env".path;
      logLevel = "info";
      settings = {
        replication_factor = 3;
        consistency_mode = "consistent";

        metadata_dir = "/var/lib/garage/meta";
        data_dir = "/var/lib/garage/data";
        metadata_auto_snapshot_interval = "6h";

        db_engine = "lmdb";

        rpc_bind_addr = "${nodeCfg.serviceIp}:3901";
        rpc_public_addr = "${nodeCfg.serviceIp}:3901";

        s3_api = {
          s3_region = "garage";
          api_bind_addr = "${nodeCfg.serviceIp}:${toString s3Port}";
        };

        admin = {
          api_bind_addr = "127.0.0.1:3903";
          metrics_require_token = true;
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/garage 0750 garage garage -"
      "d /var/lib/garage/meta 0750 garage garage -"
      "d /var/lib/garage/data 0750 garage garage -"
    ];

    systemd.services.garage = {
      after = lib.optional config.services.tailscale.enable "tailscale-online.service";
      wants = lib.optional config.services.tailscale.enable "tailscale-online.service";
      unitConfig.RequiresMountsFor = "/var/lib/garage";
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "garage";
        Group = "garage";
        Restart = lib.mkForce "on-failure";
        RestartSec = lib.mkForce "10s";
      };
    };

    environment.etc."garage-layout-nodes.json".text = builtins.toJSON layoutNodes;

    environment.etc."consul.d/garage-s3.json" = lib.mkIf config.services.consul.enable {
      text = builtins.toJSON {
        services = [
          {
            name = "garage-s3";
            id = "garage-s3-${hostName}";
            address = nodeCfg.serviceIp;
            port = s3Port;
            tags = [
              "garage"
              "s3"
              "internal"
              nodeCfg.datacenter
            ];
            meta = {
              site = nodeCfg.datacenter;
              host = hostName;
              region = "garage";
            };
            checks = [
              {
                id = "garage-s3-${hostName}-tcp";
                name = "Garage S3 TCP";
                tcp = "${nodeCfg.serviceIp}:${toString s3Port}";
                interval = "10s";
                timeout = "1s";
              }
            ];
          }
        ];
      };
    };
  };
}
