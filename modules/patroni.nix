{ config, lib, pkgs, nodes, hostName, ... }:

with lib;

let
  cfg = config.services.patroni;
  nodeCfg = nodes.${hostName};

  # Find all nodes with Patroni enabled
  patroniNodes = lib.filter (n: n ? "patroni" && n.patroni) (lib.attrValues nodes);

  patroniConfig = {
    scope = cfg.scope;
    namespace = "/service/";
    name = hostName;

    restapi = {
      listen = "${nodeCfg.serviceIp}:8008";
      connect_address = "${nodeCfg.serviceIp}:8008";
    };

    consul = {
      host = "127.0.0.1:8500";
      register_service = true;
    };

    bootstrap = {
      dcs = {
        ttl = 30;
        loop_wait = 10;
        retry_timeout = 10;
        maximum_lag_on_failover = 1048576;
        postgresql = {
          use_pg_rewind = true;
          parameters = {
            max_connections = 200;
            shared_buffers = "256MB";
            effective_cache_size = "1GB";
            maintenance_work_mem = "64MB";
            checkpoint_completion_target = 0.9;
            wal_buffers = "16MB";
            default_statistics_target = 100;
            random_page_cost = 1.1;
            effective_io_concurrency = 200;
            work_mem = "1310kB";
            min_wal_size = "1GB";
            max_wal_size = "4GB";
            max_worker_processes = 4;
            max_parallel_workers_per_gather = 2;
            max_parallel_workers = 4;
            max_parallel_maintenance_workers = 2;
          };
        };
      };

      initdb = [
        { encoding = "UTF8"; }
        { data-checksums = true; }
      ];

      pg_hba = [
        "local all all peer"
        "host replication replicator 0.0.0.0/0 md5"
        "host all all 0.0.0.0/0 md5"
      ];

      users = {
        admin = {
          password = "admin";
          options = [ "CREATEDB" "CREATEROLE" ];
        };
        replicator = {
          password = "__REPLICATION_PASSWORD__";
          options = [ "REPLICATION" ];
        };
      };
    };

    postgresql = {
      listen = "${nodeCfg.serviceIp}:5432";
      connect_address = "${nodeCfg.serviceIp}:5432";
      data_dir = cfg.dataDir;
      bin_dir = "${pkgs.postgresql_17}/bin";
      pgpass = "/var/lib/patroni/.pgpass";
      authentication = {
        replication = {
          username = "replicator";
          password = "__REPLICATION_PASSWORD__";
        };
        superuser = {
          username = "postgres";
          password = "__SUPERUSER_PASSWORD__";
        };
      };
      parameters = {
        unix_socket_directories = "/run/postgresql";
        logging_collector = "on";
        log_directory = "/var/log/postgresql";
        log_filename = "postgresql-%Y-%m-%d.log";
        log_rotation_age = "1d";
        log_rotation_size = "100MB";
      };
      create_replica_methods = [ "basebackup" ];
      basebackup = [
        { checkpoint = "fast"; }
      ];
    };

    tags = {
      nofailover = false;
      noloadbalance = false;
      clonefrom = false;
      nosync = false;
    };
  };

  # Base config with placeholders
  patroniConfigTemplate = pkgs.writeText "patroni-template.yml" (builtins.toJSON patroniConfig);

  # Helper to manage dependencies
  tailscaleDependency = optional config.services.tailscale.enable "tailscale-online.service";
in
{
  options.services.patroni = {
    enable = mkEnableOption "Patroni PostgreSQL";

    scope = mkOption {
      type = types.str;
      default = "postgres-cluster";
      description = "Name of the Patroni cluster";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/postgresql/17/data";
      description = "PostgreSQL data directory";
    };
  };

  config = mkIf cfg.enable {
    # Require sops secrets for Patroni
    sops.secrets.postgres_superuser_password = {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      restartUnits = [ "patroni.service" ];
    };

    sops.secrets.postgres_replication_password = {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      restartUnits = [ "patroni.service" ];
    };

    users.groups.postgres = {};
    users.users.postgres = {
      isSystemUser = true;
      group = "postgres";
      home = "/var/lib/postgresql";
      description = "PostgreSQL database user";
    };

    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d /var/lib/postgresql 0750 postgres postgres -"
      "d /var/lib/postgresql/17 0750 postgres postgres -"
      "d ${cfg.dataDir} 0750 postgres postgres -"
      "d /var/lib/patroni 0750 postgres postgres -"
      "d /var/log/postgresql 0750 postgres postgres -"
      "d /run/postgresql 0755 postgres postgres -"
    ];

    # Patroni service
    systemd.services.patroni = {
      description = "Patroni PostgreSQL";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "consul.service" ] ++ tailscaleDependency;
      wants = tailscaleDependency;
      requires = [ "consul.service" ];

      # Substitute secrets into config at runtime
      script = ''
        SUPERUSER_PASSWORD=$(cat ${config.sops.secrets.postgres_superuser_password.path})
        REPLICATION_PASSWORD=$(cat ${config.sops.secrets.postgres_replication_password.path})

        sed -e "s|__SUPERUSER_PASSWORD__|$SUPERUSER_PASSWORD|g" \
            -e "s|__REPLICATION_PASSWORD__|$REPLICATION_PASSWORD|g" \
            ${patroniConfigTemplate} > /run/patroni/patroni.yml

        exec ${pkgs.patroni}/bin/patroni /run/patroni/patroni.yml
      '';

      preStart = ''
        mkdir -p /run/patroni
        chown postgres:postgres /run/patroni
        chmod 0750 /run/patroni
      '';

      serviceConfig = {
        Type = "simple";
        User = "postgres";
        Group = "postgres";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        KillMode = "mixed";
        KillSignal = "SIGINT";
        TimeoutSec = 0;
        Restart = "on-failure";
        RestartSec = "10s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "/var/lib/postgresql"
          "/var/lib/patroni"
          "/var/log/postgresql"
          "/run/postgresql"
          "/run/patroni"
        ];
      };
    };

    # Install PostgreSQL and Patroni
    environment.systemPackages = [
      pkgs.postgresql_17
      pkgs.patroni
    ];
  };
}