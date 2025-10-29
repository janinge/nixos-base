{
  description = "Homelab cluster: Nomad, Consul, Traefik, Headscale...";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05-small";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, disko, sops-nix, ... }:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations = {
      hh4-nomad = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./modules/common.nix
          ./modules/power.nix
          ./modules/nomad-client.nix
          ./modules/disko/zfs-ssd.nix
        ];
      };

      edge-gw = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./modules/common.nix
          ./modules/nomad-server.nix
          ./modules/disko/ext4-vm.nix
          ./modules/headscale.nix
        ];
      };
    };
  };
}