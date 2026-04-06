{ config, lib, ... }:

with lib;

let
  cfg = config.services.postgresPrimaryPgbouncer;
in
{
  options.services.postgresPrimaryPgbouncer = {
    enable = mkEnableOption "local PgBouncer endpoint for PostgreSQL primary clients";

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address where the local PgBouncer listener binds.";
    };

    listenPort = mkOption {
      type = types.port;
      default = 6432;
      description = "Port where the local PgBouncer listener accepts client connections.";
    };

    upstreamHost = mkOption {
      type = types.str;
      default = "primary.postgres-cluster.service.consul";
      description = "Writer endpoint hostname used by PgBouncer for outbound PostgreSQL connections.";
    };

    upstreamPort = mkOption {
      type = types.port;
      default = 5432;
      description = "Writer endpoint port used by PgBouncer for outbound PostgreSQL connections.";
    };

    poolMode = mkOption {
      type = types.enum [ "session" "transaction" "statement" ];
      default = "transaction";
      description = "PgBouncer pool mode used for local PostgreSQL-primary clients.";
    };

    serverLifetimeSeconds = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum lifetime of PgBouncer server connections before reconnecting upstream.";
    };
  };

  config = mkIf cfg.enable {
    services.pgbouncer = {
      enable = true;
      settings = {
        pgbouncer = {
          auth_type = "trust";
          listen_addr = cfg.listenAddress;
          listen_port = cfg.listenPort;
          pool_mode = cfg.poolMode;
          server_lifetime = cfg.serverLifetimeSeconds;
        };
        databases = {
          "*" = "host=${cfg.upstreamHost} port=${toString cfg.upstreamPort}";
        };
      };
    };
  };
}
