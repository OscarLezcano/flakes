{
  generated,
  lib,
  stdenv,
  buildPackages,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dpkg,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  adwaita-icon-theme,
  gsettings-desktop-schemas,
  gtk3,
  gtk4,
  qt6,
  kdePackages,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libdrm,
  libkrb5,
  libuuid,
  libxkbcommon,
  libxshmfence,
  libgbm,
  nspr,
  nss,
  pango,
  pciutils,
  pipewire,
  snappy,
  speechd-minimal,
  udev,
  wayland,
  xdg-utils,
  coreutils,
  libxcb,
  vulkan-loader,
  zlib,
  # command line arguments which are always set e.g "--disable-gpu"
  commandLineArgs ? "",
  # Necessary for USB audio devices.
  pulseSupport ? stdenv.hostPlatform.isLinux,
  libpulseaudio,
  # For GPU acceleration support on Wayland (without the lib it doesn't seem to work)
  libGL,
  # For video acceleration via VA-API (--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder)
  libvaSupport ? stdenv.hostPlatform.isLinux,
  libva,
  enableVideoAcceleration ? libvaSupport,
  # For Vulkan support (--enable-features=Vulkan); disabled by default as it seems to break VA-API
  vulkanSupport ? false,
  enableVulkan ? vulkanSupport,
  # Add KDE Plasma/Breeze Qt plugins for theming. Disabled by default to
  # avoid pulling KDE dependencies into the default Brave closure.
  plasmaSupport ? false,
}:

let
  inherit (lib)
    optional
    optionals
    makeLibraryPath
    makeSearchPathOutput
    makeBinPath
    optionalString
    strings
    escapeShellArg
    ;

  source =
    assert lib.assertMsg (stdenv.hostPlatform.system == "x86_64-linux")
      "Brave is currently packaged only for x86_64-linux";
    generated."brave-linux-x64";

  pname = "brave";
  optName = "brave";
  fileBase = "brave-browser";
  appId = "com.brave.Browser";
  innerWrapper = "brave-browser";
  # Upstream Exec= target in .desktop files (replaced with our wrapper).
  upstreamBin = "brave-browser-stable";

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libx11
    libGL
    libxkbcommon
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxshmfence
    libxtst
    libuuid
    libgbm
    nspr
    nss
    pango
    pciutils # ANGLE dlopens libpci to identify GPUs, including for VA-API device selection.
    pipewire
    udev
    wayland
    libxcb
    zlib
    snappy
    speechd-minimal # Text-to-speech through speech-dispatcher (--enable-speech-dispatcher).
    libkrb5
    vulkan-loader # Chromium and Dawn dlopen libvulkan.so.1 by name.
    qt6.qtbase
  ]
  ++ optionals plasmaSupport [
    # KDE libraries need the libstdc++ they were built with, ahead of any
    # older copy that the session's graphics driver may load first.
    stdenv.cc.cc.lib
    kdePackages.plasma-integration
    kdePackages.breeze
  ]
  ++ optional pulseSupport libpulseaudio
  ++ optional libvaSupport libva;

  rpath = makeLibraryPath deps + ":" + makeSearchPathOutput "lib" "lib64" deps;
  binpath = makeBinPath deps;

  enableFeatures =
    optionals enableVideoAcceleration [
      "AcceleratedVideoDecodeLinuxGL"
      "AcceleratedVideoEncoder"
    ]
    ++ optional enableVulkan "Vulkan";

  disableFeatures = [
    "OutdatedBuildDetector"
  ] # disable automatic updates
  # The feature disable is needed for VAAPI to work correctly: https://github.com/brave/brave-browser/issues/20935
  ++ optionals enableVideoAcceleration [ "UseChromeOSDirectVideoDecoder" ];

