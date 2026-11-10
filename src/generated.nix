{ callPackage }:
{
  vscode = callPackage ../generated/vscode/generated.nix { };
  brave = callPackage ../generated/brave/generated.nix { };
  opencodeV2 = callPackage ../generated/opencode/generated.nix { };
}
