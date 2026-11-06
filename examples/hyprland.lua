-- Spore's lines for Hyprland 0.57 and newer (~/.config/hypr/hyprland.lua).
-- Older Hyprland, with hyprland.conf: examples/hyprland.conf.

-- The shell starts with the session.
hl.on("hyprland.start", function()
    hl.exec_cmd("spore")
end)

-- Spore's shortcuts (the same as niri's).
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd("spore-ipc lock lock"))
hl.bind("SUPER + ALT + C", hl.dsp.exec_cmd("spore-ipc controlcenter toggle"))
hl.bind("SUPER + ALT + comma", hl.dsp.exec_cmd("spore-ipc settings toggle"))
hl.bind("SUPER + ALT + A", hl.dsp.exec_cmd("spore-ipc appearance toggle"))
hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd("spore-ipc clipboard toggle"))
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd("spore-ipc power toggle"))
hl.bind("SUPER + ALT + F", hl.dsp.exec_cmd("spore-files"))

-- Idle turns the monitors off; a key or the mouse turns them back on.
hl.config({
    misc = {
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
    },
})

-- The window borders in Spore's palette. The shell writes this file when it
-- first runs (pcall: no error before that) and applies it again each time the
-- palette or the mode changes.
local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
pcall(dofile, state .. "/spore/hypr/colors.lua")
