{ config, pkgs, lib, ... }:

{
  services.nomad = {
    enable = true;
    settings = {
      datacenter = "osl1";
      name = config.networking.hostName;
      bind_addr = "0.0.0.0";
      server.enabled = true;
      server.bootstrap_expect = 1;
      client.enabled = false;
      telemetry.publish_allocation_metrics = true;
    };
  };

  services.consul = {
    enable = true;
    extraConfig = {
      datacenter = "osl1";
      node_name = "consul-${config.networking.hostName}";
      bind_addr = "0.0.0.0";
      client_addr = "0.0.0.0";
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
        endpoint = "127.0.0.1:8500";
        exposedByDefault = false;
        prefix = "traefik";
      };
      entryPoints = {
        web.address = ":80";
        websecure.address = ":443";
      };
    };
  };
}