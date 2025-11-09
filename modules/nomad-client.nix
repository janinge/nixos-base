{ config, pkgs, lib, ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/nomad 0750 nomad nomad -"
  ];

  services.nomad = {
    enable = true;
    settings = {
      name = config.networking.hostName;
      bind_addr = "0.0.0.0";
      data_dir = "/var/lib/nomad";
      client.enabled = true;
      client.options = {
        "docker.endpoint" = "unix:///var/run/docker.sock";
      };
      server.enabled = false;
      telemetry.publish_allocation_metrics = true;
    };
  };

  services.consul = {
    enable = true;
    extraConfig = {
      server = false;
      retry_join = [ "100.x.y.z" ];
      dns_config = { allow_stale = true; node_ttl = "15s"; };
      autopilot.cleanup_dead_servers = true;
    };
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = false;
  };

  virtualisation.docker.enable = lib.mkForce false;
  systemd.services.nomad.serviceConfig.SupplementaryGroups = lib.mkForce [];
  systemd.services.nomad.serviceConfig.DynamicUser = lib.mkForce false;

  services.prometheus.exporters.node.enable = true;
  services.cadvisor = {
    enable = true;
    listenAddress = "0.0.0.0";
  };
}
