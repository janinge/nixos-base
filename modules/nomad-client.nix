{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
  consulServers = lib.filter (n: n ? "isRegistry" && n.isRegistry) (lib.attrValues nodes);
  consulJoin = lib.map (n: n.serviceIp) consulServers;
in
{
  imports = [ ./nomad.nix ];

  services.nomad.settings = lib.mkMerge [
    {
      client = {
        enabled = true;
        cni_config_dir = "/etc/cni/net.d";
        options = {
          "driver.denylist" = "docker";
        };
      };
      server.enabled = false;

      plugin = {
        podman = {
          config = {
            enabled = true;
            socket_path = "unix:///run/podman/podman.sock";
            volumes = {
              enabled = true;
            };
            gc = {
              image = true;
              image_delay = "3m";
            };
          };
        };
      };

      consul = {
        client_auto_join = true;
      };
    }
  ];

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

  services.consul.extraConfig = lib.mkMerge [
    {
      server = false;
      retry_join = consulJoin;
      dns_config = { allow_stale = true; node_ttl = "15s"; };
      autopilot.cleanup_dead_servers = true;
    }
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings.dns_enabled = false;
  };

  virtualisation.docker.enable = lib.mkForce false;

  # Just override the socket location
  systemd.sockets.podman.socketConfig.ListenStream = lib.mkForce "/run/podman/podman.sock";

  systemd.services.nomad = {
    serviceConfig = {
      User = "nomad";
      Group = "nomad";
      SupplementaryGroups = lib.mkForce [ "podman" ];
      DynamicUser = lib.mkForce false;
      # Override ExecStart to remove the -plugin-dir argument
      ExecStart = lib.mkForce "${config.services.nomad.package}/bin/nomad agent -config=/etc/nomad.json";
    };
    after = [ "podman.socket" ];
    requires = [ "podman.socket" ];
  };

  services.prometheus.exporters.node.enable = true;
  services.cadvisor = {
    enable = true;
    listenAddress = "0.0.0.0";
  };
}
