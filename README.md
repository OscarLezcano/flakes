# VS Code Nix Flake

A Nix flake that packages stable VS Code and VS Code Insider for the supported
systems.

This repository uses [nvfetcher](https://github.com/berberman/nvfetcher) to track
the latest upstream VS Code archives and update package sources automatically
daily.

- [Systems Supported](#systems-supported)
- [Usage](#usage)
- [Overlays](#overlays)
- [VS Code](#vs-code)
- [VS Code Insider](#vs-code-insider)

## Systems Supported

The flake supports the following systems:

- x86_64-linux
- aarch64-linux
- aarch64-darwin

The current nixpkgs input does not support `x86_64-darwin`.

## Usage

In your `flake.nix`, you can import packages from this flake as follows:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";

    flakes.url = "github:George-Miao/flakes";
    flakes.inputs.nixpkgs.follows = "nixpkgs";
    # ... other inputs ...
  };

  outputs = { self, nixpkgs, flakes, ... }:
    let
      system = "x86_64-linux"; # or your system
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          flakes.packages.${system}.vscode
          # ... other packages ...
        ];
      };
    };
}
```

## Overlays

The default overlay makes both VS Code packages available in nixpkgs. Use
`flakes.overlays.default` to enable it, or use `flakes.overlays.vscode` to add
only the VS Code packages.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flakes.url = "github:George-Miao/flakes";
  };

  outputs = { self, nixpkgs, flakes, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [ flakes.overlays.default ];
        }
        # Now you can use vscode and vscode-insider in your configuration
      ];
    };
  };
}
```

Available overlays:

- `.#overlays.default`: includes `vscode` and `vscode-insider`
- `.#overlays.vscode`: includes `vscode` and `vscode-insider`

## Packages

### [VS Code](https://code.visualstudio.com/)

Output: `.#packages.${system}.vscode`

The stable VS Code release for each supported system, with a native ARM64
archive on macOS.

### [VS Code Insider](https://code.visualstudio.com/insiders/)

Output: `.#packages.${system}.vscode-insider`

The VS Code Insider release for each supported system, with a native ARM64
archive on macOS.
