{
  description = "Homelab cluster: Nomad, Consul, Traefik, Headscale...";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05-small";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, disko, sops-nix, ... }:
  let
    defaultSystem = "x86_64-linux";
    lib = nixpkgs.lib;
    nodes = import ./cluster/nodes.nix;
    sharedVolumes = import ./cluster/volumes.nix;
    juicefsMountCatalog = import ./cluster/juicefs-mounts.nix;

    hostFiles = builtins.readDir ./hosts;

    mkModules = node: [
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
      ./modules/common.nix
      ./modules/garage.nix
      ./modules/disko/${node.diskLayout}.nix
    ];

    mkHostConfigs =
      lib.mapAttrs'
        (fileName: _: let
          hostName = lib.removeSuffix ".nix" fileName;
          nodeCfg = nodes.${hostName};
          system = nodeCfg.system or defaultSystem;
        in {
          name = hostName;
          value = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = mkModules nodeCfg ++ [ ./hosts/${fileName} ];
            specialArgs = {
              inherit nodes hostName sharedVolumes juicefsMountCatalog;
            };
          };
        })
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n) hostFiles);

    supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    forAllSystems = lib.genAttrs supportedSystems;
  in {
    nixosConfigurations = mkHostConfigs;

    devShells = forAllSystems (devSystem:
      let
        pkgs = nixpkgs.legacyPackages.${devSystem};
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            sops
            ssh-to-age
            age
            nixos-anywhere
          ];
        };
      });
  };
}
