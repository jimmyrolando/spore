# One user's part: Spore Shell (with Files) and the apps it works with.
{ pkgs, ... }:

{
  programs.spore = {
    enable = true;
    # Optional: your settings.json kept in your dotfiles. The Settings window
    # saves to it.
    # settingsFile = "/home/alice/dotfiles/spore/settings.json";
  };

  home.packages = with pkgs; [
    # The GTK themes (light and dark) and the icons Spore switches between.
    adw-gtk3
    papirus-icon-theme
    # The app launcher the bar opens (settings.json: bar.launcher).
    rofi
    # A terminal Spore themes; Files opens it with "Open terminal here".
    kitty
  ];
  home.sessionVariables.TERMINAL = "kitty";

  # Rofi in Spore's colors: its theme imports the palette Spore generates.
  xdg.configFile."rofi/config.rasi".source = ./rofi/config.rasi;
  xdg.configFile."rofi/spore.rasi".source = ./rofi/spore.rasi;

  # Only turned on: the theme and icons are set by Spore (through dconf),
  # following the light/dark mode. Setting them here would undo that on
  # every rebuild.
  gtk.enable = true;

  # niri's config gets the lines in niri.kdl, next to this file.

  # To make Files the app that opens folders (a drive's, "Show in folder"),
  # run once:
  #   gio mime inode/directory spore-files.desktop
  # (Not with xdg.mimeApps: it makes mimeapps.list read-only, and Files'
  # "Always open with…" saves there.)

  home.stateVersion = "26.05";
}
