{ config, pkgs, lib, nodes, hostName, ... }:
let
  cfg = config.cluster.nomadKata;
  nomadCfg = config.cluster.nomad;
  nodeCfg = nodes.${hostName};
  kataRuntime = "io.containerd.kata.v2";
in
{
  imports = [ ./nomad-kata-netpolicy.nix ];

  options.cluster.nomadKata = {
    enable = lib.mkEnableOption "Kata Containers runtime support for Nomad OCI workloads";

    runtime = lib.mkOption {
      type = lib.types.str;
      default = kataRuntime;
      description = "Docker runtime name used by Nomad's Docker driver for Kata workloads.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = nomadCfg.client.enable;
        message = "cluster.nomadKata.enable requires cluster.nomad.client.enable.";
      }
      {
        assertion = nomadCfg.client.runtime == "kata-docker";
        message = "cluster.nomadKata.enable requires cluster.nomad.client.runtime = \"kata-docker\".";
      }
      {
        assertion = nodeCfg ? kernelModules;
        message = "Kata-capable Nomad clients must declare KVM kernelModules in cluster/nodes.nix.";
      }
    ];

    # Runtime path: Nomad schedules normal OCI tasks through its built-in Docker
    # driver; Docker then starts selected tasks with Kata's containerd shim.
    services.nomad = {
      dropPrivileges = false;
      settings = {
        plugin.docker = {
          config = {
            allow_runtimes = [ "runc" cfg.runtime ];
            allow_privileged = false;
          };
        };
        client.meta = {
          kata = "true";
          kata_runtime = cfg.runtime;
          container_runtime = "kata-docker";
        };
      };
    };

    virtualisation.docker = {
      enable = true;
      extraPackages = [
        pkgs.kata-runtime
        pkgs.qemu_kvm
      ];
      daemon.settings = {
        dns = [ nodeCfg.serviceIp ];
        runtimes.${cfg.runtime} = {
          runtimeType = cfg.runtime;
        };
        # Docker 29 enables a private time namespace by default (moby#52326),
        # adding {"type":"time"} to the OCI spec. Kata 3.29.0's guest agent
        # rejects unknown namespace types ("invalid namespace type"), breaking
        # every Kata container. Offsets are zero so the namespace is a no-op;
        # disable it via the 29.5+ feature flag until Kata accepts it upstream
        # (kata-containers#12076).
        features."time-namespaces" = false;
      };
    };

    systemd.services.nomad = {
      after = [ "docker.service" ];
      wants = [ "docker.service" ];
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        NoNewPrivileges = false;
        PrivateTmp = true;
      };
    };

    boot.kernelModules = [
      "vhost_vsock"
      "vhost_net"
      "tun"
    ];

    environment.etc."kata-containers/configuration.toml".source =
      "${pkgs.kata-runtime}/share/defaults/kata-containers/configuration-qemu.toml";

    systemd.tmpfiles.rules = [
      "d /var/run/kata-containers 0755 root root -"
      "d /var/run/kata-containers/vhost-user 0755 root root -"
    ];

    environment.systemPackages = [
      pkgs.kata-runtime
      pkgs.docker
      pkgs.qemu_kvm
    ];
  };
}
