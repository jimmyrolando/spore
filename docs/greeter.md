# Greeter

`spore-greeter` runs `greeter/` inside `cage`: greetd launches it on a TTY,
with no compositor. It's enabled with `services.spore.greeter.enable = true`,
which replaces greetd's `default_session` (with `mkForce`, so the previous
configuration, for example tuigreet, stays intact and comes back when you
disable it).

The screen: the user's wallpaper blurred, the time and date in large type,
a card with the initial, the user (editable), the password and the session
picker (it remembers the last one; Niri by default), and at the bottom the
hostname and Suspend / Reboot / Shutdown (with confirmation). If PAM asks for
extra steps (2FA, questions), the field shows each request as is.

## The user's theme

The greeter runs as the `greeter` user and can't read anyone's `home`. So
the shell publishes a copy of what it needs (wallpaper, mode, palette,
`colors.json`) in `/var/lib/spore/<user>/`: the folder belongs to the user,
with group `greeter` and permissions `2750`, so no other user can read it.
`services.spore.users` creates it; if it doesn't exist, the shell publishes
nothing.

The greeter shows the theme of the last user who logged in (it saves it in
`/var/lib/spore/.greeter/last-user` when launching the session), with their
name already typed; if another user is typed in, it switches to that user's
theme. With nothing published it uses `assets/wallpapers/spore-dome.jpg` and
the default palette.

`Theme.qml` isn't in `greeter/` in the repo: Quickshell doesn't allow
importing outside the entry point's folder, so `nix/greeter.nix` copies
`shell/common/Theme.qml` at build time. There's only one, and it's never out
of date.

## The flow with greetd (`Greeter.qml`)

1. When the user is typed and Enter is pressed:
   `Greetd.createSession(user)`.
2. greetd replies with `authMessage(...)`. With `responseRequired: true` it
   asks for something (usually the password, but PAM can ask for several
   steps); the field shows the message it sends.
3. `Greetd.respond(text)` checks it against PAM. If it fails,
   `authFailure(message)` arrives: the error is shown and `cancelSession()`
   is called so you can try again.
4. If everything went well, `readyToLaunch()` arrives, and **only then** is
   `Greetd.launch([...])` called with the chosen session's command. greetd
   expects the greeter to exit right away: no long animations afterward.

## Sessions (`Sessions.qml`)

It reads the `.desktop` files from `wayland-sessions`. On NixOS they aren't
in `/run/current-system/sw`: they come from
`services.displayManager.sessionData.desktops`, and the module passes them in
`SPORE_SESSIONS_DIRS`. Each file's `Exec=` is the command
`Greetd.launch()` receives.

## Testing it

cage doesn't support layer-shell: the greeter is a regular window
(`FloatingWindow`); with a `PanelWindow` you get a black screen with the
cursor. That's why it's tested inside cage and not in niri: a headless cage,
`fakegreet` (it comes with greetd and simulates the protocol) and `grim` for
the screenshot, without touching your session:

```bash
WLR_BACKENDS=headless WLR_RENDERER=pixman \
SPORE_GREETER_DIR=<dir with .greeter/last-user and <user> -> /var/lib/spore/<user>> \
SPORE_SESSIONS_DIRS=<sessionData.desktops>/share/wayland-sessions \
QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
  fakegreet "cage -d -- sh -c 'quickshell --path <spore-greeter>/share/spore/greeter & sleep 6; grim greeter.png'"
```

> **Before enabling it**, have another way in: another TTY, SSH, or the
> previous `default_session` at hand. If the QML has an error, you can be
> left without a graphical login.
