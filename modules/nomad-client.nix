{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
  consulServers = lib.filter (n: n ? "isRegistry" && n.isRegistry) (lib.attrValues nodes);
  consulJoin = lib.map (n: n.serviceIp) consulServers;
in
{
  users.groups.nomad = {};
  users.users.nomad = {
    isSystemUser = true;
    group = "nomad";
    home = "/var/lib/nomad";
    description = "Nomad service user";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/nomad 0750 nomad nomad -"
  ];

  services.nomad = {
    enable = true;
    settings = {
      name = hostName;
      bind_addr = cfg.serviceIp;
      data_dir = "/var/lib/nomad";
      client = {
        enabled = true;
        cni_config_dir = "/etc/cni/net.d";
        options = {
          "docker.endpoint" = "unix:///var/run/docker.sock";
        };
      };
      server.enabled = false;
      telemetry.publish_allocation_metrics = true;
    };
  };

  environment.etc."cni/net.d/nomad.conflist".text = lib.generators.toJSON {} {
    cniVersion = "0.4.0";
    name = "nomad";
    plugins = [
      {
        type = "bridge";
        bridge = cfg.serviceBridge;
        ipMasq = true;
        ipam = {
          type = "host-local";
          subnet = cfg.routedSubnet;
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

  services.consul = {
    enable = true;
    extraConfig = {
      server = false;
      retry_join = consulJoin;
      bind_addr = cfg.serviceIp;
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

  systemd.services.nomad.serviceConfig = {
    User = "nomad";
    Group = "nomad";
    SupplementaryGroups = lib.mkForce [];
    DynamicUser = lib.mkForce false;
  };

  services.prometheus.exporters.node.enable = true;
  services.cadvisor = {
    enable = true;
    listenAddress = "0.0.0.0";
  };
}
