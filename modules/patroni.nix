{ config, lib, pkgs, nodes, hostName, ... }:

with lib;

let
  cfg = config.cluster.patroni;
  nodeCfg = nodes.${hostName};

  # Select PostgreSQL package based on version
  pgPackage = pkgs."postgresql_${toString cfg.postgresqlVersion}";

  # Find all nodes with Patroni enabled for the cluster
  patroniNodes = lib.filter (n: n ? "patroni" && n.patroni) (lib.attrValues nodes);
  patroniNodeIps = map (n: n.serviceIp) patroniNodes;
in
{
  options.cluster.patroni = {
    enable = mkEnableOption "Patroni PostgreSQL";

    scope = mkOption {
      type = types.str;
      default = "postgres-cluster";
      description = "Name of the Patroni cluster";
    };

    postgresqlVersion = mkOption {
      type = types.int;
      default = 17;
      description = "PostgreSQL major version";
    };
  };

  config = mkIf cfg.enable {
    # Configure sops secrets
    sops.secrets.postgres_superuser_password = {
      sopsFile = ../secrets/secrets.yaml;
    };

    sops.secrets.postgres_replication_password = {
      sopsFile = ../secrets/secrets.yaml;
    };

    # Create environment file from secrets
    sops.templates."patroni-env" = {
      content = ''
        PATRONI_SUPERUSER_PASSWORD=${config.sops.placeholder.postgres_superuser_password}
        PATRONI_REPLICATION_PASSWORD=${config.sops.placeholder.postgres_replication_password}
        PATRONI_REWIND_PASSWORD=${config.sops.placeholder.postgres_replication_password}
      '';
      mode = "0400";
    };

    services.patroni = {
      enable = true;
      name = hostName;
      scope = cfg.scope;
      nodeIp = nodeCfg.serviceIp;
      otherNodesIps = patroniNodeIps;

      postgresqlPackage = pgPackage;
      postgresqlPort = 5432;
      postgresqlDataDir = "/var/lib/postgresql/${toString cfg.postgresqlVersion}/data";

      settings = {
        # Consul DCS configuration
        consul = {
          host = "127.0.0.1:8500";
          register_service = true;
        };

        # REST API
        restapi = {
          listen = "${nodeCfg.serviceIp}:8008";
          connect_address = "${nodeCfg.serviceIp}:8008";
        };

        # Bootstrap configuration
        bootstrap = {
          dcs = {
            ttl = 30;
            loop_wait = 10;
            retry_timeout = 10;
            maximum_lag_on_failover = 1048576;

            postgresql = {
              use_pg_rewind = true;
              use_slots = true;

              parameters = {
                # Connection settings
                max_connections = 64;
                superuser_reserved_connections = 4;

                # Memory settings
                shared_buffers = "2GB";
                effective_cache_size = "6GB";
                maintenance_work_mem = "1GB";
                work_mem = "20MB";

                # WAL settings
                wal_buffers = "16MB";
                min_wal_size = "1GB";
                max_wal_size = "4GB";
                wal_level = "replica";

                # Checkpointing
                checkpoint_completion_target = 0.9;
                checkpoint_timeout = "15min";

                # Query planner
                default_statistics_target = 100;
                random_page_cost = 1.1;
                effective_io_concurrency = 200;

                # Parallel queries
                max_worker_processes = 4;
                max_parallel_workers_per_gather = 2;
                max_parallel_workers = 4;
                max_parallel_maintenance_workers = 2;

                # Replication settings
                hot_standby = "on";
                wal_log_hints = "on";
                max_wal_senders = 10;
                max_replication_slots = 10;
              };
            };
          };

          # Initialize database
          initdb = [
            { encoding = "UTF8"; }
            { locale = "en_US.UTF-8"; }
            { data-checksums = true; }
          ];

          # Host-based authentication
          pg_hba = [
            "local all all peer"
            "host all all 127.0.0.1/32 scram-sha-256"
            "host all all ::1/128 scram-sha-256"
            "host replication replicator 10.42.0.0/16 scram-sha-256"
            "host all all 10.42.0.0/16 scram-sha-256"
          ];
        };

        # PostgreSQL configuration
        postgresql = {
          listen = "${nodeCfg.serviceIp}:5432";
          connect_address = "${nodeCfg.serviceIp}:5432";

          # Explicitly set bin_dir to ensure Patroni finds the correct binaries
          bin_dir = "${pgPackage}/bin";

          authentication = {
            replication = {
              username = "replicator";
            };
            superuser = {
              username = "postgres";
            };
            rewind = {
              username = "rewind";
            };
          };

          parameters = {
            unix_socket_directories = "/run/postgresql";

            # Logging
            logging_collector = "on";
            log_directory = "/var/log/postgresql";
            log_filename = "postgresql-%Y-%m-%d_%H%M%S.log";
            log_rotation_age = "1d";
            log_rotation_size = "100MB";
            log_line_prefix = "%m [%p] %u@%d ";
            log_timezone = "UTC";
          };

          # Replica creation method
          create_replica_methods = [ "basebackup" ];
          basebackup = [
            { checkpoint = "fast"; }
            { max-rate = "100M"; }
          ];
        };

        # Tags for this node
        tags = {
          nofailover = false;
          noloadbalance = false;
          clonefrom = false;
          nosync = false;
        };

        # Watchdog for automatic fencing (optional)
        # watchdog = {
        #   mode = "automatic";
        #   device = "/dev/watchdog";
        #   safety_margin = 5;
        # };
      };
    };

    # Override systemd service to inject environment file
    systemd.services.patroni = {
      after = [ "consul.service" ] ++
              (lib.optional config.services.tailscale.enable "tailscale-online.service");
      wants = lib.optional config.services.tailscale.enable "tailscale-online.service";
      requires = [ "consul.service" ];

      # Add environment file via serviceConfig
      serviceConfig = {
        EnvironmentFile = config.sops.templates."patroni-env".path;
        # Patroni is configured to use /run/postgresql for unix sockets.
        # Systemd must create this directory with the correct permissions.
        RuntimeDirectory = "postgresql";
        RuntimeDirectoryMode = "0755";

        # Explicitly force run as postgres user to override upstream default (patroni)
        User = mkForce "postgres";
        Group = mkForce "postgres";
      };
    };

    # Ensure directories exist with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/log/postgresql 0750 postgres postgres -"
      # Patroni defaults pgpass location here, ensure it exists and is writable by postgres
      "d /var/lib/patroni 0750 postgres postgres -"
    ];
  };
}