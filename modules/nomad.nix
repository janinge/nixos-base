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
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/nomad 0750 nomad nomad -"
  ];

  services.nomad = {
    enable = true;

    extraPackages = with pkgs; [
      nomad-driver-podman
      cni-plugins
    ];

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

  environment.systemPackages = with pkgs; [
    nomad-driver-podman
    cni-plugins
  ];
}