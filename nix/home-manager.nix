# programs.spore: installs the shell (with Files) for a user and, optionally,
# their settings.json and dev mode. The greeter is system-wide (nixos.nix).
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.spore;
in
{
  options.programs.spore = {
    enable = lib.mkEnableOption "Spore Shell, the Quickshell shell for niri, with Files";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.spore-shell;
      defaultText = lib.literalExpression "spore.packages.\${system}.spore-shell";
      description = "The Spore Shell package (the shell and Files).";
    };

    devPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/user/Projects/spore";
      description = ''
        A local checkout of spore. When set, `spore`, `spore-ipc` and
        `spore-files` run from there (with hot reload on edit) instead of the
        package. The greeter always uses its package.
      '';
    };

    settingsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/user/dotfiles/spore/settings.json";
      description = ''
        Path to your own settings.json (e.g. in your dotfiles). It's linked
        to ~/.config/spore/settings.json without going through the store, so
        the settings window can save changes. Without it, the shell uses its
        defaults and creates the file when saving from the window.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."spore/dev-path" = lib.mkIf (cfg.devPath != null) {
      text = cfg.devPath;
    };

    xdg.configFile."spore/settings.json" = lib.mkIf (cfg.settingsFile != null) {
      source = config.lib.file.mkOutOfStoreSymlink cfg.settingsFile;
    };
  };
}
