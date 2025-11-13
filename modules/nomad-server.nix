{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in
{
  imports = [ ./nomad.nix ];

  systemd.services.nomad.after = [ "consul.service" ];

  services.nomad.settings = {
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
  };

  services.consul.extraConfig = {
    client_addr = "127.0.0.1 ${cfg.serviceIp}";
    server = true;
    bootstrap_expect = 1;
    ui = true;
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