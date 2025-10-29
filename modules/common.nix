{ config, lib, pkgs, ... }:

{
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "no";

  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
    ports = [ 36022 ];
  };

  users.users.janinge = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [ tree tmux htop git vim ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDQu7S3fOmp/s7y6+xQLYUbv71THSkyPbqv3t5jdidXnH69nBSSLVShXvUb+CZPV5qrsdnDqHtwGDwCmeD8X7a8V5P14OlfN0C6/TssEM0fKqmWWEuzAtU0bpHIq8ZIAGBenY+1y2Pbx0NlPeFn7VLGdcywY/uyuZXx3JAYZA8uPSMXfGrXK2fTdpas8c7iNObqP9uWXOF3OuXmRhkE0BSSYW8b3xB27irihoVViLXNpGvsW4BYUMV0/amNLypL194oYsqY/+eBdmf4ueDBYdsVn7CUgxACe+GfNhDBtC/4qcs5z1Cs4OpVXo0Jo4xxGrgbChZSdVAf+H0ej2W1p96O+3g42StPJm99IWbje4AuvOgpPOn0z4+Mo6M/mcQzWEPZN2DGc3ojDESDUIkvUP/Gkitp7ehmX50/fkFlvHws5GWMUrC4rBAVf7Ek3xpHGGCZkM/cop49TBLNicaM+Xzz3qLZQM8ZYwfbf8LhfEMjw1ji+uHhXcOqMFns4dLjPdE= janinge@Air.home.arpa"
    ];
  };

  users.users.root.initialHashedPassword = "$y$jFT$YToVgnBA2HkKLVWaxIvfa0$cEnX5jJ2P.v4XPAdoWAt9/n/zNYiiCrIFoQwjJMFq6.";

  security.sudo.wheelNeedsPassword = false;
  security.pam.passwordHashAlgorithm = "yescrypt";

  environment.systemPackages = with pkgs; [
    zsh tmux curl wget jq unzip
    nomad consul
    tailscale
    lzop pv mbuffer
  ];

  programs.zsh.enable = true;

  services.tailscale.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
