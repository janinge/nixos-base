{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.postgresPrimaryPgbouncer;
  authFilePath = "/run/pgbouncer/users.txt";
  usesLocalCorednsPath =
    config.services.coredns.enable
    && builtins.elem "127.0.0.1" config.networking.nameservers;
  localDnsDependencies =
    optional config.services.coredns.enable "coredns.service"
    ++ optional config.services.consul.enable "consul.service";
  renderUserEntry = username: userCfg: ''
    username=${escapeShellArg username}
    password_file=${escapeShellArg (toString userCfg.passwordFile)}
    password="$(<"$password_file")"

    if [ -z "$password" ]; then
      echo "PgBouncer password for '$username' must not be empty." >&2
      exit 1
    fi

    case "$username" in
      *$'\n'*|*$'\r'*)
        echo "PgBouncer username '$username' must not contain newlines." >&2
        exit 1
        ;;
    esac

    case "$password" in
      *$'\n'*|*$'\r'*)
        echo "PgBouncer password for '$username' must not contain newlines." >&2
        exit 1
        ;;
    esac

    escaped_username=''${username//\\/\\\\}
    escaped_username=''${escaped_username//\"/\\\"}
    escaped_password=''${password//\\/\\\\}
    escaped_password=''${escaped_password//\"/\\\"}

    printf '"%s" "%s"\n' "$escaped_username" "$escaped_password" >> "$tmp_auth_file"
  '';
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

    defaultPoolSize = mkOption {
      type = types.int;
      default = 4;
      description = "Maximum number of pooled upstream PostgreSQL server connections per user/database pair.";
    };

    maxClientConnections = mkOption {
      type = types.int;
      default = 32;
      description = "Maximum number of client connections PgBouncer accepts.";
    };

    queryWaitTimeoutSeconds = mkOption {
      type = types.int;
      default = 10;
      description = "Maximum time a client query waits for an available upstream PostgreSQL server connection.";
    };

    serverResetQuery = mkOption {
      type = types.str;
      default = "";
      description = "Query used to clean a PostgreSQL server connection before reuse.";
    };

    serverResetQueryAlways = mkOption {
      type = types.bool;
      default = false;
      description = "Whether PgBouncer runs serverResetQuery in all pooling modes.";
    };

    serverLifetimeSeconds = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum lifetime of PgBouncer server connections before reconnecting upstream.";
    };

    serverLoginRetrySeconds = mkOption {
      type = types.int;
      default = 5;
      description = ''
        Seconds PgBouncer waits before retrying upstream server login after a
        failure.
      '';
    };

    dnsMaxTtlSeconds = mkOption {
      type = types.int;
      default = 5;
      description = "Maximum TTL for cached DNS answers inside PgBouncer.";
    };

    dnsNxdomainTtlSeconds = mkOption {
      type = types.int;
      default = 5;
      description = "Maximum TTL for cached negative DNS answers inside PgBouncer.";
    };

    dnsZoneCheckPeriodSeconds = mkOption {
      type = types.int;
      default = 30;
      description = ''
        Period for PgBouncer SOA checks when built with c-ares, used to detect
        DNS changes sooner than normal TTL expiry.
      '';
    };

    logConnections = mkOption {
      type = types.bool;
      default = false;
      description = "Whether PgBouncer logs every successful client connection.";
    };

    logDisconnections = mkOption {
      type = types.bool;
      default = false;
      description = "Whether PgBouncer logs every client disconnection.";
    };

    logPoolerErrors = mkOption {
      type = types.bool;
      default = true;
      description = "Whether PgBouncer logs pooler errors.";
    };

    users = mkOption {
      type = types.attrsOf (types.submodule ({ ... }: {
        options = {
          passwordFile = mkOption {
            type = types.str;
            description = ''
              Path to a file containing the shared password for this PgBouncer
              user. PgBouncer uses this password both to authenticate incoming
              clients and to connect upstream to PostgreSQL as the same user.
            '';
          };
        };
      }));
      default = { };
      description = "Users allowed to connect through the local PgBouncer endpoint.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.users != { };
        message = "services.postgresPrimaryPgbouncer.enable requires at least one user in services.postgresPrimaryPgbouncer.users.";
      }
    ];

    services.pgbouncer = {
      enable = true;
      settings = {
        pgbouncer = {
          auth_type = "scram-sha-256";
          auth_file = authFilePath;
          default_pool_size = cfg.defaultPoolSize;
          dns_max_ttl = cfg.dnsMaxTtlSeconds;
          dns_nxdomain_ttl = cfg.dnsNxdomainTtlSeconds;
          dns_zone_check_period = cfg.dnsZoneCheckPeriodSeconds;
          listen_addr = cfg.listenAddress;
          listen_port = cfg.listenPort;
          log_connections = if cfg.logConnections then 1 else 0;
          log_disconnections = if cfg.logDisconnections then 1 else 0;
          log_pooler_errors = if cfg.logPoolerErrors then 1 else 0;
          max_client_conn = cfg.maxClientConnections;
          pool_mode = cfg.poolMode;
          query_wait_timeout = cfg.queryWaitTimeoutSeconds;
          server_login_retry = cfg.serverLoginRetrySeconds;
          server_lifetime = cfg.serverLifetimeSeconds;
          server_reset_query = cfg.serverResetQuery;
          server_reset_query_always = if cfg.serverResetQueryAlways then 1 else 0;
          ignore_startup_parameters = "extra_float_digits,prefer_simple_protocol";
        };
        databases = {
          "*" = "host=${cfg.upstreamHost} port=${toString cfg.upstreamPort}";
        };
      };
    };

    systemd.services.pgbouncer = mkMerge [
      {
        preStart = ''
          tmp_auth_file="$(${pkgs.coreutils}/bin/mktemp /run/pgbouncer/users.txt.XXXXXX)"
          trap '${pkgs.coreutils}/bin/rm -f "$tmp_auth_file"' EXIT

          : > "$tmp_auth_file"
${concatStringsSep "\n" (mapAttrsToList renderUserEntry cfg.users)}
          ${pkgs.coreutils}/bin/chown ${escapeShellArg config.services.pgbouncer.user}:${escapeShellArg config.services.pgbouncer.group} "$tmp_auth_file"
          ${pkgs.coreutils}/bin/chmod 0400 "$tmp_auth_file"
          ${pkgs.coreutils}/bin/mv "$tmp_auth_file" ${escapeShellArg authFilePath}
          trap - EXIT
        '';

        serviceConfig.PermissionsStartOnly = true;
      }
      (mkIf usesLocalCorednsPath {
        after = localDnsDependencies;
        wants = localDnsDependencies;
      })
    ];
  };
}
