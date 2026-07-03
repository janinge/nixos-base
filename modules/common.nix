{ config, lib, pkgs, nodes ? {}, hostName ? null, ... }:

let
  cfg =
    if hostName != null && builtins.hasAttr hostName nodes
    then nodes.${hostName}
    else {};
  disablePublicIPv6 = cfg.disablePublicIPv6 or false;
  publicIf = cfg.publicIf or null;
in
{
  imports = [
    ./public-firewall.nix
    ./pgbouncer.nix
    ./juicefs.nix
    ./juicefs-internal.nix
    ./juicefs-csi.nix
  ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "no";

  networking.dhcpcd.IPv6rs = lib.mkIf (disablePublicIPv6 && publicIf != null) false;

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  } // lib.optionalAttrs (disablePublicIPv6 && publicIf != null) {
    "net.ipv6.conf.${publicIf}.accept_ra" = 0;
    "net.ipv6.conf.${publicIf}.accept_ra_defrtr" = 0;
    "net.ipv6.conf.${publicIf}.autoconf" = 0;
    "net.ipv6.conf.${publicIf}.disable_ipv6" = 1;
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      HostKeyAlgorithms = "ssh-ed25519";
      PubkeyAcceptedAlgorithms = "ssh-ed25519";
    };
    hostKeys = [{
      type = "ed25519";
      path = "/etc/ssh/ssh_host_ed25519_key";
    }];
    ports = [ 36022 ];
  };

  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  users.groups = {
    tm = { };
    media = { };
  };

  users.users.janinge = {
    isNormalUser = true;
    extraGroups = [ "wheel" "media" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA8t6rvHVj8FdzQE/iV8T2bofg1ATTOuLqRoOw9fCHgC janinge@air"
    ];
  };

  users.users.rebe = {
    isNormalUser = true;
    extraGroups = [ "media" "tm" ];
  };

  users.users.root.initialHashedPassword = "$y$jFT$YToVgnBA2HkKLVWaxIvfa0$cEnX5jJ2P.v4XPAdoWAt9/n/zNYiiCrIFoQwjJMFq6.";
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    tree htop git vim
    zsh tmux curl wget jq unzip
    tailscale
    lzop pv mbuffer lsof

    ethtool conntrack-tools
    termshark tcpdump mtr traceroute
    dig
    socat iperf3 iftop nethogs bmon
  ];

  environment.variables = {
    EDITOR = "vim";
    VISUAL = "vim";
};

  programs.zsh.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion ="25.05";
}
