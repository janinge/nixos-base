{ config, pkgs, lib, nodes, hostName, pkgs-unstable, ... }:
let
  cfg = config.cluster.nomad;
  nodeCfg = nodes.${hostName};

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

      jobSecrets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of SOPS secret names to distribute to this Nomad client. They will be readable by the nomad user for use in deployment templates.";
        example = [ "authentik.env" "postgres.env" ];
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
          "shared-fs" = { path = "/mnt/seaweedfs"; createDir = false; };
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
        extraGroups = [ "podman" ];
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
        "d /var/lib/alloc_mounts 0755 nomad nomad -"
      ];

      # Ensure Nomad and Consul start after Tailscale is fully online
      systemd.services.nomad = {
        after = lib.optional config.services.tailscale.enable "tailscale-online.service"
          # Wait for SeaweedFS mount if it is enabled on this host
          ++ lib.optional (config.services.seaweedfs.mount != null) "seaweedfs-mount.service";

        wants = lib.optional config.services.tailscale.enable "tailscale-online.service"
          ++ lib.optional (config.services.seaweedfs.mount != null) "seaweedfs-mount.service";

        serviceConfig = {
          Restart = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "10s";
          StartLimitIntervalSec = lib.mkForce 0;
        };
      };

      systemd.services.consul = {
        after = lib.optional config.services.tailscale.enable "tailscale-online.service";
        wants = lib.optional config.services.tailscale.enable "tailscale-online.service";
      };

      services.nomad = {
        enable = true;
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

      # Inject credentials into Traefik
      systemd.services.traefik.serviceConfig = {
        EnvironmentFile = [ config.sops.templates."traefik-aws.env".path ];
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
          entryPoints = {
            web.address = ":80";
            websecure.address = ":443";
            tailnet.address = "${nodeCfg.serviceIp}:8443";
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
              delayBeforeCheck = 60;
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
              authentik = {
                forwardAuth = {
                  address = "https://auth.h00t.works/outpost.goauthentik.io/auth/traefik";
                  trustForwardHeader = true;
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
        };
      };
    })

    # Client specific configuration
    (lib.mkIf cfg.client.enable {
      services.nomad.extraSettingsPlugins = [ pkgs-unstable.nomad-driver-podman ];

      # Generates sops.secrets for items passed in the list
      sops.secrets = lib.genAttrs cfg.client.jobSecrets (secretName: {
        owner = "nomad";
        group = "nomad";
        mode = "0440";
      });

      # Create directories for host volumes that request it
      # Owned by nomad:nomad because Nomad runs as user 'nomad'
      systemd.tmpfiles.rules = lib.mapAttrsToList (name: vol:
        "d ${vol.path} 0755 nomad nomad -"
      ) (lib.filterAttrs (n: v: v.createDir) cfg.client.hostVolumes);

      services.nomad.settings = {
        plugin."nomad-driver-podman" = {
          config = { };
        };

        client = {
          enabled = true;
          node_class = nodeCfg.datacenter;
          cni_config_dir = "/etc/cni/net.d";
          network_interface = nodeCfg.serviceBridge;
          options = {
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
          };

          # Node metadata for use in job constraint/affinity filtering
          meta = {
            service_ip = nodeCfg.serviceIp;
            service_bridge = nodeCfg.serviceBridge;
            public_if = nodeCfg.publicIf;
            routed_subnet = nodeCfg.routedSubnet;
            datacenter = nodeCfg.datacenter;
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
            ipMasq = true;
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

      services.consul.extraConfig = {
        retry_join = lib.filter (ip: ip != nodeCfg.serviceIp) consulJoin;
        dns_config = { allow_stale = true; node_ttl = "15s"; };
        autopilot.cleanup_dead_servers = true;
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

      services.prometheus.exporters.node.enable = true;
      services.cadvisor = {
        enable = true;
        listenAddress = "0.0.0.0";
      };

      environment.systemPackages = with pkgs; [
        pkgs-unstable.nomad-driver-podman
        passt
        cni-plugins
        podman
        podman-tui
        dive
        jq
      ];
    })
  ];
}
