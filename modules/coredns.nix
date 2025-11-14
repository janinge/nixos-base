{ lib, nodes, hostName, ... }:
let
  cfg = nodes.${hostName};
in
{
  services.coredns = {
    enable = true;
    config = ''
      .:53 {
        # Bind the DNS server to the service IP address for this host.
        bind ${cfg.serviceIp}

        # Serve `h00t.works` and `*.h00t.works` queries,
        # answering with the node's service IP.
        template IN A h00t.works. {
          answer "{{ .Name }} 300 IN A ${cfg.serviceIp}"
        }

        template IN ANY h00t.works. {
          rcode NOERROR
        }

        forward . tls://45.90.28.223 tls://45.90.30.223 {
          except h00t.works.
          tls_servername 1663da.dns.nextdns.io
        }
      }
    '';
  };
}