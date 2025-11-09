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
      HostKeyAlgorithms = "ssh-ed25519";
      PubkeyAcceptedAlgorithms = "ssh-ed25519";
    };
    ports = [ 36022 ];
  };

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
    nomad consul
    tailscale
    lzop pv mbuffer
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
