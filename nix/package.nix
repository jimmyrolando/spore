# spore-shell: the session shell and Files, its file manager. The greeter is
# a package of its own (greeter.nix).
{
  lib,
  stdenvNoCC,
  quickshell,
  matugen,
  ffmpeg-headless,
  qt6,
  dconf,
  coreutils,
  glib,
  libarchive,
  poppler-utils,
  gawk,
  findutils,
  procps,
  curl,
  cliphist,
  wl-clipboard,
  ddcutil,
  hwdata,
  kdePackages,
}:

let
  # More image formats for Qt, for the quick view, the thumbnails and the
  # wallpapers: WebP and TIFF (qtimageformats), HEIC, AVIF and JPEG XL
  # (kimageformats). Plugins only: nothing runs until an image needs them.
  imagePlugins = "${qt6.qtimageformats}/lib/qt-6/plugins:${kdePackages.kimageformats}/lib/qt-6/plugins";
  # What the shell runs on its own. It's added to PATH without overriding
  # the system's: niri, rofi, systemctl, kitty, etc. still come from there.
  runtimePath = lib.makeBinPath [
    matugen
    # Wallpaper thumbnails (images and videos) and the still frame of a
    # video wallpaper.
    ffmpeg-headless
    dconf
    coreutils
    gawk
    findutils
    procps
    curl
    # Clipboard history (ClipboardService.qml).
    cliphist
    wl-clipboard
    # The external monitors' brightness (BrightnessService.qml).
    ddcutil
    # Files (shell/files/): gio opens files with their app.
    glib
    # Files: bsdtar compresses and extracts archives.
    libarchive
    # Files: pdftoppm and pdfinfo draw a PDF's pages in the quick view.
    poppler-utils
  ];
in
stdenvNoCC.mkDerivation {
  pname = "spore-shell";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../shell
      ../video
      ../assets
      ../settings.example.json
      ../LICENSE
      ../THIRD-PARTY-NOTICES.md
      ./bin/spore
      ./bin/spore-ipc
      ./bin/spore-files
      ./spore-files.desktop
    ];
  };

  installPhase = ''
    runHook preInstall

    share=$out/share/spore
    mkdir -p $share $out/bin
    cp -r shell video assets settings.example.json $share/
    # MIT asks for the notice in every copy; the third-party icons' too.
    install -Dm644 -t $out/share/licenses/spore LICENSE THIRD-PARTY-NOTICES.md

    for script in spore spore-ipc spore-files; do
      substitute nix/bin/$script $out/bin/$script \
        --subst-var-by share "$share" \
        --subst-var-by runtimePath "${runtimePath}" \
        --subst-var-by quickshell "${quickshell}" \
        --subst-var-by pciIds "${hwdata}/share/hwdata/pci.ids" \
        --subst-var-by qtmultimedia "${qt6.qtmultimedia}" \
        --subst-var-by imagePlugins "${imagePlugins}"
      chmod +x $out/bin/$script
    done

    # Files in the app launchers (rofi -show drun…).
    install -Dm644 nix/spore-files.desktop $out/share/applications/spore-files.desktop
    substituteInPlace $out/share/applications/spore-files.desktop --subst-var-by bin "$out/bin"

    runHook postInstall
  '';

  meta = {
    description = "Spore Shell: a Quickshell desktop for niri on NixOS, with its file manager";
    homepage = "https://github.com/jimmyrolando/spore";
    # The code is MIT; the Lucide icons, ISC (see THIRD-PARTY-NOTICES.md).
    license = with lib.licenses; [
      mit
      isc
    ];
    platforms = lib.platforms.linux;
    mainProgram = "spore";
  };
}
