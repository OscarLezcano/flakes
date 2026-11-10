{
  lib,
  stdenv,
  callPackage,
  bun,
  darwin,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  models-dev,
  nodejs,
  nix-update-script,
  ripgrep,
  sysctl,
  versionCheckHook,
  wayland,
  writableTmpDirAsHomeHook,
  ...
}:
let
  sources = callPackage ../generated/opencode/generated.nix { };
  opencodeSource = sources.opencode;

  # opencode 2.2.x requires Bun >= 1.4.4. Older Bun versions also lack the
  # `extension` export of `ws`, which breaks the compiled binary at runtime.
  bunSources = {
    aarch64-darwin = {
      file = "bun-darwin-aarch64.zip";
      hash = "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
    };
    aarch64-linux = {
      file = "bun-linux-aarch64.zip";
      hash = "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=";
    };
    x86_64-linux = {
      file = "bun-linux-x64-baseline.zip";
      hash = "sha256-4ERutVmVdy65iUvrrppr42jZhai5Jx7hJEhvmUbu3XY=";
    };
  };
  bun' = bun.overrideAttrs (_: {
    version = "1.4.4";
    src = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/${bunSources.${stdenv.hostPlatform.system}.file}";
      inherit (bunSources.${stdenv.hostPlatform.system}) hash;
    };
  });

  node_modules =
    finalAttrs:
    stdenv.mkDerivation {
      pname = "${finalAttrs.pname}-node_modules";
      inherit (finalAttrs) version src;

      __structuredAttrs = true;
      strictDeps = true;

      impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
        "GIT_PROXY_COMMAND"
        "SOCKS_SERVER"
      ];

      nativeBuildInputs = [
        bun'
        writableTmpDirAsHomeHook
      ];

      dontConfigure = true;

      buildPhase = ''
        runHook preBuild

        export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
        bun install \
          --cpu="*" \
          --filter './' \
          --filter './packages/cli' \
          --filter './packages/desktop' \
          --filter './packages/app' \
          --frozen-lockfile \
          --ignore-scripts \
          --no-progress \
          --os="*"

        bun --bun ./nix/scripts/canonicalize-node-modules.ts
        bun --bun ./nix/scripts/normalize-bun-binaries.ts

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        find . -type d -name node_modules -exec cp -R --parents {} $out \;

        # opencode targets only Linux and Darwin (see meta.platforms), so the
        # Windows executables that "bun install --os=*" fetches are never
        # executed. Dropping them keeps the output reproducible on hosts whose
        # security endpoint agents scan the store, and removes the vulnerable
        # bundled 7za.exe that will be quarantined.
        find $out -type f -name '*.exe' -delete

        runHook postInstall
      '';

      # NOTE: Required else we get errors that our fixed-output derivation references store paths
      dontFixup = true;

      outputHash =
        if stdenv.hostPlatform.isLinux then
          "sha256-jLQpq4xXkOt0ZKcHh3eC2SI1SPjAkv1scsTEGMaOB5A="
        else if stdenv.hostPlatform.isDarwin then
          # It likely needs replacing too, but I have no idea how to test it.
          "sha256-6VvzodSiEko+Q9UldOJ0V4eV2Gd6JelpYNUMBnI5W/c="
        else
          throw "Unsupported platform";
      outputHashMode = "recursive";
    };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = lib.removePrefix "v" opencodeSource.version;

  __structuredAttrs = true;
  strictDeps = true;

  src = opencodeSource.src;

  postPatch =
    ''
      substituteInPlace packages/script/src/index.ts \
        --replace-fail \
        'throw new Error(`This script requires bun@''${expectedBunVersionRange}' \
        'console.warn(`Warning: This script requires bun@''${expectedBunVersionRange}'
    ''
    + ''
      substituteInPlace packages/cli/script/schema.ts \
        --replace-fail 'import { format } from "prettier"' 'const format = (s: string) => JSON.stringify(JSON.parse(s), null, 2)'
    '';

  node_modules = node_modules finalAttrs;

  nativeBuildInputs = [
    bun'
    installShellFiles
    makeBinaryWrapper
    nodejs
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.autoSignDarwinBinariesHook
  ];

  env = {
    MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
    OPENCODE_DISABLE_MODELS_FETCH = true;
    OPENCODE_VERSION = finalAttrs.version;
    OPENCODE_CHANNEL = "latest";
    NODE_OPTIONS = "--max-old-space-size=4096";
  };

  configurePhase = ''
    runHook preConfigure

    cp -R "$node_modules"/. .
    patchShebangs node_modules
    patchShebangs packages/*/node_modules

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    cd ./packages/cli
    bun --bun ./script/build.ts --single --skip-install
    bun --bun ./script/schema.ts cli.json
    bun --bun ../schema/script/config-schema.ts config.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/cli-*/bin/opencode $out/bin/opencode

    wrapArgs=(
      --set OPENCODE_DISABLE_AUTOUPDATE true
      --suffix PATH : ${lib.makeBinPath [ ripgrep ]}
    )
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      wrapArgs+=(--prefix PATH : ${lib.makeBinPath [ sysctl ]})
    ''}
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      wrapArgs+=(--prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          stdenv.cc.cc
          wayland
        ]
      })
    ''}

    wrapProgram $out/bin/opencode "''${wrapArgs[@]}"

    install -Dm644 cli.json $out/share/cli.json
    install -Dm644 config.json $out/share/config.json
    install -Dm644 ../web/public/theme.json $out/share/theme.json

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd opencode \
      --bash <($out/bin/opencode --completions bash) \
      --zsh <($out/bin/opencode --completions zsh) \
      --fish <($out/bin/opencode --completions fish)
  '';

  dontStrip = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  versionCheckKeepEnvironment = [
    "HOME"
    "OPENCODE_DISABLE_MODELS_FETCH"
  ];
  versionCheckProgramArg = "--version";

  passthru = {
    jsonschema = {
      cli = "${finalAttrs.finalPackage}/share/cli.json";
      config = "${finalAttrs.finalPackage}/share/config.json";
      theme = "${finalAttrs.finalPackage}/share/theme.json";
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "node_modules"
      ];
    };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      delafthi
      DuskyElf
      graham33
      xiaoxiangmoe
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "opencode";
  };
})