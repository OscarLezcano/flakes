{ lib }:
let
  generatedSources = final: prev: {
    _flakesGenerated = prev.callPackage ./generated.nix { };
  };

  vscodePackage = final: prev: {
    inherit (prev.callPackage ./vscode.nix { generated = final._flakesGenerated.vscode; })
      vscode
      vscode-insider
      ;
  };

  withGenerated =
    overlay:
    lib.composeManyExtensions [
      generatedSources
      overlay
    ];
in
rec {
  default = lib.composeManyExtensions [
    generatedSources
    vscodePackage
  ];

  vscode = withGenerated vscodePackage;
}
