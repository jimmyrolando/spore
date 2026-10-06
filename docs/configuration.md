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

`Mod+Alt+,` (like `Cmd+,` on a Mac), or the Control Center's gear. Six
sections:

- **Appearance** (the one it opens on by default): the wallpaper grid, the
  palette, the mode (Light / Dark / Auto), the transition and video
  wallpapers.
- **Fonts**: the interface, numbers and bar fonts, picked from a list with a
  search box (each one written in its own font).
- **Bar**: the shape, the background and the widgets (zone, order and which
  ones share a capsule).
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
| `audio` | volume (wheel: ±5 %) | Control Center → Audio |
| `bluetooth`, `network` | status | its Control Center page |
| `idleInhibitor` | coffee cup: no locking or suspending | on / off |
| `screencast` | a red dot, only while an app records or shares the screen (like on macOS); tooltip with the app and the screen | |
| `notifications` | bell (with a dot if there are unread ones) | Control Center → Notifications |
| `drives` | eject (only with external drives) | Control Center → Drives |
| `clock` | date and time | Control Center → Calendar |
| `power` | power | the power menu |

The Control Center opens below the zone of the widget that was clicked
(left, center or right).

## IPC

`spore-ipc <target> <function> [arguments]`, for niri shortcuts or scripts:

| Target | Functions |
|---|---|
| `controlcenter` | `toggle`, `open <page>` (`home`, `media`, `audio`, `system`, `network`, `bluetooth`, `drives`, `weather`, `calendar`, `notifications`) |
| `settings` | `toggle`, `open <section>` (`appearance`, `fonts`, `bar`, `lock`, `idle`, `about`) |
| `appearance` | `toggle` (the strip) |
| `clipboard` | `toggle` |
| `power` | `toggle` |
| `about` | `toggle` |
| `lock` | `lock`, `isLocked` |
| `caffeine` | `toggle`, `enable`, `disable`, `isEnabled` (no locking or suspending on idle) |
| `wallpaper` | `reload` |

`spore-ipc` is `quickshell ipc --path <the shell's folder> call`: without the
folder, Quickshell looks in `~/.config/quickshell` and doesn't find the
shell. It uses the same folder as `spore` (the package or `devPath`).

Files is another process with its own target, `files`: see
[Files](files.md#ipc).
