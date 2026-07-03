{ config, lib, options, nodes ? {}, hostName ? null, ... }:

let
  nodeCfg =
    if hostName != null && builtins.hasAttr hostName nodes
    then nodes.${hostName}
    else {};

  cfg = config.cluster.publicFirewall;
  publicIf = nodeCfg.publicIf or null;
  serviceBridge = nodeCfg.serviceBridge or null;
  hasNomadClientOption = lib.hasAttrByPath [ "cluster" "nomad" "client" "enable" ] options;
  hasNomadClient = hasNomadClientOption && config.cluster.nomad.client.enable;

  portRangeType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.port;
        description = "First port in the inclusive range.";
      };

      to = lib.mkOption {
        type = lib.types.port;
        description = "Last port in the inclusive range.";
      };
    };
  };

  gatewayTCPPorts = lib.optionals (nodeCfg.isGateway or false) [
    80
    443
    25
    465
    587
    993
  ];

  tcpPorts = lib.unique ([ 36022 ] ++ gatewayTCPPorts ++ cfg.extraTCPPorts);
  udpPorts = lib.unique (
    lib.optional config.services.tailscale.enable config.services.tailscale.port
    ++ lib.optional config.services.headscale.enable 3478
    ++ cfg.extraUDPPorts
  );
  tcpPortRanges =
    cfg.extraTCPPortRanges
    ++ lib.optional hasNomadClient {
      inherit (config.cluster.nomad.client.dynamicPorts) from to;
    };
in
{
  options.cluster.publicFirewall = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = publicIf != null && hostName != "hh4-nomad";
      description = ''
        Restrict inbound traffic on the node's public interface to an explicit
        allowlist while leaving trusted internal interfaces open.
      '';
    };

    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publicIf;
      description = "Public interface where the inbound allowlist is applied.";
    };

    extraTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional TCP ports to allow on the public interface.";
    };

    extraTCPPortRanges = lib.mkOption {
      type = lib.types.listOf portRangeType;
      default = [ ];
      description = "Additional TCP port ranges to allow on the public interface.";
    };

    extraUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional UDP ports to allow on the public interface.";
    };
  };

  config = lib.mkMerge [
    {
      networking.firewall.enable = cfg.enable;
      networking.firewall.checkReversePath = "loose";
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.interface != null;
          message = "cluster.publicFirewall.enable requires cluster.publicFirewall.interface to be set.";
        }
      ];

      networking.firewall.trustedInterfaces =
        lib.optional config.services.tailscale.enable "tailscale0"
        ++ lib.optional (serviceBridge != null) serviceBridge;

      networking.firewall.interfaces.${cfg.interface} = {
        allowedTCPPorts = tcpPorts;
        allowedTCPPortRanges = tcpPortRanges;
        allowedUDPPorts = udpPorts;
      };
    })
  ];
}
