# AGENTS.md

## Repository overview

This repository is a multi-platform Nix flake that uses `flake-parts`. This
document covers only the VS Code packages: `vscode` (stable) and
`vscode-insider`.

The flake supports `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. VS
Code artifacts are fetched for the matching `linux-x64`, `linux-arm64`, and
`darwin-arm64` targets.

## Layout

- `flake.nix` exposes `vscode` and `vscode-insider` from `src/vscode.nix`.
- `src/vscode.nix` contains the VS Code package logic for both channels.
- `nvfetcher/vscode.toml` is the source of truth for VS Code download URLs.
- `generated/vscode/generated.nix` and `generated/vscode/generated.json` are
  generated files; do not edit them by hand.
- `src/generated.nix` exposes the `vscode` unit consumed by the package
  definition.
- `src/overlays.nix` exports the `vscode` overlay and includes VS Code in the
  default overlay.
- `.github/workflows/check.yml` evaluates the flake checks on the supported
  systems.
- `.github/workflows/nvfetcher.yml` refreshes generated sources on a schedule.

The `result` path is a local Nix build symlink and is ignored by Git. Do not
depend on or commit its contents.

## How the VS Code packages work

- `src/vscode.nix` maps the host platform to an nvfetcher entry prefix:
  `isDarwin` selects `darwin-arm64`, `isAarch` selects `linux-arm64`, and any
  other Linux target selects `linux-x64`.
- Each channel looks up `vscode-${vsc-system}-${channel}` in `generated.vscode`,
  where `channel` is `stable` or `insider`. Those entry names must keep this
  exact shape.
- The package version is read from the extracted `package.json` at
  `Contents/Resources/app/package.json` on Darwin or
  `resources/app/package.json` on Linux. Do not hard-code it.
- On Linux, `libsoup_3` and `webkitgtk_4_1` are added as platform dependencies;
  `curl` is added on every platform. Keep platform differences in
  `src/vscode.nix` rather than in generated files.
- Both channels reuse nixpkgs' `vscode`/`buildVscode` machinery by overriding the
  source and version, and set `isInsiders` for the insider channel.

## Making changes

- Keep VS Code package logic in `src/vscode.nix`. Wire any additional output
  through `flake.nix` and `src/overlays.nix` when it should be consumable
  through the overlay.
- Preserve the existing Nix style: two-space indentation, argument sets at the
  top of package files, `let` bindings for derived values, and trailing
  semicolons. Keep diffs focused; do not reformat generated files.
- Use Nix platform predicates such as `stdenv.hostPlatform.isLinux`, `isDarwin`,
  and `isAarch` when dependencies or artifacts vary by target. If an upstream
  artifact does not exist for a system, omit the package for that system rather
  than leaving a guaranteed failing derivation.
- Package attributes automatically become flake checks. Both `vscode` and
  `vscode-insider` must therefore evaluate and build as checks on every
  supported platform.
- Do not hard-code versions or fixed-output source hashes in `src/vscode.nix`;
  all source versions and hashes must come from the `vscode` nvfetcher unit.

## Updating VS Code sources

Edit `nvfetcher/vscode.toml`. Each entry resolves the latest archive through
`update.code.visualstudio.com` and fetches it as a tarball:

```toml
[vscode-linux-x64-stable]
src.cmd = """curl -Ls -o /dev/null -w %{url_effective} 'https://update.code.visualstudio.com/latest/linux-x64/stable'"""
fetch.tarball = "$ver"
```

Then regenerate only the VS Code unit:

```sh
nix-shell -p nvfetcher --command \
  "nvfetcher -v --keep-going -c nvfetcher/vscode.toml -o generated/vscode"
```

Review the generated diff and commit `nvfetcher/vscode.toml` together with
`generated/vscode/generated.nix` and `generated/vscode/generated.json`.

The generated entry names must continue to match the lookups in
`src/vscode.nix`: `vscode-linux-x64-stable`, `vscode-linux-x64-insider`,
`vscode-linux-arm64-stable`, `vscode-linux-arm64-insider`,
`vscode-darwin-arm64-stable`, and `vscode-darwin-arm64-insider`.

After a dependency refresh, build both VS Code packages rather than assuming
that a successful source generation proves the archive layout or build
interface is unchanged.

## Validation

```sh
# Evaluate the flake checks, including both VS Code packages, without building.
NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --no-build

# Build both channels on the current system.
NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#vscode .#vscode-insider
```

VS Code is unfree, so keep `NIXPKGS_ALLOW_UNFREE=1` and `--impure` when
evaluating or building it. For platform-specific changes, local success covers
only the current system; inspect the platform mapping for every supported
system and rely on the CI matrix for native cross-platform builds.
