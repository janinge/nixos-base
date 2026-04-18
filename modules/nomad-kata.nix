{ config, pkgs, lib, pkgs-unstable, nodes, hostName, ... }:
let
  cfg = config.cluster.nomadKata;
  nomadCfg = config.cluster.nomad;
  nodeCfg = nodes.${hostName};
  kataRuntime = "io.containerd.kata.v2";
in
{
  options.cluster.nomadKata = {
    enable = lib.mkEnableOption "Kata Containers runtime support for Nomad OCI workloads";

    runtime = lib.mkOption {
      type = lib.types.str;
      default = kataRuntime;
      description = "containerd runtime name used by Nomad's containerd driver for Kata workloads.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = nomadCfg.client.enable;
        message = "cluster.nomadKata.enable requires cluster.nomad.client.enable.";
      }
      {
        assertion = nomadCfg.client.runtime == "kata-containerd";
        message = "cluster.nomadKata.enable requires cluster.nomad.client.runtime = \"kata-containerd\".";
      }
      {
        assertion = nodeCfg ? kernelModules;
        message = "Kata-capable Nomad clients must declare KVM kernelModules in cluster/nodes.nix.";
      }
    ];

    # Runtime path: Nomad schedules normal OCI tasks through the external
    # containerd driver; containerd then starts those tasks with Kata's shim.
    # This keeps VM lifecycle hidden behind the OCI runtime and avoids a custom
    # VM launcher, guest image pipeline, or workload transport protocol.
    services.nomad = {
      dropPrivileges = false;
      extraSettingsPlugins = [ pkgs-unstable.nomad-driver-containerd ];
      settings = {
        plugin."nomad-driver-containerd" = {
          config = {
            enabled = true;
            containerd_runtime = cfg.runtime;
            stats_interval = "5s";
            allow_privileged = false;
          };
        };
        client.meta = {
          kata = "true";
          kata_runtime = cfg.runtime;
          container_runtime = "kata-containerd";
        };
      };
    };

    virtualisation.containerd = {
      enable = true;
      settings = {
        plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata = {
          runtime_type = cfg.runtime;
        };
      };
    };

    systemd.services.containerd.path = [
      pkgs.kata-runtime
      pkgs.qemu_kvm
    ];

    systemd.services.nomad = {
      after = [ "containerd.service" ];
      wants = [ "containerd.service" ];
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
      pkgs.containerd
      pkgs.qemu_kvm
      pkgs-unstable.nomad-driver-containerd
    ];
  };
}
