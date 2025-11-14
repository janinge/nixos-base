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

        # Forward all other queries to NextDNS via DNS-over-TLS.
        # Alternatives include DNS-over-QUIC (quic://) or DNS-over-HTTPS (https://).
        forward . quic://dns1.nextdns.io tls://dns2.nextdns.io {
          # Do not forward queries for the local domain.
          except h00t.works.;
        }
      }
    '';
  };
}