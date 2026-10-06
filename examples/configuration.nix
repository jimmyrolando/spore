# The system's part of a Spore desktop: only what Spore needs, to merge into
# your own configuration.nix (with your hardware-configuration.nix, boot
# loader, locale, etc.).
{ pkgs, ... }:

{
  # niri, the compositor Spore runs on (it also brings its portal and the PAM
  # service the lockscreen uses).
  programs.niri.enable = true;

  # What the shell shows and controls. Without one of them, its page or
  # widget stays empty; nothing else breaks.
  services.pipewire = {
    # Volume, outputs and inputs, what's playing.
    enable = true;
    pulse.enable = true;
  };
  # The network page (Wi-Fi, connections).
  networking.networkmanager.enable = true;
  # The Bluetooth page.
  hardware.bluetooth.enable = true;
  # The battery, on a laptop.
  services.upower.enable = true;
  # USB drives: mount, eject, and their folders in Files.
  services.udisks2.enable = true;
  # The light/dark mode, the GTK theme and the icons Spore sets go through
  # dconf.
  programs.dconf.enable = true;

  # Spore's fonts: Noto Sans for the interface, JetBrains Mono for numbers.
  fonts.packages = with pkgs; [
    noto-fonts
    nerd-fonts.jetbrains-mono
  ];

  users.users.alice = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };

  # --- The greeter (optional) ---
  # Spore Shell works with any greeter, and the greeter without the shell
  # (with its default wallpaper). Before enabling it, have another way in
  # (another TTY, SSH): if it fails, there's no graphical login.
  services.greetd.enable = true;
  services.spore = {
    greeter.enable = true;
    # The users whose shell shows its wallpaper and palette on the greeter.
    users = [ "alice" ];
  };
}
