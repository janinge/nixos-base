{ config, lib, pkgs, nodes, hostName, ... }:

let
  cfg = config.cluster.juicefsCsi;
  nomadCfg = config.cluster.nomad;
  nodeCfg = nodes.${hostName};

  # Idempotent bind + rshare of the Nomad data_dir. CSI node plugins create FUSE
  # mounts inside a privileged container; without bidirectional (rshared)
  # propagation from /var/lib/nomad and a shared dockerd mount namespace, those
  # mounts never become visible to consumer allocations (a silent failure).
  rshareScript = pkgs.writeShellScript "nomad-csi-rshared" ''
    set -eu
    if ! ${pkgs.util-linux}/bin/findmnt -no TARGET /var/lib/nomad >/dev/null 2>&1; then
      ${pkgs.util-linux}/bin/mount --bind /var/lib/nomad /var/lib/nomad
    fi
    ${pkgs.util-linux}/bin/mount --make-rshared /var/lib/nomad
  '';
in
{
  options.cluster.juicefsCsi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = nodeCfg.juicefsCsi or false;
      description = ''
        Run the JuiceFS CSI driver (community edition) on this node so Nomad can
        dynamically provision JuiceFS volumes. Scoped to kata-docker clients,
        which already run rootful Docker required by the privileged node plugin.
      '';
    };

    allowPrivileged = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the Nomad Docker driver permits privileged tasks. The CSI node
        plugin must run privileged. Read by modules/nomad-kata.nix.
      '';
    };

    pluginId = lib.mkOption {
      type = lib.types.str;
      default = "juicefs";
      description = "CSI plugin id (must match the csi_plugin{} stanza and volume plugin_id).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = nomadCfg.client.enable;
        message = "cluster.juicefsCsi.enable requires cluster.nomad.client.enable.";
      }
      {
        assertion = nomadCfg.client.runtime == "kata-docker";
        message = ''
          cluster.juicefsCsi.enable is scoped to kata-docker clients (they run
          the rootful Docker the privileged CSI node plugin needs). Set
          cluster.nomad.client.runtime = "kata-docker" or disable juicefsCsi.
        '';
      }
    ];

    boot.kernelModules = [ "fuse" ];

    # Advertise the node so jobs/volumes can constrain to CSI-capable clients.
    services.nomad.settings.client.meta.juicefs = "true";

    # Mount propagation prerequisites (see rshareScript).
    systemd.services.docker.serviceConfig.MountFlags = "shared";

    systemd.services.nomad-csi-rshared = {
      description = "Make /var/lib/nomad rshared for CSI mount propagation";
      before = [ "nomad.service" ];
      requiredBy = [ "nomad.service" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = rshareScript;
      };
    };

    # Metadata password for the node plugin, supplied via META_PASSWORD so it is
    # never embedded in the postgres metaurl (avoids juicefs-csi-driver#1016
    # shell-escaping issues in process-mount mode).
    sops.secrets.juicefs_meta_password = {
      mode = "0400";
      restartUnits = [ "nomad.service" ];
    };

    sops.templates."juicefs-csi.env" = {
      content = ''
        META_PASSWORD=${config.sops.placeholder.juicefs_meta_password}
      '';
      mode = "0400";
      restartUnits = [ "nomad.service" ];
    };

    environment.systemPackages = [ pkgs.juicefs ];
  };
}
