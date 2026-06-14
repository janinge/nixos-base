{ config, lib, nodes, hostName, ... }:
let
  cfg = config.cluster.nomadKata.netPolicy;
  nodeCfg = nodes.${hostName};

  # Render one allowlist entry into an nft accept rule.
  allowRule = a:
    "iifname \"${cfg.bridge}\" ip daddr ${a.cidr} "
    + "${a.protocol} dport ${toString a.port} accept";

  allowRules = lib.concatMapStringsSep "\n          " allowRule cfg.allow;

  hostPortRules = lib.concatMapStringsSep "\n          "
    (p: "iifname \"${cfg.bridge}\" meta l4proto { tcp, udp } th dport ${toString p} accept")
    cfg.hostAllowPorts;
in
{
  options.cluster.nomadKata.netPolicy = {
    enable = lib.mkEnableOption ''
      host egress/ingress firewall for untrusted Kata jobs on the CNI bridge.
      Default-deny to internal networks (allowing only an explicit allowlist),
      default-allow to the Internet, and drop bridge->host traffic except
      hostAllowPorts. Pairs with cluster.nomad.client.snat = false so job
      source IPs are preserved and matchable
    '';

    bridge = lib.mkOption {
      type = lib.types.str;
      default = nodeCfg.serviceBridge;
      description = "CNI bridge carrying untrusted Kata job traffic.";
    };

    internalPrefixes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.0.0.0/8"        # cluster overlay (10.42.0.0/16) + any other RFC1918 /8
        "172.16.0.0/12"     # RFC1918
        "192.168.0.0/16"    # RFC1918
        "100.64.0.0/10"     # tailnet CGNAT range
        "169.254.0.0/16"    # link-local incl. cloud metadata 169.254.169.254
      ];
      description = ''
        Destination prefixes untrusted jobs may NOT reach (dropped unless an
        allowlist entry matches first). Everything outside this set is treated
        as Internet and allowed. Add the node's public DC subnet here to also
        block local hypervisor/neighbour reachability.
      '';
    };

    hostAllowPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = ''
        Ports on the host (reached via the bridge gateway IP) that jobs may
        use. Everything else from the bridge to the host is dropped, closing
        the Nomad API, cadvisor, node_exporter and SSH. Typically [ 53 ] to
        permit DNS to the node's CoreDNS.
      '';
    };

    allow = lib.mkOption {
      default = [ ];
      description = ''
        Pre-approved internal endpoints jobs may reach, as {cidr, protocol,
        port}. Evaluated before the internal-prefix drop, so these punch
        through the default-deny (e.g. a Postgres/object-store endpoint).
      '';
      example = [
        { cidr = "10.42.24.1/32"; protocol = "tcp"; port = 5432; }
      ];
      type = lib.types.listOf (lib.types.submodule {
        options = {
          cidr = lib.mkOption {
            type = lib.types.str;
            description = "Destination host or network in CIDR form.";
          };
          protocol = lib.mkOption {
            type = lib.types.enum [ "tcp" "udp" ];
            default = "tcp";
            description = "L4 protocol.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = "Destination port.";
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    networking.nftables.enable = true;

    # A dedicated inet table. It only inspects traffic entering via the Kata
    # bridge; every other packet falls through the accept policy untouched, so
    # this coexists with networking.firewall.enable = false and the
    # iptables-managed CNI/docker/NAT rules without flushing them.
    networking.nftables.tables."kata-netpolicy" = {
      family = "inet";
      content = ''
        # Destinations untrusted jobs may not reach.
        set internal {
          type ipv4_addr
          flags interval
          ${lib.optionalString (cfg.internalPrefixes != [ ])
            "elements = { ${lib.concatStringsSep ", " cfg.internalPrefixes} }"}
        }

        # job -> host services. Base chain sees all input; only bridge-sourced
        # packets are filtered, ending in an explicit drop.
        chain input {
          type filter hook input priority filter; policy accept;

          iifname "${cfg.bridge}" ct state established,related accept
          ${hostPortRules}
          iifname "${cfg.bridge}" drop
        }

        # job -> onward. Allowlist first, then deny internal space, then fall
        # through to accept (Internet).
        chain forward {
          type filter hook forward priority filter; policy accept;

          iifname "${cfg.bridge}" ct state established,related accept
          ${allowRules}
          iifname "${cfg.bridge}" ip daddr @internal drop
        }
      '';
    };
  };
}
