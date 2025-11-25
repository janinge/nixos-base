{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = config.cluster.nomad;
  nodeCfg = nodes.${hostName};

  # Helper variables for client configuration
  consulServers = lib.filter (n: n ? "isRegistry" && n.isRegistry) (lib.attrValues nodes);
  consulJoin = lib.map (n: n.serviceIp) consulServers;
in
{
  options.cluster.nomad = {
    server = {
      enable = lib.mkEnableOption "Nomad Server Role";
    };
    client = {
      enable = lib.mkEnableOption "Nomad Client Role";
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
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/nomad 0750 nomad nomad -"
      ];

      services.nomad = {
        enable = true;
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
        extraConfig = {
          node_name = "consul-${hostName}";
          bind_addr = nodeCfg.serviceIp;
          datacenter = "earth";
        };
      };

      environment.variables = {
        NOMAD_ADDR = "http://${nodeCfg.serviceIp}:4646";
      };
    })

    # Server Specific Configuration
    (lib.mkIf cfg.server.enable {
      systemd.services.nomad.after = [ "consul.service" ];

      services.nomad.settings = {
        server = {
          enabled = true;
          bootstrap_expect = 1;
        };
        advertise = {
          http = nodeCfg.serviceIp;
          rpc = nodeCfg.serviceIp;
          serf = nodeCfg.serviceIp;
        };
        client.enabled = false;
        consul = {
          server_service_name = "nomad";
          server_auto_join = true;
        };
      };

      services.consul.extraConfig = {
        client_addr = "127.0.0.1 ${nodeCfg.serviceIp}";
        server = true;
        bootstrap_expect = 1;
        ui_config = {
          enabled = true;
        };
      };

      services.traefik = {
        enable = true;
        staticConfigOptions = {
          api = {
            dashboard = true;
            insecure = false;
          };
          entryPoints = {
            web.address = ":80";
            websecure.address = ":443";
            tailnet.address = "${nodeCfg.serviceIp}:8443";
          };
          providers.consulCatalog = {
            endpoint.address = "127.0.0.1:8500";
            exposedByDefault = false;
            prefix = "traefik";
          };
          certificatesResolvers.letsencrypt.acme = {
            storage = "/var/lib/traefik/acme.json";
            httpChallenge.entryPoint = "web";
          };
        };

        dynamicConfigOptions = {
          http = {
            routers = {
              traefik-dashboard = {
                entryPoints = [ "tailnet" ];
                service = "api@internal";
                rule = "Host(`traefik.h00t.works`)";
                tls = { certResolver = "letsencrypt"; };
              };
              nomad-ui = {
                entryPoints = [ "tailnet" ];
                service = "nomad-ui";
                rule = "Host(`nomad.h00t.works`)";
                tls = { certResolver = "letsencrypt"; };
              };
              consul-ui = {
                entryPoints = [ "tailnet" ];
                service = "consul-ui";
                rule = "Host(`consul.h00t.works`)";
                tls = { certResolver = "letsencrypt"; };
              };
            };
            services = {
              nomad-ui = {
                loadBalancer = {
                  servers = [ { url = "http://127.0.0.1:4646"; } ];
                };
              };
              consul-ui = {
                loadBalancer = {
                  servers = [ { url = "http://127.0.0.1:8500"; } ];
                };
              };
            };
          };
        };
      };
    })

    # Client Specific Configuration
    (lib.mkIf cfg.client.enable {
      services.nomad.extraSettingsPlugins = [ pkgs.nomad-driver-podman ];

      services.nomad.settings = {
        plugin."nomad-driver-podman" = {
          config = { };
        };

        client = {
          enabled = true;
          cni_config_dir = "/etc/cni/net.d";
          options = {
            "driver.denylist" = "docker";
          };
        };
        server.enabled = false;

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
        server = false;
        retry_join = consulJoin;
        dns_config = { allow_stale = true; node_ttl = "15s"; };
        autopilot.cleanup_dead_servers = true;
      };

      virtualisation.podman = {
        enable = true;
        dockerCompat = false;
        defaultNetwork.settings.dns_enabled = false;
      };

      virtualisation.docker.enable = lib.mkForce false;

      # Fix the duplicate ListenStream entries by clearing first
      systemd.sockets.podman.socketConfig = {
        ListenStream = lib.mkForce [ "" "/run/podman/podman.sock" ];
        SocketMode = "0660";
        SocketGroup = "podman";
      };

      # Keep the Podman service running
      systemd.services.podman = {
        wantedBy = [ "multi-user.target" ];
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
        nomad-driver-podman
        cni-plugins
        podman
        podman-tui
        dive
      ];
    })
  ];
}