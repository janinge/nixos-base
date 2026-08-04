{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = config.cluster.nomad;
  nodeCfg = nodes.${hostName};
  isPodmanClient = cfg.client.enable && cfg.client.runtime == "podman";
  isKataDockerClient = cfg.client.enable && cfg.client.runtime == "kata-docker";

  # Rootless containers create files in allocation directories using subordinate
  # host UIDs.  Nomad runs outside that user namespace and cannot traverse (and
  # therefore GC) directories such as a container-owned mode 0700 data dir.
  # Reap only old allocation directories which the server no longer considers
  # live.  The API checks deliberately fail closed: an unavailable or malformed
  # response leaves every directory untouched.
  nomadAllocReaper = pkgs.writeShellApplication {
    name = "nomad-allocation-reaper";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.findutils pkgs.gnugrep pkgs.jq ];
    text = ''
      set -o errexit -o nounset -o pipefail

      alloc_root=/var/lib/nomad/alloc
      minimum_age_minutes=60
      nomad_addr="''${NOMAD_ADDR:-http://${nodeCfg.serviceIp}:4646}"
      export NOMAD_ADDR="$nomad_addr"
      dry_run=false

      case "''${1:-}" in
        --dry-run) dry_run=true ;;
        "") ;;
        *) echo "usage: nomad-allocation-reaper [--dry-run]" >&2; exit 2 ;;
      esac

      test -d "$alloc_root" || exit 0

      work_dir=$(mktemp -d)
      trap 'rm -rf "$work_dir"' EXIT

      node_id=$(< /var/lib/nomad/client/client-id)
      if ! [[ "$node_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo "Invalid Nomad client ID; refusing allocation cleanup" >&2
        exit 1
      fi
      curl --fail --silent --show-error \
        "$nomad_addr/v1/node/$node_id/allocations" > "$work_dir/allocations.json"
      jq -e 'type == "array"' "$work_dir/allocations.json" >/dev/null

      # DesiredStatus=run must always win, including allocations temporarily in
      # unknown state during a network partition.  Also retain every allocation
      # whose client state is not terminal.
      jq -r '.[]
        | select(.DesiredStatus == "run"
          or (.ClientStatus != "complete"
            and .ClientStatus != "failed"
            and .ClientStatus != "lost"))
        | .ID' "$work_dir/allocations.json" > "$work_dir/live-allocations"

      find "$alloc_root" -mindepth 1 -maxdepth 1 -type d \
        -mmin "+$minimum_age_minutes" -print0 |
        while IFS= read -r -d "" allocation_dir; do
          allocation_id="''${allocation_dir##*/}"

          # Never operate on unexpected names, even under the dedicated root.
          if ! [[ "$allocation_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
            echo "Ignoring unexpected allocation directory: $allocation_dir" >&2
            continue
          fi

          if grep --fixed-strings --line-regexp --quiet "$allocation_id" "$work_dir/live-allocations"; then
            continue
          fi

          if [[ "$dry_run" == true ]]; then
            echo "Would remove stale allocation directory: $allocation_dir"
          else
            echo "Removing stale allocation directory: $allocation_dir"
            find "$allocation_dir" -xdev -depth -delete
          fi
        done
    '';
  };

  # Helper variables for client configuration
  consulServers = lib.filter (n: n ? "isRegistry" && n.isRegistry) (lib.attrValues nodes);
  consulJoin = lib.map (n: n.serviceIp) consulServers;

  serverCount = lib.length consulServers;

  wildcardTls = {
    certResolver = "letsencrypt";
    domains = [{
      main = "h00t.works";
      sans = [ "*.h00t.works" ];
    }];
  };

  wildcardTlsCf = {
    certResolver = "cloudflare";
    domains = [{
      main = "smbergen.no";
      sans = [ "*.smbergen.no" ];
    }];
  };
in
{
  options.cluster.nomad = {
    server = {
      enable = lib.mkEnableOption "Nomad Server Role";
      gateway = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = nodeCfg.isGateway or false;
          description = "Enable edge gateway role (Traefik)";
        };
      };
    };
    client = {
      enable = lib.mkEnableOption "Nomad Client Role";

      runtime = lib.mkOption {
        type = lib.types.enum [ "podman" "kata-docker" ];
        default = "podman";
        description = ''
          Container runtime path used by this Nomad client. The default keeps
          the existing rootless Podman driver behavior; kata-docker enables
          Nomad's built-in Docker driver with the Kata containerd shim runtime.
        '';
      };

      snat = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Masquerade job egress to the host's identity via the CNI bridge
          (ipMasq). When false, job traffic keeps its routed-subnet source IP
          across the tailnet so it can be matched by egress policy / Headscale
          ACLs; Internet egress is still NAT'd via the public interface. Set
          false on nodes running untrusted workloads.
        '';
      };

      dynamicPorts = {
        from = lib.mkOption {
          type = lib.types.port;
          default = 50000;
          description = "First port in the Nomad client dynamic allocation range.";
        };

        to = lib.mkOption {
          type = lib.types.port;
          default = 51000;
          description = "Last port in the Nomad client dynamic allocation range.";
        };
      };

      jobSecrets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of SOPS secret names to distribute to this Nomad client. They will be readable by the nomad user for use in deployment templates.";
        example = [ "authentik.env" "postgres.env" ];
      };

      jobSecretsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "SOPS secrets file to use for all jobSecrets on this node. When null, the host's sops.defaultSopsFile is used.";
        example = ../secrets/kata.yaml;
      };

      hostVolumes = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Path on the host system";
            };
            readOnly = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Mount volume as read-only";
            };
            createDir = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Automatically create the directory if it doesn't exist";
            };
          };
        });
        default = {};
        description = "Nomad host volumes configuration";
        example = {
          "local-data" = { path = "/var/lib/nomad-vols/data"; };
          "shared-fs" = { path = "/mnt/shared"; createDir = false; };
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.server.enable || cfg.client.enable) {
      users.groups.nomad = {};
      users.users.nomad = {
        isSystemUser = true;
        group = "nomad";
        extraGroups = lib.optional isPodmanClient "podman";
        home = "/var/lib/nomad";
        description = "Nomad service user";
        linger = true;

        subUidRanges = [
          { startUid = 100000; count = 65536; }
        ];
        subGidRanges = [
          { startGid = 100000; count = 65536; }
        ];
      };

      sops.secrets.nomad_gossip_key = {
        owner = "nomad";
        restartUnits = [ "nomad.service" ];
      };
      sops.secrets.consul_gossip_key = {
        owner = "consul";
        restartUnits = [ "consul.service" ];
      };

      sops.templates."nomad-secrets.json" = {
        content = ''{ "server": { "encrypt": "${config.sops.placeholder.nomad_gossip_key}" } }'';
        owner = "nomad";
        group = "nomad";
        mode = "0440";
      };

      sops.templates."consul-secrets.json" = {
        content = ''{ "encrypt": "${config.sops.placeholder.consul_gossip_key}" }'';
        owner = "consul";
        group = "consul";
        mode = "0440";
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/nomad 0750 nomad nomad -"
        # A client may previously have run as root (for example with the
        # Kata/Docker runtime). Reconcile Nomad-owned state when returning to
        # the unprivileged Podman client. Do not recursively chown alloc/:
        # task files can intentionally use container namespace ownership.
        "d /var/lib/nomad/client 0700 nomad nomad -"
        "Z /var/lib/nomad/client - nomad nomad -"
        "z /var/lib/nomad/client/state.db 0600 nomad nomad -"
        "d /var/lib/nomad/alloc 0711 nomad nomad -"
        "d /var/lib/nomad/.cache 0700 nomad nomad -"
        "Z /var/lib/nomad/.cache - nomad nomad -"
        "d /var/lib/nomad/.config 0700 nomad nomad -"
        "Z /var/lib/nomad/.config - nomad nomad -"
        "d /var/lib/nomad/.local 0700 nomad nomad -"
        "Z /var/lib/nomad/.local - nomad nomad -"
        "d /var/lib/alloc_mounts 0755 nomad nomad -"
      ];

      # Ensure Nomad and Consul start after Tailscale is fully online
      systemd.services.nomad = {
        after = lib.optional config.services.tailscale.enable "tailscale-online.service";

        wants = lib.optional config.services.tailscale.enable "tailscale-online.service";

        unitConfig = {
          StartLimitIntervalSec = lib.mkForce 0;
        };

        serviceConfig = {
          Restart = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "10s";
        };
      };

      systemd.services.consul = {
        after = lib.optional config.services.tailscale.enable "tailscale-online.service";
        wants = lib.optional config.services.tailscale.enable "tailscale-online.service";
      };

      services.nomad = {
        enable = true;
        enableDocker = isKataDockerClient;
        extraSettingsPaths = [ config.sops.templates."nomad-secrets.json".path ];
        settings = {
          name = hostName;
          data_dir = "/var/lib/nomad";
          bind_addr = nodeCfg.serviceIp;
          telemetry.publish_allocation_metrics = true;
          datacenter = "earth";
          consul = {
            address = "127.0.0.1:8500";
            auto_advertise = true;
          };
          client = {
            cni_path = "${pkgs.cni-plugins}/bin";
          };
        };
      };

      services.consul = {
        enable = true;
        extraConfigFiles = [ config.sops.templates."consul-secrets.json".path ];
        extraConfig = {
          node_name = "consul-${hostName}";
          bind_addr = nodeCfg.serviceIp;
          datacenter = "earth";
          node_meta = {
            site = nodeCfg.datacenter;
            host = hostName;
          };
        };
      };

      environment.variables = {
        NOMAD_ADDR = "http://${nodeCfg.serviceIp}:4646";
      };
    })

    # Server specific configuration
    (lib.mkIf cfg.server.enable {
      systemd.services.nomad.after = [ "consul.service" ];

      services.nomad.settings = {
        server = {
          enabled = true;
          bootstrap_expect = serverCount;
          raft_multiplier = 5;
          heartbeat_grace = "1m";
          # Configure Nomad to directly join peers if Consul discovery isn't ready yet
          server_join = {
            retry_join = lib.filter (ip: ip != nodeCfg.serviceIp) consulJoin;
            retry_max = 0;
            retry_interval = "15s";
          };
        };
        advertise = {
          http = nodeCfg.serviceIp;
          rpc = nodeCfg.serviceIp;
          serf = nodeCfg.serviceIp;
        };
        consul = {
          server_service_name = "nomad";
          server_auto_join = true;
        };
      };

      services.consul.extraConfig = {
        client_addr = "127.0.0.1 ${nodeCfg.serviceIp}";
        server = true;
        bootstrap_expect = serverCount;
        retry_join = lib.filter (ip: ip != nodeCfg.serviceIp) consulJoin;
        ui_config = {
          enabled = true;
        };
        performance = {
          raft_multiplier = 5;
        };
      };
    })

    # Gateway specific configuration (Traefik)
    (lib.mkIf cfg.server.gateway.enable {
      sops.secrets.aws_route53_access_key_id = {
        owner = "traefik";
        restartUnits = [ "traefik.service" ];
      };
      sops.secrets.aws_route53_secret_access_key = {
        owner = "traefik";
        restartUnits = [ "traefik.service" ];
      };
      sops.secrets.acme_email = {
        owner = "traefik";
        restartUnits = [ "traefik.service" ];
      };
      sops.secrets.cloudflare_api_token = {
        owner = "traefik";
        restartUnits = [ "traefik.service" ];
      };

      sops.templates."traefik-aws.env" = {
        content = ''
          AWS_ACCESS_KEY_ID=${config.sops.placeholder.aws_route53_access_key_id}
          AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.aws_route53_secret_access_key}
          AWS_REGION=us-east-1
          AWS_HOSTED_ZONE_ID=Z00024711XAQWYV6Y3F0V
          TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${config.sops.placeholder.acme_email}
        '';
        owner = "traefik";
      };
      sops.templates."traefik-cf.env" = {
        content = ''
          CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_api_token}
          TRAEFIK_CERTIFICATESRESOLVERS_CLOUDFLARE_ACME_EMAIL=${config.sops.placeholder.acme_email}
        '';
        owner = "traefik";
      };

      # Inject credentials into Traefik
      systemd.services.traefik.serviceConfig = {
        EnvironmentFile = [
          config.sops.templates."traefik-aws.env".path
          config.sops.templates."traefik-cf.env".path
        ];
      };

      services.traefik = {
        enable = true;
        staticConfigOptions = {
          log = {
            level = "INFO";
          };
          accessLog = {};
          api = {
            dashboard = true;
            insecure = false;
          };
          tls = {
            options = {
              default = {
                minVersion = "VersionTLS13";
                sniStrict = true;

                curvePreferences = [
                  "CurveP521"
                  "CurveP384"
                  "CurveP256"
                ];
              };
            };
          };
          entryPoints = let
            encodedCharacters = {
              allowEncodedSlash = false;
              allowEncodedBackSlash = false;
              allowEncodedNullCharacter = false;
              allowEncodedSemicolon = false;
              allowEncodedPercent = false;
              allowEncodedQuestionMark = false;
              allowEncodedHash = false;
            };
            httpOptions = {
              sanitizePath = true;
              inherit encodedCharacters;
            };
          in {
            web = {
              address = ":80";
              http = httpOptions;
            };
            websecure = {
              address = ":443";
              http = httpOptions;
            };
            smtp.address = ":25";
            submission.address = ":587";
            smtps.address = ":465";
            imaps.address = ":993";
            tailnet = {
              address = "${nodeCfg.serviceIp}:8443";
              http = httpOptions;
            };
          };
          providers.consulCatalog = {
            endpoint.address = "127.0.0.1:8500";
            exposedByDefault = false;
            watch = true;
          };
          certificatesResolvers.letsencrypt.acme = {
            storage = "/var/lib/traefik/acme.json";
            dnsChallenge = {
              provider = "route53";
              propagation = {
                delayBeforeChecks = "60s";
              };
            };
          };
          certificatesResolvers.cloudflare.acme = {
            storage = "/var/lib/traefik/acme-cloudflare.json";
            dnsChallenge = {
              provider = "cloudflare";
              propagation = {
                delayBeforeChecks = "60s";
              };
            };
          };
        };

        dynamicConfigOptions = {
          http = {
            routers = {
              traefik-dashboard = {
                entryPoints = [ "tailnet" ];
                service = "api@internal";
                rule = "Host(`traefik.h00t.works`)";
                tls = wildcardTls;
              };
              nomad-ui = {
                entryPoints = [ "tailnet" ];
                service = "nomad-ui";
                rule = "Host(`nomad.h00t.works`)";
                tls = wildcardTls;
              };
              consul-ui = {
                entryPoints = [ "tailnet" ];
                service = "consul-ui";
                rule = "Host(`consul.h00t.works`)";
                tls = wildcardTls;
              };
            };
            services = {
              nomad-ui = {
                loadBalancer = {
                  servers = [ { url = "http://${nodeCfg.serviceIp}:4646"; } ];
                };
              };
              consul-ui = {
                loadBalancer = {
                  servers = [ { url = "http://127.0.0.1:8500"; } ];
                };
              };
            };
            middlewares = {
              hsts = {
                headers = {
                  stsSeconds = 63072000;
                  stsIncludeSubdomains = true;
                  stsPreload = true;

                  contentTypeNosniff = true;
                  browserXssFilter = true;
                  frameDeny = true;

                  referrerPolicy = "strict-origin-when-cross-origin";
                  permissionsPolicy = "camera=(), microphone=(), geolocation=()";
                };
              };
              stalwart-cors = {
                headers = {
                  accessControlAllowOriginList = [
                    "https://webmail.h00t.works"
                    "https://www.h00tmail.com"
                  ];
                  accessControlAllowMethods = [
                    "GET"
                    "POST"
                    "OPTIONS"
                  ];
                  accessControlAllowHeaders = [
                    "Authorization"
                    "Content-Type"
                    "Accept"
                  ];
                  accessControlAllowCredentials = true;
                  addVaryHeader = true;
                };
              };
              authentik = {
                forwardAuth = {
                  address = "https://auth.h00t.works/outpost.goauthentik.io/auth/traefik";
                  trustForwardHeader = true;
                  maxResponseBodySize = 1048576;
                  authResponseHeaders = [
                    "X-authentik-username"
                    "X-authentik-groups"
                    "X-authentik-email"
                    "X-authentik-name"
                    "X-authentik-uid"
                    "X-authentik-jwt"
                    "X-authentik-meta-jwks"
                    "X-authentik-meta-outpost"
                    "X-authentik-meta-provider"
                    "X-authentik-meta-app"
                    "X-authentik-meta-version"
                  ];
                };
              };
            };
          };
          tcp.serversTransports = {
            proxyprotocolv2 = {
              proxyProtocol.version = 2;
            };
          };
        };
      };
    })

    # Client specific configuration
    (lib.mkIf cfg.client.enable {
      # Generates sops.secrets for items passed in the list
      sops.secrets = lib.genAttrs cfg.client.jobSecrets (secretName: {
        owner = "nomad";
        group = "nomad";
        mode = "0440";
      } // lib.optionalAttrs (cfg.client.jobSecretsFile != null) {
        sopsFile = cfg.client.jobSecretsFile;
      });

      # Create directories for host volumes that request it
      # Owned by nomad:nomad because Nomad runs as user 'nomad'
      systemd.tmpfiles.rules = lib.mapAttrsToList (name: vol:
        "d ${vol.path} 0755 nomad nomad -"
      ) (lib.filterAttrs (n: v: v.createDir) cfg.client.hostVolumes);

      services.nomad.settings = {
        client = {
          enabled = true;
          min_dynamic_port = cfg.client.dynamicPorts.from;
          max_dynamic_port = cfg.client.dynamicPorts.to;
          node_class = nodeCfg.datacenter;
          cni_config_dir = "/etc/cni/net.d";
          bridge_network_name = nodeCfg.serviceBridge;
          bridge_network_subnet = nodeCfg.routedSubnet;
          network_interface = nodeCfg.serviceBridge;
          options = lib.optionalAttrs (!isKataDockerClient) {
            "driver.denylist" = "docker";
          };

          # Allow Nomad templates to read outside the task directory on the host natively
          template = {
            disable_file_sandbox = true;
          };

          # Map configured host volumes to Nomad settings
          host_volume = lib.mapAttrs (name: vol: {
            path = vol.path;
            read_only = vol.readOnly;
          }) cfg.client.hostVolumes;

          host_network = {
            service = {
              cidr = "${nodeCfg.serviceIp}/32";
              interface = nodeCfg.serviceBridge;
            };
          } // lib.optionalAttrs (config.cluster.publicFirewall.enable && nodeCfg.publicIf != null) {
            public = {
              interface = nodeCfg.publicIf;
            };
          };

          # Node metadata for use in job constraint/affinity filtering
          meta = {
            service_ip = nodeCfg.serviceIp;
            service_bridge = nodeCfg.serviceBridge;
            public_if = nodeCfg.publicIf;
            routed_subnet = nodeCfg.routedSubnet;
            datacenter = nodeCfg.datacenter;
            site = nodeCfg.datacenter;
            container_runtime = cfg.client.runtime;
            # Scheduling tier: primary | secondary | overflow. Applied to every
            # client regardless of runtime, so both Podman and Kata nodes carry
            # it. Jobs use it via affinity to prefer primary and treat overflow
            # nodes as last-resort spill-over.
            tier = nodeCfg.tier or "primary";
          };
        };

        advertise = {
          http = nodeCfg.serviceIp;
          rpc = nodeCfg.serviceIp;
          serf = nodeCfg.serviceIp;
        };

        consul = {
          client_auto_join = true;
        };
      };

      environment.etc."cni/net.d/nomad.conflist".text = lib.generators.toJSON {} {
        cniVersion = "0.4.0";
        name = "nomad";
        plugins = [
          {
            type = "bridge";
            bridge = nodeCfg.serviceBridge;
            ipMasq = cfg.client.snat;
            ipam = {
              type = "host-local";
              subnet = nodeCfg.routedSubnet;
              routes = [ { dst = "0.0.0.0/0"; } ];
            };
          }
          { type = "firewall"; }
          {
            type = "portmap";
            capabilities = { portMappings = true; };
          }
        ];
      };

      # With SNAT disabled the CNI bridge no longer masquerades job egress, so
      # job traffic to the public Internet would leave with an unroutable
      # routed-subnet source. networking.nat only masquerades traffic exiting
      # the externalInterface (the public NIC), so adding the service bridge
      # here restores Internet egress while leaving tailnet (tailscale0)
      # traffic un-NATed — preserving job source IPs across the mesh. Relies on
      # the host having networking.nat.{enable,externalInterface} set.
      networking.nat.internalInterfaces =
        lib.mkIf (!cfg.client.snat) [ nodeCfg.serviceBridge ];

      services.consul.extraConfig = {
        retry_join = lib.filter (ip: ip != nodeCfg.serviceIp) consulJoin;
        dns_config = { allow_stale = true; node_ttl = "15s"; };
        autopilot.cleanup_dead_servers = true;
      };

      virtualisation.docker.enable = lib.mkIf (!isKataDockerClient) (lib.mkForce false);

      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = nodeCfg.serviceIp;
      };
      services.cadvisor = {
        enable = true;
        listenAddress = nodeCfg.serviceIp;
      };

      environment.systemPackages = with pkgs; [
        cni-plugins
        jq
      ];
    })

    # Existing rootless Podman workload path. Kata clients use a separate
    # containerd driver path so the Podman driver model stays unchanged.
    (lib.mkIf isPodmanClient {
      # Nomad cannot remove allocation files owned by UIDs in the rootless
      # Podman subordinate-ID mapping.  Run a conservative privileged fallback
      # after Nomad's own GC has had time to remove terminal allocations.
      systemd.services.nomad-allocation-reaper = {
        description = "Remove stale rootless-Podman Nomad allocation directories";
        after = [ "nomad.service" ];
        wants = [ "nomad.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe nomadAllocReaper;
          User = "root";
          Group = "root";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/nomad/alloc" ];
        };
      };

      systemd.timers.nomad-allocation-reaper = {
        description = "Periodically remove stale Nomad allocation directories";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "15m";
          OnUnitActiveSec = "6h";
          RandomizedDelaySec = "5m";
          Persistent = true;
        };
      };

      services.nomad.extraSettingsPlugins = [ pkgs.nomad-driver-podman ];

      services.nomad.settings = {
        plugin."nomad-driver-podman" = {
          config = { };
        };
      };

      virtualisation.podman = {
        enable = true;
        dockerCompat = false;
        defaultNetwork.settings.dns_enabled = true;
      };

      virtualisation.docker.enable = lib.mkForce false;

      # Fix the duplicate ListenStream entries by clearing first
      systemd.sockets.podman.socketConfig = {
        ListenStream = lib.mkForce [ "" "/run/podman/podman.sock" ];
        SocketMode = "0660";
        SocketGroup = "podman";
      };

      systemd.services.nomad = {
        serviceConfig = {
          User = "nomad";
          Group = "nomad";
          SupplementaryGroups = lib.mkForce [ "podman" ];
          DynamicUser = lib.mkForce false;

          ProtectSystem = "full";
          ProtectHome = false;
          PrivateTmp = true;
          NoNewPrivileges = false;

          # CAP_NET_ADMIN is needed for CNI network creation
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" "CAP_SYS_ADMIN" ];
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
        };
      };

      environment.systemPackages = with pkgs; [
        nomad-driver-podman
        passt
        podman
        podman-tui
        dive
      ];
    })
  ];
}