in
stdenv.mkDerivation {
  inherit pname;
  inherit (source) version;

  __structuredAttrs = true;
  strictDeps = true;

  src = source.src;

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  doInstallCheck = true;

  nativeBuildInputs = [
    dpkg
    # override doesn't preserve splicing https://github.com/NixOS/nixpkgs/issues/132651
    # Has to use `makeShellWrapper` from `buildPackages` even though `makeShellWrapper` from the inputs is spliced because `propagatedBuildInputs` would pick the wrong one because of a different offset.
    (buildPackages.wrapGAppsHook3.override { makeWrapper = buildPackages.makeShellWrapper; })
  ];

  buildInputs = [
    # needed for GSETTINGS_SCHEMAS_PATH
    glib
    gsettings-desktop-schemas
    gtk3
    gtk4

    # needed for XDG_ICON_DIRS
    adwaita-icon-theme
  ];

  installPhase = ''
      runHook preInstall

      mkdir -p $out $out/bin

      cp -R usr/share $out
      cp -R opt/ $out/opt

      export BINARYWRAPPER=$out/opt/brave.com/${optName}/${innerWrapper}

      # Fix path to bash in $BINARYWRAPPER
      substituteInPlace $BINARYWRAPPER \
          --replace-fail /bin/bash ${stdenv.shell} \
          --replace-fail 'CHROME_WRAPPER' 'WRAPPER'

      ln -sf $BINARYWRAPPER $out/bin/${pname}

      for exe in $out/opt/brave.com/${optName}/{brave,chrome_crashpad_handler}; do
          patchelf \
              --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              --set-rpath "${rpath}" $exe
      done

      # Fix paths
      substituteInPlace $out/share/applications/{${fileBase},${appId}}.desktop \
          --replace-fail /usr/bin/${upstreamBin} $out/bin/${pname}
      substituteInPlace $out/share/gnome-control-center/default-apps/${fileBase}.xml \
          --replace-fail /opt/brave.com $out/opt/brave.com
      substituteInPlace $out/opt/brave.com/${optName}/default-app-block \
          --replace-fail /opt/brave.com $out/opt/brave.com

      # Correct icons location
      icon_sizes=("16" "24" "32" "48" "64" "128" "256")

      for icon in ''${icon_sizes[*]}
      do
          mkdir -p $out/share/icons/hicolor/''${icon}x''${icon}/apps
          ln -s $out/opt/brave.com/${optName}/product_logo_''${icon}.png $out/share/icons/hicolor/''${icon}x''${icon}/apps/${fileBase}.png
      done

      # ANGLE loads this copy by absolute path; the NixOS-patched loader finds ICDs
      # under /run/opengl-driver, the bundled one does not.
      rm $out/opt/brave.com/${optName}/libvulkan.so.1
      ln -s ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $out/opt/brave.com/${optName}/libvulkan.so.1

      # Replace xdg-settings and xdg-mime
      ln -sf ${xdg-utils}/bin/xdg-settings $out/opt/brave.com/${optName}/xdg-settings
      ln -sf ${xdg-utils}/bin/xdg-mime $out/opt/brave.com/${optName}/xdg-mime

      runHook postInstall
  '';

  preFixup = ''
    # Add command line args to wrapGApp.
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${rpath}
      --prefix PATH : ${binpath}
      --suffix PATH : ${
        lib.makeBinPath [
          xdg-utils
          coreutils
        ]
      }
      --set CHROME_WRAPPER ${pname}
      # Always put Brave's own qtbase plugins first; a session with a different
      # Qt version could otherwise make Qt load incompatible platform or
      # shell-integration plugins and abort. The Plasma/Breeze plugins sit
      # behind plasmaSupport to avoid pulling KDE into the default closure.
      --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/lib/qt-6/plugins
      ${optionalString plasmaSupport ''
        --prefix QT_PLUGIN_PATH : ${kdePackages.plasma-integration}/lib/qt-6/plugins
        --prefix QT_PLUGIN_PATH : ${kdePackages.breeze}/lib/qt-6/plugins
      ''}
      ${optionalString (enableFeatures != [ ]) ''
        --add-flags "--enable-features=${strings.concatStringsSep "," enableFeatures}\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+,WaylandWindowDecorations --enable-wayland-ime=true}}"
      ''}
      ${optionalString (disableFeatures != [ ]) ''
        --add-flags "--disable-features=${strings.concatStringsSep "," disableFeatures}"
      ''}
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"
      --add-flags ${escapeShellArg commandLineArgs}
    )
  '';

  installCheckPhase = ''
    # Bypass upstream wrapper which suppresses errors
    $out/opt/brave.com/${optName}/brave --version
  '';

  meta = {
    homepage = "https://brave.com/";
    description = "Privacy-oriented browser for Desktop and Laptop computers";
    changelog =
      "https://github.com/brave/brave-browser/blob/master/CHANGELOG_DESKTOP.md#"
      + lib.replaceStrings [ "." ] [ "" ] source.version;
    longDescription = ''
      Brave browser blocks the ads and trackers that slow you down,
      chew up your bandwidth, and invade your privacy. Brave lets you
      contribute to your favorite creators automatically.
    '';
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [
      uskudnik
      jefflabonte
      buckley310
      rachalaraj
      bachp
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "brave";
  };
}