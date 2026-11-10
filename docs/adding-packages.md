# Cómo añadir paquetes a este flake

Este repositorio empaqueta únicamente VS Code (`vscode` y `vscode-insider`).
Esta guía explica cómo añadir otro paquete, usando Brave como ejemplo.

Hay dos caminos y conviene elegir bien desde el principio:

1. **El paquete ya existe en nixpkgs**: reexportarlo. Es el camino fácil.
2. **Necesitas la última release o un artefacto que nixpkgs no empaqueta**:
   usar nvfetcher y escribir una derivación propia.

Regla de oro: **no empaquetes de nuevo algo que nixpkgs ya mantiene**, salvo que
necesites una versión o un artefacto concreto.

## Antes de empezar

Comprueba si el paquete ya existe en el `nixpkgs` fijado por el flake:

```sh
nix search nixpkgs brave
```

Para Brave, el `nixpkgs` actual trae la versión `1.98.60`, mientras que upstream
publica la `1.99.55`. Si la versión de nixpkgs te sirve, usa el camino 1. Si no,
usa el camino 2.

## Camino 1: reexportar un paquete de nixpkgs

Solo hay que añadirlo a `packages` en `flake.nix`:

```nix
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
      brave = pkgs.brave;
    };
  };
```

Como `checks = packages`, el paquete pasa a validarse automáticamente como
check. No hace falta tocar nvfetcher, `src/generated.nix` ni
`src/overlays.nix`.

Valida:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#brave
NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --no-build
```

Si la versión de nixpkgs se queda corta, actualiza el input:

```sh
nix flake update nixpkgs
```

Ten en cuenta que eso actualiza **todo** lo que venga de nixpkgs. Si solo
quieres una versión concreta de un paquete, el camino 2 suele ser más
controlable.

## Camino 2: empaquetar una release con nvfetcher

Este es el patrón que usa VS Code en este repo.

Flujo de archivos:

```text
nvfetcher/brave.toml       -> configuración de versiones y URLs
generated/brave/           -> archivos generados por nvfetcher (no editar)
src/generated.nix          -> registra la unidad "brave"
src/brave.nix              -> derivación que consume la fuente generada
flake.nix                  -> expone el paquete
src/overlays.nix           -> expone el overlay
README.md                  -> documentación
```

### 1. Inspecciona los artefactos del upstream

Para Brave:

```sh
curl -s https://api.github.com/repos/brave/brave-browser/releases/latest \
  | jq -r '.tag_name, (.assets[].name)'
```

En la release aparecen nombres como:

- `brave-browser-1.99.55-linux-amd64.zip`
- `brave-browser-1.99.55-linux-arm64.zip`
- `Brave-Browser-arm64.dmg`

Fíjate bien en qué sistemas y arquitecturas publica el proyecto. No expongas el
paquete en un sistema para el que no exista artefacto.

### 2. Crea `nvfetcher/brave.toml`

Una entrada por plataforma. `src.cmd` obtiene la versión y `$ver` se sustituye en
la URL:

```toml
[brave-linux-x64]
src.cmd = """curl -Ls -o /dev/null -w %{url_effective} 'https://github.com/brave/brave-browser/releases/latest' | sed 's#.*/tag/v##'"""
fetch.tarball = "https://github.com/brave/brave-browser/releases/download/v$ver/brave-browser-$ver-linux-amd64.zip"

[brave-linux-arm64]
src.cmd = """curl -Ls -o /dev/null -w %{url_effective} 'https://github.com/brave/brave-browser/releases/latest' | sed 's#.*/tag/v##'"""
fetch.tarball = "https://github.com/brave/brave-browser/releases/download/v$ver/brave-browser-$ver-linux-arm64.zip"

[brave-darwin-arm64]
src.cmd = """curl -Ls -o /dev/null -w %{url_effective} 'https://github.com/brave/brave-browser/releases/latest' | sed 's#.*/tag/v##'"""
fetch.url = "https://github.com/brave/brave-browser/releases/download/v$ver/Brave-Browser-arm64.dmg"
```

Notas:

- `fetch.tarball` sirve para `.zip`, `.tar.gz`, etc.
- `fetch.url` sirve para `.dmg`, `.deb`, `.rpm` y otros formatos que no se
  desempaquetan con `fetchTarball`.
- El formato de `$ver` debe coincidir con el nombre real del artefacto. Por eso
  el `sed` elimina la `v` del tag y la URL la vuelve a añadir solo donde toca.
- Si un `src.cmd` necesita herramientas externas (`curl`, `jq`, etc.), asegúrate
  de que estén disponibles al ejecutar nvfetcher.

### 3. Genera los archivos

```sh
nix-shell -p nvfetcher curl jq --command \
  "nvfetcher -v --keep-going -c nvfetcher/brave.toml -o generated/brave"
