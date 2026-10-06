# Lockscreen and idle

## Lockscreen (`shell/lock/`)

At the top, a card with the user's initial, "Welcome back, <name>" (the
first name from the GECOS field of `/etc/passwd`), the date and a circular
clock whose ring marks the seconds. At the bottom, the weather, the password
with the Unlock button inside, Suspend / Reboot / Shutdown (the last two ask
for a second click: the first shows "Confirm?") and the network. There's no
Logout: whoever is at a locked screen shouldn't end the session that easily. In the corner, the hostname.

- **`Lock.qml`**: uses `WlSessionLock` (the `ext-session-lock-v1` protocol)
  and not a window on top of everything: it's the compositor that guarantees
  nothing is visible and no key gets through while locked. It creates a
  `LockSurface` per monitor and holds the `lock` `IpcHandler`. While locked,
  the shell doesn't hot-reload ([development](development.md#dev-mode)).
- **`LockContext.qml`**: the authentication state (what's been typed,
  whether it failed, whether a check is in progress), separate from the
  interface so every monitor shows the same thing. What's typed is cleared
  after every attempt, right or wrong, and when a lock starts: the field
  never keeps the last password. It uses `PamContext` with
  `config: "swaylock"`: it reuses the `pam.d/swaylock` NixOS ships with
  `programs.niri` (authentication only, against `pam_unix`), and
  `services.spore` declares it too. Without it, the field says "Can't check
  passwords" instead of waiting on "Checking…" for good. If something
  explicit is ever needed, the alternative is to declare a
  `security.pam.services.spore-lock` and point `config` at it.
- **`LockSurface.qml`**: the screen, one per monitor.

It's triggered over IPC:

```bash
spore-ipc lock lock
```

> **Careful when testing it.** `ext-session-lock-v1` is *fail-secure*: if the
> Quickshell process dies while locked (a crash, `kill -9`, a `timeout`),
> niri can be left with the session locked and nobody to unlock it. Never
> test it by killing the process: lock, type your password, confirm it
> unlocks, and only then close whatever you need. Better yet: test it in a
> nested niri ([development](development.md)).

## Idle (`shell/services/Idle.qml`)

It uses Quickshell's `IdleMonitor` (the `ext-idle-notify-v1` protocol), with
no swayidle or hypridle. The times are `idle.*` in `settings.json` or
Settings → Idle.

- It respects inhibitors: with a video playing in Firefox, nothing locks or
  turns off. The `idleInhibitor` widget (the coffee cup) does the same by
  hand.
- `Compositor.qml` turns off the monitors (on niri, `power-off-monitors`);
  niri turns them back on with any key or mouse movement.
- Before suspending it always locks (even if `lockAfter` is `0`) and waits a
  second, so the lockscreen is already drawn on wake.
- Whatever else puts the system to sleep (the lid, the power key,
  `systemctl suspend`, another app), the screen locks first: a delay
  inhibitor makes logind wait for the lock (up to 2 s), and
  `systemd-inhibit --list` shows it as Spore. `loginctl lock-session` locks
  it too.
- In a nested niri (screen `winit`) it's disabled: there's never any
  activity there and it would end up suspending the whole machine. Nor does
  it follow logind there: its sleep and its sessions are the real ones.
