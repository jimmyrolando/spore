# services.spore: what the system needs (not each user): the folders the
# shell and the greeter share, and optionally the greeter in greetd. The
# shell itself is installed per user (home-manager.nix).
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.spore;
  desktops = config.services.displayManager.sessionData.desktops;
  sessionDirs = "${desktops}/share/wayland-sessions:${desktops}/share/xsessions";
in
{
  options.services.spore = {
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users who use spore. Each one gets /var/lib/spore/<user> (owned by
        the user, group greeter, 2750) where their shell publishes the
        wallpaper, mode and palette for the greeter to show, without other
        users being able to read them.
      '';
    };

    greeter = {
      enable = lib.mkEnableOption ''
        the spore greeter in greetd (it replaces default_session). Try it first
        from another TTY or with SSH at hand: if it fails, you can't log in
      '';

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.spore-greeter;
        defaultText = lib.literalExpression "spore.packages.\${system}.spore-greeter";
        description = "The Spore greeter package.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.users != [ ] || cfg.greeter.enable) {
      assertions = [
        {
          assertion = config.services.greetd.enable;
          message = "services.spore needs services.greetd.enable (it creates the greeter user).";
        }
      ];

      systemd.tmpfiles.rules = [
        "d /var/lib/spore 0755 root root -"
        # Only the greeter writes here (the last user who logged in).
        "d /var/lib/spore/.greeter 0750 greeter greeter -"
      ]
      ++ map (user: "d /var/lib/spore/${user} 2750 ${user} greeter -") cfg.users;

      # The lockscreen checks the password with this PAM service
      # (shell/lock/LockContext.qml). programs.niri declares it too; without
      # it, nothing could unlock the screen.
      security.pam.services.swaylock = { };
    })

    (lib.mkIf cfg.greeter.enable {
      # mkForce: enabling the greeter replaces any default_session (e.g.
      # tuigreet); disabling it goes back to the previous one without touching
      # anything else.
      services.greetd.settings.default_session = lib.mkForce {
        # The sessions (niri.desktop, etc.) aren't in /run/current-system/sw:
        # NixOS gathers them in sessionData.desktops (like tuigreet --sessions).
        command = "env SPORE_SESSIONS_DIRS=${sessionDirs} ${cfg.greeter.package}/bin/spore-greeter";
        user = "greeter";
      };
    })
  ];
}
