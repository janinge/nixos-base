{ pkgs, ... }:
{
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;
    settings = {
      server_url = "https://headscale.h00t.works";
      dns = { base_domain = "hs.h00t.works"; };
      log_level = "info";
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.headscale = {
      rule = "Host(`headscale.h00t.works`)";
      entryPoints = [ "websecure" ];
      service = "headscale";
      tls.certResolver = "letsencrypt";
    };

    services.headscale.loadBalancer.servers = [
      { url = "http://127.0.0.1:8080"; }
    ];
  };
}