{ pkgs, ... }:
{
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;
    settings = {
      server_url = "https://headscale.h00t.works";
      dns = { base_domain = "hs.h00t.works"; };
      log_level = "info";
    };
  };
}