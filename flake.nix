{
  description = "Spore Shell: a Quickshell desktop for niri on NixOS";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        # The shell, with Files.
        spore-shell = pkgs.callPackage ./nix/package.nix { };
        # The greeter for greetd, on its own.
        spore-greeter = pkgs.callPackage ./nix/greeter.nix { };
        default = spore-shell;
      });

      homeManagerModules.default = import ./nix/home-manager.nix self;
      nixosModules.default = import ./nix/nixos.nix self;
    };
}
