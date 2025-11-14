{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in
{
  imports = [ ./nomad.nix ];

  systemd.services.nomad.after = [ "consul.service" ];

  services.nomad.settings = lib.mkMerge [
    {
      server = {
        enabled = true;
        bootstrap_expect = 1;
      };
      advertise = {
        http = cfg.serviceIp;
        rpc = cfg.serviceIp;
        serf = cfg.serviceIp;
      };
      client.enabled = false;
      consul = {
        server_service_name = "nomad";
        server_auto_join = true;
      };
    }
  ];

  services.consul.extraConfig = lib.mkMerge [
    {
      client_addr = "127.0.0.1 ${cfg.serviceIp}";
      server = true;
      bootstrap_expect = 1;
      ui_config = {
        enabled = true;
      };
    }
  ];

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

        tailnet.address = "${cfg.serviceIp}:443";
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
              servers = [
                { url = "http://127.0.0.1:4646"; }
              ];
            };
          };

          consul-ui = {
            loadBalancer = {
              servers = [
                { url = "http://127.0.0.1:8500"; }
              ];
            };
          };
        };

      };
    };
  };
}