```

Esto crea:

- `generated/brave/generated.nix`
- `generated/brave/generated.json`

**Nunca edites esos archivos a mano.** nvfetcher los regenera y actualiza los
hashes. El workflow `.github/workflows/nvfetcher.yml` los refresca
periódicamente.

El script `scripts/update-nvfetcher.sh` regenera todas las unidades del repo,
pero solo instala `nvfetcher`:

```sh
./scripts/update-nvfetcher.sh
```

Si tu configuración depende de `curl`, `jq` u otras herramientas, ejecuta el
comando manual de arriba o ajusta el script.

### 4. Registra la unidad en `src/generated.nix`

```nix
{ callPackage }:
{
  brave = callPackage ../generated/brave/generated.nix { };
  vscode = callPackage ../generated/vscode/generated.nix { };
}
```

### 5. Crea `src/brave.nix`

Esquema mínimo:

```nix
{ generated, stdenv, lib, ... }:
let
  target =
    if stdenv.hostPlatform.isDarwin then
      "darwin-arm64"
    else if stdenv.hostPlatform.isAarch then
      "linux-arm64"
    else
      "linux-x64";

  source = generated."brave-${target}";
in
stdenv.mkDerivation {
  pname = "brave";
  inherit (source) version;
  src = source.src;

  # Aquí falta el trabajo real de empaquetado.
}
```

Aviso importante: un navegador no es solo copiar un binario. Normalmente
necesitarás:

- `autoPatchelfHook` para corregir el intérprete y las librerías.
- `makeWrapper` para lanzar el binario con el entorno correcto.
- Dependencias del sistema (`libxkbcommon`, `gtk3`, `nss`, `alsa-lib`, etc.).
- Instalar el binario, el `.desktop` y los iconos.
- Tratar el formato descargado: `.zip`, `.dmg`, `.deb` o `.rpm`.

Para Brave, lo más razonable suele ser reutilizar `pkgs.brave` y actualizar
nixpkgs. Escribir el empaquetado completo desde cero es un trabajo avanzado y
puede romperse con cada release.

### 6. Expón el paquete en `flake.nix`

```nix
perSystem =
  { pkgs, ... }:
  let
    generated = pkgs.callPackage ./src/generated.nix { };
    vscode = pkgs.callPackage ./src/vscode.nix { generated = generated.vscode; };
    brave = pkgs.callPackage ./src/brave.nix { generated = generated.brave; };
  in
  rec {
    checks = packages;
    packages = {
      inherit (vscode) vscode vscode-insider;
      inherit brave;
    };
  };
```

### 7. Añade el overlay en `src/overlays.nix`

El archivo actual tiene esta forma:

```nix
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
```

Añade `bravePackage` y regístralo:

```nix
bravePackage = final: prev: {
  brave = prev.callPackage ./brave.nix {
    generated = final._flakesGenerated.brave;
  };
};
```

```nix
default = lib.composeManyExtensions [
  generatedSources
  vscodePackage
  bravePackage
];

brave = withGenerated bravePackage;
```

Si `src/brave.nix` devuelve un attrset en vez de una derivación, ajusta el
overlay para hacer `inherit (prev.callPackage ...) brave;`.

### 8. Documenta y valida

Añade la sección correspondiente en `README.md` y ejecuta:

```sh
git add .
NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#brave
NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --no-build
```

Para evaluar todas las plataformas sin construir:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --no-build --all-systems
```

Recuerda que el éxito local solo cubre tu sistema. Revisa el mapeo de plataformas
y deja que la matriz de CI construya nativamente en las demás.

## Reglas e invariantes del repo

- No edites archivos bajo `generated/`; se regeneran con nvfetcher.
- Un `nvfetcher/<unidad>.toml` corresponde a `generated/<unidad>/`.
- Los nombres de las entradas deben coincidir con las búsquedas de
  `src/<paquete>.nix`, por ejemplo `generated."brave-${target}"`.
- Usa predicados de plataforma (`stdenv.hostPlatform.isLinux`, `isDarwin`,
  `isAarch`) cuando las dependencias o artefactos cambien por sistema.
- Si upstream no publica un artefacto para un sistema, no expongas el paquete
  ahí. Usa `lib.optionalAttrs` cuando haga falta.
- Mantén las versiones y hashes fuera de las expresiones escritas a mano; deben
  venir de nvfetcher.
- Conserva el estilo Nix del repo: indentación de dos espacios, argument sets al
  principio y `let` para valores derivados.
- Si el paquete es unfree, usa `NIXPKGS_ALLOW_UNFREE=1` y `--impure`.
- Después de una actualización de fuentes, construye el paquete afectado; que
  nvfetcher genere bien los archivos no garantiza que el layout del artefacto
  siga siendo compatible.

## Checklist rápido

- [ ] ¿El paquete ya está en nixpkgs? Si sí, reexportarlo.
- [ ] ¿He identificado los artefactos reales por sistema?
- [ ] ¿He creado o actualizado `nvfetcher/<unidad>.toml`?
- [ ] ¿He regenerado `generated/<unidad>/` con nvfetcher?
- [ ] ¿He registrado la unidad en `src/generated.nix`?
- [ ] ¿He creado `src/<paquete>.nix` y consume la fuente generada?
- [ ] ¿Está expuesto en `flake.nix` y, si aplica, en `src/overlays.nix`?
- [ ] ¿Está documentado en `README.md`?
- [ ] ¿Pasa `nix build --impure .#<paquete>`?
- [ ] ¿Pasa `nix flake check --impure --no-build`?
