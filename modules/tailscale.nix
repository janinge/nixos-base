{ config, pkgs, lib, ... }:
{
  # A dedicated service to block until Tailscale is connected to a mesh
  systemd.services.tailscale-online = lib.mkIf config.services.tailscale.enable {
    description = "Wait for Tailscale to be connected";
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "tailscaled.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "300s";
      ExecStart = pkgs.writeShellScript "wait-for-tailscale" ''
        # Wait for backend state to be Running
        until ${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -r .BackendState | grep -q 'Running'; do
          echo "Waiting for Tailscale to connect..."
          sleep 2
        done
      '';
    };
  };
}