# Configuration

Everything adjustable without touching QML lives in
`~/.config/spore/settings.json`, one per user. With
`programs.spore.settingsFile` it can be a link to your dotfiles;
`settings.example.json` has the default values.

`services/Settings.qml` reads it at startup and reads it again when it
changes, without restarting the shell. A missing key uses its default value,
and so does one of the wrong type (`"five"` where a number goes), with a
warning in the log that names it (`settings.json: idle.lockAfter should be a
number`). The log says `Settings: loaded (...)`, or `Invalid settings.json`
if the JSON is broken, in which case the previous values are kept.

## The Settings window

`Mod+Alt+,` (like `Cmd+,` on a Mac), or the Control Center's gear. Eight
sections:

- **Appearance** (the one it opens on by default): the wallpaper grid, the
  palette, the mode (Light / Dark / Auto), the transition and video
  wallpapers.
- **Fonts**: the interface, numbers and bar fonts, picked from a list with a
  search box (each one written in its own font).
- **Bar**: the shape, the background and the widgets (zone, order and which
  ones share a capsule).
- **Displays**: each monitor's resolution, refresh rate, scale and rotation,
  and turning it off (not the last one). It goes through the compositor
  (`niri msg output`, `hyprctl keyword monitor`). After a change it asks
  "Keep this change?" and goes back by itself after 15 seconds, in case the
  screen goes black. What you keep is saved in `~/.local/state/spore/displays.json`
  (by the monitor's make, model and serial, not the port) and the shell puts
  it back when it starts or the monitor is plugged in. It wins over the
  compositor's own `output` config (niri takes the first one it finds, so a
  line in an included file couldn't); "Forget" on a monitor goes back to that
  config. Turning a monitor off is only put back if another one stays on.
- **Printers**: the printers CUPS knows: pause or resume, which one is the
  default, its queue (cancel a job or all of them), a test page (a sheet drawn
  by the shell, with the Spore mark, the machine's details and patterns for
  color, gray, text and lines, printed as an image), and removing
  it. It runs `lpstat`, `lpadmin`, `cupsenable`/`cupsdisable`, `cancel` and
  `lp`, so it needs CUPS and a user allowed to administer it (on NixOS, in
  `wheel`). The queue is read every 3 seconds, only while this section is
  open. "Search" looks for printers that announce themselves on the network
  (`ippfind`, mDNS: it needs Avahi) and "Add" sets one up without a driver
  (`lpadmin -m everywhere`). One that needs a driver is added on CUPS' own
  page (a button opens `localhost:631/admin`), which knows about them.
- **Lock screen**: the weather (off by default: when on, Open-Meteo sees your
  IP address every 30 minutes), its location and units.
- **Idle**: the idle timeouts.
- **About**: the brand and the versions.

Every change is saved right away to `settings.json` (`Settings.save()`); the
file is still the source of truth.

**Preview on desktop** closes the window and opens the **strip**: a band at
the bottom with the thumbnails, the palette and the mode, to choose while
seeing the desktop. It goes to the empty workspace so the whole wallpaper is
visible and, when done, back to the one you were on. `Mod+Alt+A` opens the
same strip directly.

## `settings.json`

| Key | Default | What it is |
|---|---|---|
| `idle.lockAfter` | `300` | seconds of idle before locking (`0` = never) |
| `idle.screenOffAfter` | `600` | same, to turn off the monitors |
| `idle.suspendAfter` | `1800` | same, to suspend |
| `idle.caffeineScreenOffAfter` | `3600` | with Caffeine on (which never suspends), seconds of idle before locking and turning off the monitors (`0` = they stay on) |
| `bar.launcher` | `["rofi", "-show", "drun"]` | the `launcher` widget's command |
| `bar.clockFormat` | `"ddd MMM dd  hh:mm"` | a `Qt.formatDateTime` format; what comes before the first double space is the date (in a muted tone) and what comes after, the time |
| `bar.style` | `"full"` | the shape: `"full"` (edge to edge), `"floating"` (detached from the edges, with rounded corners) or `"pill"` (a pill) |
| `bar.opacity` | `1.0` | the bar's background, from `0.0` (no background: only the capsules over the wallpaper) to `1.0` (solid) |
| `bar.layout` | see below | the widgets per zone |
| `bar.widgetOptions` | `{}` | each widget's options, e.g. `{ "activeWindow": { "showIcon": false } }`; in Settings → Bar, with the gear on its row |
| `picker.wallpaperDir` | `"~/Pictures/Wallpapers"` | the wallpaper folder (in Settings, the folder button opens the picker) |
| `wallpaper.transition` | `"fade"` | `none`, `fade`, `wipe`, `disc`, `nix`, `nix-rnd`, `spore` or `random` |
| `wallpaper.videos` | `true` | `false` = videos stay as a still image (their last frame) and nothing plays |
| `lock.weather` | `null` | the weather: `null` (the default) is off, and nothing goes online for it. Settings → Lock screen turns it on (`{ "enabled": true }`: the time zone's city) and its Location saves `{ "location", "name", "region", "latitude", "longitude" }`. `"enabled": false` turns it off and keeps the location |
| `lock.units` | `"metric"` | `"metric"` (°C, km/h) or `"imperial"` (°F, mph) |
| `clipboard.maxItems` | `500` | clipboard history entries; the oldest are deleted automatically |
| `fonts.interface` | `"Noto Sans"` | the interface text font (menus, panels, most of the text) |
| `fonts.monospace` | `"JetBrainsMono Nerd Font Mono"` | numbers, times and values (formerly `bar.font`, which is still read if `fonts` is missing) |
| `fonts.bar` | `""` | the bar's; `""` = the monospace one |

### Bar widgets (`bar.layout`)

```json
"layout": {
  "left":   [["launcher", "about"]],
  "center": [["workspaces"]],
  "right":  [["clipboard", "audio", "bluetooth", "idleInhibitor", "system"], ["clock", "power"]]
}
```

Each zone is a list of groups and each group is a capsule. What isn't listed
isn't shown. In the center, the group with `workspaces` (or the middle one)
sits at the exact center of the screen.

It's edited from Settings → Bar, with one block per zone (Left, Center,
Right) and one for the hidden ones. Each row has three buttons to send it to
another zone or hide it, ↑ ↓ for the order, and the link to share the
capsule with the one above.

| Id | What it is | Click |
|---|---|---|
| `launcher` | rocket | `bar.launcher` |
| `about` | NixOS logo | About (system data, fastfetch style) |
| `controlCenter` | dashboard | Control Center → Home |
| `activeWindow` | the focused app's icon and name | |
| `apps` | one icon per open app (tooltip: its name); `‹ ›` collapses it to only the focused one | go to that app; with several windows, a list to pick one |
| `system` | CPU (tooltip with CPU, memory and GPU) | Control Center → System |
| `cpu`, `gpu` | icon and two bars: usage and temperature (from 80 °C in the warning color) | Control Center → System |
| `memory` | icon and a usage bar | Control Center → System |
| `workspaces` | niri's workspaces | go to the workspace |
| `clipboard` | clipboard | the history |
| `appImages` | grid | the AppImages in a folder (newest of each) |
| `audio` | volume (wheel: ±5 %) | Control Center → Audio |
| `bluetooth`, `network` | status | its Control Center page |
| `idleInhibitor` | coffee cup: no locking or suspending | on / off |
| `screencast` | a red dot, only while an app records or shares the screen (like on macOS); tooltip with the app and the screen | |
| `notifications` | bell (with a dot if there are unread ones) | Control Center → Notifications |
| `drives` | eject (only with external drives) | Control Center → Drives |
| `clock` | date and time | Control Center → Calendar |
| `power` | power | the power menu |

The `appImages` widget isn't on the bar by default (add it in Settings → Bar, under
Hidden). It opens a list of the AppImages in a folder (`~/Applications` by default),
only the newest version of each (`OpenCADStudio-v2026.41-linux-x86_64.AppImage` is
"OpenCADStudio 2026.41", with the older ones counted): type to search, Enter or a
click to run it, and one that's already running says "Open". The gear on its row
has the folder and "Run with": a command put before the file; empty, it uses
`appimage-run` if it's installed (NixOS needs it; it runs files that aren't
executable) and the file itself otherwise. Nothing runs by itself: only the folder
you choose is listed, and one starts when you pick it.

