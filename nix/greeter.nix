# spore-greeter: the greeter for greetd, on its own. It doesn't need the
# shell: with Spore Shell, it shows the wallpaper and palette the last user's
# shell published in /var/lib/spore; without it, the default ones.
{
  lib,
  stdenvNoCC,
  quickshell,
  cage,
  coreutils,
  gnugrep,
  systemd,
}:

stdenvNoCC.mkDerivation {
  pname = "spore-greeter";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../greeter
      ../shell/common/Theme.qml
      ../assets/wallpapers/spore-dome.jpg
      ../LICENSE
      ./bin/spore-greeter
    ];
  };

  installPhase = ''
    runHook preInstall

    share=$out/share/spore
    mkdir -p $share/assets/wallpapers $out/bin
    cp -r greeter $share/
    # Quickshell doesn't allow importing outside the entry point's folder: the
    # greeter carries its own copy of the theme, always the same as the shell's.
    cp shell/common/Theme.qml $share/greeter/Theme.qml
    # What it shows when no shell has published a wallpaper.
    cp assets/wallpapers/spore-dome.jpg $share/assets/wallpapers/
    install -Dm644 -t $out/share/licenses/spore-greeter LICENSE

    # The sessions list reads the .desktop files with grep, head and cut.
    substitute nix/bin/spore-greeter $out/bin/spore-greeter \
      --subst-var-by share "$share" \
      --subst-var-by runtimePath "${
        lib.makeBinPath [
          coreutils
          gnugrep
        ]
      }" \
      --subst-var-by quickshell "${quickshell}" \
      --subst-var-by cage "${cage}" \
      --subst-var-by systemd "${systemd}"
    chmod +x $out/bin/spore-greeter

    runHook postInstall
  '';

  meta = {
    description = "Spore's greeter for greetd: login with the last user's wallpaper and palette";
    homepage = "https://github.com/jimmyrolando/spore";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "spore-greeter";
  };
}
