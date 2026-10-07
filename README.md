# Spore Shell

<img src="assets/brand/spore-mark-color-light.svg" width="96" alt="Spore">

*From one spore, the whole colony grows.*

A [Quickshell](https://quickshell.org) desktop for [niri](https://github.com/niri-wm/niri)
on NixOS: bar, Control Center, notifications, clipboard, lockscreen, a
settings window, a file manager, wallpapers (video too) with transitions, and
its own greeter for greetd. The palette and the light/dark mode also reach GTK, kitty, rofi,
yazi, Zed, Kate and niri's borders.

It ships as a flake: two packages, the shell (with Files) and the greeter,
and their NixOS and home-manager modules.

## Why Spore

Spore is my return to Linux on the desktop after several years away, and my
first time on Wayland. I found NixOS thanks to
[Tony Banters](https://www.youtube.com/@tony-btw) on YouTube, and its
philosophy hooked me. I'm still getting to know it, but its flexibility lets
you try different environments quickly, and that's how I found niri: it felt
right from the very first moment. I started out with
[Noctalia](https://github.com/noctalia-dev/noctalia), but these days, with
the help of AI, building your own shell is within anyone's reach, so I made
one to my taste: its interface is inspired by Noctalia's, and it was written
with Claude's help.

None of this would have been so easy without
[Quickshell](https://quickshell.org): it turns a bar, a lockscreen or a whole
file manager into a few QML files that reload as you save them, and it
provides the Wayland, PipeWire, Bluetooth and MPRIS plumbing out of the box.
Spore is, in the end, a pile of QML on top of it.

This is a first version (0.1.0), tested on NixOS 26.05 with niri 26.04,
and Quickshell 0.3.1 from nixos-unstable.

## Principles

Spore is simple, light, and free of an endless list of options. Every
change has to respect this:

1. **The defaults are the product.** It has to look and work well without
   touching anything.
2. **Few options, and only the ones worth it:** tastes with a visible
   effect (wallpaper, palette, fonts, the bar's shape) or what depends on
   the machine (idle timeouts, the wallpaper folder). Never sizes, margins,
   curves or durations.
3. **You choose among tested combinations; you don't combine knobs.** Every
   option has to look good with all the others.
4. **Light, and measured.** No extra daemons (swayidle, dunst, waybar…),
   windows exist only while they're open, each piece of data is measured
   once for everyone, and the heavy stuff (video) runs in a separate process
   that exits when done. At rest it uses about 180 MB of memory and less
   than 2 % of one core (measured with a 4K monitor); whatever adds
   something that runs all the time has to justify its cost.
5. **One reference platform: NixOS with niri.** It's where Spore is built
   and tested. Other distros will get a manual install, but trying to
   support everything would go against simplicity.

## Installation

**Other distros:** for now, Spore installs on NixOS. Coming soon: a manual
install for other distros, so anyone can try it on their own system.

Spore comes in two pieces, installed separately:

- **Spore Shell** (`spore-shell`): the shell and Files, its file manager.
  For each user, with home-manager: `programs.spore`.
- **The greeter** (`spore-greeter`): the login screen, in greetd, for the
  whole system: `services.spore.greeter`. Optional: the shell works with
  any greeter, and the greeter without the shell (with its default
  wallpaper).

[`examples/`](examples) has a recommended configuration to start from:

| File | What it has |
|---|---|
| [`flake.nix`](examples/flake.nix) | the inputs and where the modules go |
| [`configuration.nix`](examples/configuration.nix) | the system: what the shell uses (audio, network, Bluetooth, drives, fonts) and the greeter |
| [`home.nix`](examples/home.nix) | each user: the shell and the apps it themes |
| [`niri.kdl`](examples/niri.kdl) | niri's lines: the shell at startup, the shortcuts, the border colors |
| [`rofi/`](examples/rofi) | the app launcher's theme, in Spore's colors |

In short:

```nix
# flake.nix
inputs.spore = {
  url = "github:jimmyrolando/spore";
  inputs.nixpkgs.follows = "nixpkgs-unstable";   # Quickshell is in unstable
};
# modules: spore.nixosModules.default, and for home-manager
#   home-manager.sharedModules = [ spore.homeManagerModules.default ];
```

### The shell (with Files)

```nix
# home.nix
programs.spore = {
  enable = true;
  settingsFile = "/home/alice/dotfiles/spore/settings.json";  # optional
  devPath = "/home/alice/Projects/spore";                     # optional: dev mode
};
```

In niri's config, `spawn-at-startup "spore"` and the shortcuts in
[`examples/niri.kdl`](examples/niri.kdl). It uses Noto Sans and JetBrains
Mono, and PipeWire, NetworkManager, BlueZ, UPower and udisks2 for its pages;
the external monitors' brightness needs `hardware.i2c.enable`
([`examples/configuration.nix`](examples/configuration.nix)). Its commands:

- `spore`: the shell.
- `spore-ipc <target> <function>`: talks to the running shell
  (`spore-ipc controlcenter open weather`); `quickshell ipc show` lists
  everything.
- `spore-files [folder]`: Files, the file manager ([Files](docs/files.md)); it
  also shows up in the app launcher.

### The greeter

```nix
# configuration.nix
services.greetd.enable = true;
services.spore = {
  greeter.enable = true;
  users = [ "alice" ];   # their shell shows its wallpaper and palette here
};
```

greetd runs `spore-greeter` ([greeter](docs/greeter.md)). Before enabling
it, have another way in (another TTY, SSH): if it fails, there's no
graphical login.

## Where everything lives

| What | Where |
|---|---|
| Code (shell, greeter, assets) | the nix store, read-only |
| `settings.json` | `~/.config/spore/` ([configuration](docs/configuration.md)) |
| Wallpaper, mode, palette, `colors.json`, `theme.json` | `~/.local/state/spore/` |
| What Files remembers (`files.json`) | `~/.local/state/spore/` |
| Themes generated for other apps | `~/.local/state/spore/` ([appearance](docs/appearance.md)) |
| Thumbnails, video frames and the Control Center's crop | `~/.cache/spore/` |
| The greeter's copy | `/var/lib/spore/<user>/` |

## The repository

```
flake.nix                 the packages (spore-shell, spore-greeter) and the modules
LICENSE                   the license (MIT)
THIRD-PARTY-NOTICES.md    the licenses of the third-party icons
nix/                      package.nix (the shell), greeter.nix, the modules and the bin/ scripts
examples/                 a recommended configuration (flake, system, user, niri, rofi)
settings.example.json     settings.json with the default values
assets/
  defaults/               default palette and mode
  wallpapers/             the official wallpapers (spore-dome is the default)
  brand/                  the logo in SVG
shell/                    the session shell (one Quickshell process)
  shell.qml               the entry point: the state and who opens what
  files.qml               Files' entry point (another process: spore-files)
  common/                 theme, icons, brand, text and shared controls
  services/               data and state with no interface (settings, niri, weather…)
  bar/                    the bar and its widgets
  controlcenter/          the Control Center and its pages
  panels/                 Settings, About, clipboard, power, notifications
  files/                  Files, the file manager
  lock/                   the lockscreen
  wallpaper/              the background, the transitions and the video player
video/                    the video players: the wallpaper's and the quick view's
                          (separate, short-lived processes)
greeter/                  the greeter (another process, before login)
tools/                    the automated test (test.sh, check-scripts.mjs) and the icon generator
docs/                     the documentation
```

## Documentation

- [Architecture](docs/architecture.md): how it's built, what's in each
  folder and why.
- [Configuration](docs/configuration.md): the Settings window, every
  `settings.json` key and the IPC.
- [Appearance](docs/appearance.md): wallpapers (video too), transitions,
  palettes, Auto mode and the themes for other apps.
- [Lockscreen and idle](docs/lockscreen.md)
- [Greeter](docs/greeter.md)
- [Files](docs/files.md): the file manager, its keys and its IPC.
- [Development](docs/development.md): dev mode, the automated test, how to
  test without breaking your session, icons and shaders.

## License

The code and the wallpapers are free software under the
[MIT license](LICENSE): they can be used, modified and redistributed,
including inside other projects, keeping the copyright notice.

**The Spore name and logo** (`assets/brand/`) aren't covered by it: they
can be used to talk about Spore or to package it, but a modified version has
to use another name and another logo ([details](assets/brand/NOTICE.md)).

The Lucide icons (ISC) and the Simple Icons logos (CC0) have their own
licenses: see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
