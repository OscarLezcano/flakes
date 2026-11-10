{
  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }:
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        flake = {
          overlays = import ./src/overlays.nix {
            inherit (nixpkgs) lib;
          };
        };

        perSystem =
          { pkgs, ... }:
          let
            generated = pkgs.callPackage ./src/generated.nix { };
            vscode = pkgs.callPackage ./src/vscode.nix { generated = generated.vscode; };
          in
          rec {
            checks = packages;
            packages = {
              inherit (vscode) vscode vscode-insider;
            };
          };
      }
    );
}