The Control Center opens below the zone of the widget that was clicked
(left, center or right).

## IPC

`spore-ipc <target> <function> [arguments]`, for niri shortcuts or scripts:

| Target | Functions |
|---|---|
| `controlcenter` | `toggle`, `open <page>` (`home`, `media`, `audio`, `system`, `network`, `bluetooth`, `drives`, `weather`, `calendar`, `notifications`) |
| `settings` | `toggle`, `open <section>` (`appearance`, `fonts`, `bar`, `displays`, `printers`, `lock`, `idle`, `about`) |
| `appearance` | `toggle` (the strip) |
| `clipboard` | `toggle` |
| `appimages` | `toggle` |
| `power` | `toggle` |
| `about` | `toggle` |
| `lock` | `lock`, `isLocked` |
| `caffeine` | `toggle`, `enable`, `disable`, `isEnabled` (no suspending on idle; the screen locks and turns off only after `idle.caffeineScreenOffAfter`) |
| `wallpaper` | `reload` |
| `brightness` | `refresh`, `list` (JSON: name and percent per screen), `set <name> <percent>` |

`spore-ipc` is `quickshell ipc --path <the shell's folder> call`: without the
folder, Quickshell looks in `~/.config/quickshell` and doesn't find the
shell. It uses the same folder as `spore` (the package or `devPath`).

Files is another process with its own target, `files`: see
[Files](files.md#ipc).
