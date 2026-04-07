{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.postgresPrimaryPgbouncer;
  authFilePath = "/run/pgbouncer/users.txt";
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

    serverLifetimeSeconds = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum lifetime of PgBouncer server connections before reconnecting upstream.";
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

    systemd.services.pgbouncer = {
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
    };
  };
}
