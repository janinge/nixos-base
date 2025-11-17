{
  description = "Homelab cluster: Nomad, Consul, Traefik, Headscale...";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05-small";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, sops-nix, ... }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    nodes = import ./cluster/nodes.nix;

    hostFiles = builtins.readDir ./hosts;

    mkModules = node: [
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
      ./modules/common.nix
      ./modules/disko/${node.diskLayout}.nix
    ];

    mkHostConfigs =
      lib.mapAttrs'
        (fileName: _: let
          hostName = lib.removeSuffix ".nix" fileName;
          nodeCfg = nodes.${hostName};
        in {
          name = hostName;
          value = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = mkModules nodeCfg ++ [ ./hosts/${fileName} ];
            specialArgs = {
              inherit nodes hostName;
              pkgs-unstable = import nixpkgs-unstable {
                inherit system;
                config.allowUnfree = true;
              };
            };
          };
        })
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n) hostFiles);
  in {
    nixosConfigurations = mkHostConfigs;
  };
}