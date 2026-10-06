# A whole system with Spore: NixOS stable with home-manager, and Spore built
# against nixos-unstable (Quickshell moves fast). Put it next to
# configuration.nix and home.nix, change the names (my-machine, alice) and
# rebuild with `nixos-rebuild switch --flake .#my-machine`.
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spore = {
      url = "github:jimmyrolando/spore";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      spore,
      ...
    }:
    {
      nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          # The system's part: the greeter, and the folders it shares with
          # each user's shell.
          spore.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              # The shell (with Files), for whichever user enables it.
              sharedModules = [ spore.homeManagerModules.default ];
              users.alice = import ./home.nix;
            };
          }
        ];
      };
    };
}
