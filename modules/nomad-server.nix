{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in
{
  services.nomad = {
    enable = true;
    settings = {
      name = hostName;
      bind_addr = cfg.serviceIp;
      server.enabled = true;
      server.bootstrap_expect = 1;
      client.enabled = false;
      telemetry.publish_allocation_metrics = true;
    };
  };

  services.consul = {
    enable = true;
    extraConfig = {
      node_name = "consul-${hostName}";
      bind_addr = cfg.serviceIp;
      client_addr = "127.0.0.1 ${cfg.serviceIp}";
      server = true;
      bootstrap_expect = 1;
      ui = true;
    };
  };

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      api = true;
      providers.consulCatalog = {
        endpoint.address = "127.0.0.1:8500";
        exposedByDefault = false;
        prefix = "traefik";
      };
      entryPoints = {
        web.address = ":80";
        websecure.address = ":443";
      };
      certificatesResolvers.letsencrypt.acme = {
        storage = "/var/lib/traefik/acme.json";
        httpChallenge.entryPoint = "web";
      };
    };
  };
}