{ config, lib, nodes, hostName, pkgs, ... }:
let
  cfg = nodes.${hostName};
  publicInterfaceIpv4s = map (addr: addr.address) (
    lib.attrByPath [ "networking" "interfaces" cfg.publicIf "ipv4" "addresses" ] [ ] config
  );
  isPrivateIpv4 = ip:
    lib.hasPrefix "10." ip
    || lib.hasPrefix "192.168." ip
    || builtins.match "172\\.(1[6-9]|2[0-9]|3[0-1])\\..*" ip != null;
  bindAddresses = lib.unique ([ cfg.serviceIp "127.0.0.1" ] ++ lib.filter isPrivateIpv4 publicInterfaceIpv4s);

  # Filter nodes for registry role
  registryNodes = lib.filter (n: n.isRegistry or false) (lib.attrValues nodes);
  registryIps = map (n: n.serviceIp) registryNodes;

  # Prioritize current node, then fallback to other registry nodes
  targetIps = [ cfg.serviceIp ] ++ (lib.filter (ip: ip != cfg.serviceIp) registryIps);

  # Format as space-separated string with port 8600
  consulUpstreams = lib.concatStringsSep " " (map (ip: "${ip}:8600") targetIps);

  corednsPackage = pkgs.coredns.overrideAttrs (old: {
    # CoreDNS 1.14.3 has failing upstream tests in this nixpkgs build, but keep
    # the release for its security fixes.
    doCheck = false;
  });
in
{
  services.coredns = {
    enable = true;
    package = corednsPackage;
    config = ''
      ts.h00t.works:53 {
        # Resolve MagicDNS names through the local Tailscale DNS proxy instead
        # of letting the broader h00t.works template answer with this node's
        # service IP.
        bind ${lib.concatStringsSep " " bindAddresses}
        forward . 100.100.100.100
      }

      .:53 {
        # Bind the DNS server to the service IP address for this host and localhost.
        bind ${lib.concatStringsSep " " bindAddresses}

        # Override for headscale.h00t.works
        template IN A headscale.h00t.works. {
          answer "headscale.h00t.works. 300 IN A 91.190.155.127"
        }

        # Serve `h00t.works` and `*.h00t.works` queries,
        # answering with the node's service IP.
        template IN A h00t.works {
          answer "{{ .Name }} 300 IN A ${cfg.serviceIp}"
        }

        # Silence IPv6
        template IN AAAA h00t.works {
          rcode NOERROR
        }

        forward consul ${consulUpstreams} {
          policy sequential
        }

        forward . tls://45.90.28.223 tls://45.90.30.223 {
          except consul
          tls_servername 1663da.dns.nextdns.io
        }
      }
    '';
  };
}
