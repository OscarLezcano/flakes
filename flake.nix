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
          { pkgs, lib, system, ... }:
          let
            generated = pkgs.callPackage ./src/generated.nix { };
            vscode = pkgs.callPackage ./src/vscode.nix { generated = generated.vscode; };
            brave = pkgs.callPackage ./src/brave.nix { generated = generated.brave; };
          in
          rec {
            checks = packages;
            packages = {
              inherit (vscode) vscode vscode-insider;
            }
            // lib.optionalAttrs (system == "x86_64-linux") {
              inherit brave;
            };
          };
      }
    );
}
