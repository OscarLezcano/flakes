{
  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Debo testear mas tarde
    nixpkgs.url = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      flake = {
        overlays = import ./src/overlays.nix {
          inherit (nixpkgs) lib;
        };
      };

      perSystem =
        { system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };

          generated = pkgs.callPackage ./src/generated.nix { };
          vscode = pkgs.callPackage ./src/vscode.nix { generated = generated.vscode; };
          brave = pkgs.callPackage ./src/brave.nix { generated = generated.brave; };
          opencode = pkgs.callPackage ./src/opencode.nix { generated = generated.opencode; };
        in
        rec {
          packages = {
            inherit (vscode) vscode vscode-insider;
            inherit brave opencode;
          };
          checks = packages;
        };
    };
}