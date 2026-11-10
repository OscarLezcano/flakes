{ callPackage }:
{
  vscode = callPackage ../generated/vscode/generated.nix { };
  brave = callPackage ../generated/brave/generated.nix { };
  opencode = callPackage ../generated/opencode/generated.nix { };
}
