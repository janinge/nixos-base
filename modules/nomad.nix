{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in
{
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
      bind_addr = cfg.serviceIp;
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
      bind_addr = cfg.serviceIp;
      datacenter = "earth";
    };
  };

  environment.variables = {
    NOMAD_ADDR = "http://${cfg.serviceIp}:4646";
  };
}