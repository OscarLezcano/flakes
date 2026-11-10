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

  bravePackage = final: prev:
    lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-linux") {
      brave = prev.callPackage ./brave.nix {
        generated = final._flakesGenerated.brave;
      };
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
    bravePackage
  ];

  vscode = withGenerated vscodePackage;

  brave = withGenerated bravePackage;
}
