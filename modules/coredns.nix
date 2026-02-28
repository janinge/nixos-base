{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};

  # Filter nodes for registry role
  registryNodes = lib.filter (n: n.isRegistry or false) (lib.attrValues nodes);
  registryIps = map (n: n.serviceIp) registryNodes;

  # Prioritize current node, then fallback to other registry nodes
  targetIps = [ cfg.serviceIp ] ++ (lib.filter (ip: ip != cfg.serviceIp) registryIps);

  # Format as space-separated string with port 8600
  consulUpstreams = lib.concatStringsSep " " (map (ip: "${ip}:8600") targetIps);
in
{
  services.coredns = {
    enable = true;
    config = ''
      .:53 {
        # Bind the DNS server to the service IP address for this host and localhost.
        bind ${cfg.serviceIp} 127.0.0.1

        # Override for headscale.h00t.works
        template IN A headscale.h00t.works. {
          answer "headscale.h00t.works. 300 IN A 91.190.155.127"
        }

        # Serve `h00t.works` and `*.h00t.works` queries,
        # answering with the node's service IP.
        template IN A (.*\.)?h00t\.works\. {
          answer "{{ .Name }} 300 IN A ${cfg.serviceIp}"
        }

        # Silence IPv6
        template IN AAAA (.*\.)?h00t\.works\. {
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