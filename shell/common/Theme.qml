import QtQuick

// Centralized palette. Every color any component uses lives HERE, in one
// place -- no loose hex values in each file.
//
// Two independent axes: `palette` (where the colors come from) and `mode`
// (dark/light, which is also what the rest of the system is told). Each
// palette defines both variants with the same roles.
//
// Deliberately not a Singleton: Quickshell's Singletons didn't prove
// reliable here (see docs/architecture.md). shell.qml creates a single one
// and passes it as a property (`theme`) to everything that paints: the
// "wallpaper" palette is loaded from a file and changes live, so a copy of
// constants in each component is no longer enough.
QtObject {
    id: root

    // "dark" | "light"
    property string mode: "dark"
    // "spore" | "catppuccin" | "ayu" | "wallpaper"
    property string palette: "catppuccin"
    // `.colors` from `matugen image ... -j hex` (see shell.qml), null until
    // it's been generated -- in that case "wallpaper" falls back to catppuccin.
    property var matugen: null

    readonly property bool isDark: mode === "dark"

    // The three fonts (settings.json: fonts; Settings → Appearance → Fonts).
    // These are the defaults (and the greeter's if the user hasn't published).
    // fontFamily: the monospace one, for numbers, times and values. Nerd Font's
    // "Mono" variant gives icons the same width as letters.
    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    // The bar's (by default, the monospace one).
    property string barFont: fontFamily
    // Bar icons: the Nerd Font's regular variant; the "Mono" one shrinks them
    // to a letter's width and they end up tiny.
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    // The order they appear in the picker.
    readonly property var paletteNames: ["spore", "catppuccin", "ayu", "wallpaper"]

    // Besides the shell's roles, each variant brings what the other apps use
    // (see SystemTheme.qml): `ansi` is kitty's 16 terminal colors
    // (color0..color15, from the official themes), and `kate` the matching Kate
    // editor theme (KSyntaxHighlighting).
    readonly property var palettes: ({
        // The brand's (the "Spore Shell brand" handoff): in light mode Mist, Ink and
        // the Spore accent (periwinkle); in dark mode the brand's warm variant,
        // Soil, Bone and Peach. The 16 terminal colors, built for each background.
        spore: {
            label: "Spore",
            dark: {
                base: "#1b1311", crust: "#120c0b", surface: "#2e2522", text: "#ece4e0",
                accent: "#f7b394", textOnAccent: "#1b1311", error: "#f08f7f",
                ansi: ["#2e2522", "#f08f7f", "#9cc99a", "#f2c572", "#89b4fa", "#d9a0c8", "#8fcfc0", "#ece4e0",
                       "#5a4c47", "#f5a595", "#b3d9b1", "#f7d38f", "#a7c7fb", "#e8b9da", "#a9e0d3", "#fff8f4"],
                kate: "Breeze Dark"
            },
            light: {
                base: "#f4f4fb", crust: "#e8e8f6", surface: "#e3e4f4", text: "#2b2d4a",
                accent: "#5457b8", textOnAccent: "#ffffff", error: "#d9534a",
                ansi: ["#2b2d4a", "#c94a44", "#4f9d69", "#c98a2e", "#5457b8", "#9a5bb8", "#2f8f9d", "#bcbdd6",
                       "#6c6f92", "#d9534a", "#5fb47a", "#e0913a", "#6f72d0", "#b574d4", "#3aa6b5", "#dcdcef"],
                kate: "Breeze Light"
            }
        },
        catppuccin: {
            label: "Catppuccin",
            dark: {
                base: "#1e1e2e", crust: "#11111b", surface: "#313244", text: "#cdd6f4",
                accent: "#89b4fa", textOnAccent: "#1e1e2e", error: "#f38ba8",
                ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                       "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"],
                kate: "Catppuccin Mocha"
            },
            light: {
                base: "#eff1f5", crust: "#dce0e8", surface: "#ccd0da", text: "#4c4f69",
                accent: "#1e66f5", textOnAccent: "#eff1f5", error: "#d20f39",
                ansi: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
                       "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"],
                kate: "Catppuccin Latte"
            }
        },
        // The same backgrounds/text/ansi as kitty's Ayu and Ayu Light themes.
        ayu: {
            label: "Ayu",
            dark: {
                base: "#0e1419", crust: "#0a0e14", surface: "#243340", text: "#e5e1cf",
                accent: "#e6b450", textOnAccent: "#0e1419", error: "#d95757",
                ansi: ["#000000", "#ff3333", "#b8cc52", "#e6c446", "#36a3d9", "#f07078", "#95e5cb", "#ffffff",
                       "#323232", "#ff6565", "#e9fe83", "#fff778", "#68d4ff", "#ffa3aa", "#c7fffc", "#ffffff"],
                kate: "ayu Dark"
            },
            light: {
                base: "#fafafa", crust: "#e7eaed", surface: "#dfe3e8", text: "#5c6166",
                // Dark text on the orange: light on light isn't readable.
                accent: "#fa8d3e", textOnAccent: "#0e1419", error: "#e65050",
                ansi: ["#000000", "#ff3333", "#86b200", "#f19618", "#41a6d9", "#f07078", "#4cbe99", "#ffffff",
                       "#323232", "#ff6565", "#b8e532", "#ffc849", "#73d7ff", "#ffa3aa", "#7ff0cb", "#ffffff"],
                kate: "ayu Light"
            }
        }
    })

    function label(name: string): string {
        return name === "wallpaper" ? "Wallpaper" : palettes[name].label
    }

    // Material 3 roles (matugen) -> this palette's roles. crust has to be "more
    // sunken" than base in both modes: in dark that's the lowest container, in
    // light surface_dim (lowest is pure white).
    function fromMatugen(c: var, m: string): var {
        const g = k => c[k][m].color
        return {
            base: g("surface"),
            crust: g(m === "dark" ? "surface_container_lowest" : "surface_dim"),
            surface: g("surface_container_highest"),
            text: g("on_surface"),
            accent: g("primary"),
            textOnAccent: g("on_primary"),
            error: g("error"),
            // Material 3 has no terminal colors (matugen's base16 comes out almost
            // monochrome): Ayu's, with the wallpaper's background/text.
            ansi: palettes.ayu[m].ansi,
            // A neutral Kate theme: none of them follows the wallpaper.
            kate: m === "dark" ? "Breeze Dark" : "Breeze Light"
        }
    }

    // Colors for any palette/mode, not only the active one (the picker uses
    // them for the previews). null if "wallpaper" hasn't been generated yet.
    function colorsFor(name: string, m: string): var {
        if (name === "wallpaper")
            return matugen ? fromMatugen(matugen, m) : null
        return palettes[name] ? palettes[name][m] : null
    }

    readonly property var current: colorsFor(palette, mode) || palettes.catppuccin[mode]

    // Main background (bar, windows)
    readonly property color base: current.base
    // Darker/higher-contrast background (greeter, lockscreen, overlays)
    readonly property color crust: current.crust
    // Background for secondary elements (e.g. an unfocused workspace)
    readonly property color surface: current.surface
    // Main text
    readonly property color text: current.text
    // Accent color (focus, highlights)
    readonly property color accent: current.accent
    // Text that goes ON the accent (e.g. the focused workspace's number)
    readonly property color textOnAccent: current.textOnAccent
    // Errors / validation
    readonly property color error: current.error
    // --- Design tokens (the Control Center v2 / bar 3a handoff) ------------
    // The design's values are for light periwinkle; here they come from the
    // active palette's roles, so they work for all of them and for dark mode.

    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Interface text; numbers, times and IPs use fontFamily.
    property string uiFont: "Noto Sans"

    // ink-2: icons and secondary buttons (the text, just slightly toward the
    // accent).
    readonly property color ink2: Qt.tint(text, alpha(accent, 0.2))
    // The bar clock's date, soft subtitles.
    readonly property color soft: Qt.tint(text, alpha(base, 0.3))
    readonly property color muted: Qt.tint(text, alpha(base, 0.42))
    // Tertiary: times, padlocks.
    readonly property color muted2: Qt.tint(text, alpha(base, 0.58))

    readonly property color accentSoft: alpha(accent, 0.08)
    readonly property color accentHover: alpha(accent, 0.14)
    readonly property color accentHoverStrong: alpha(accent, 0.18)

    // Surfaces: panel, cards (almost white in light mode), navigation rail,
    // slider tracks and graph backgrounds.
    readonly property color panelBg: base
    readonly property color cardBg: isDark ? Qt.tint(base, alpha(text, 0.05)) : Qt.tint(base, Qt.rgba(1, 1, 1, 0.85))
    readonly property color cardBorder: alpha(accent, 0.12)
    readonly property color panelBorder: alpha(accent, 0.2)
    readonly property color railBg: Qt.tint(base, alpha(accent, 0.07))
    readonly property color track: Qt.tint(base, alpha(accent, isDark ? 0.16 : 0.1))
    readonly property color insetBg: Qt.tint(cardBg, alpha(accent, 0.05))
    readonly property color switchOff: Qt.tint(base, alpha(accent, isDark ? 0.3 : 0.22))

    // States: danger (power off, delete, badges), ok and warning. Green and
    // orange from the palette's terminal colors.
    readonly property color danger: error
    readonly property color dangerSoft: alpha(error, 0.08)
    readonly property color dangerHover: alpha(error, 0.16)
    readonly property color ok: current.ansi[2]
    readonly property color warn: current.ansi[3]

    // Bar: a neutral background, without design 3a's accent tint (with the
    // Wallpaper palette, an odd accent tinted the whole bar), and lighter
    // capsules on top (in dark mode, just slightly lighter than the bar). In
    // light mode the background moves a little toward the text, a toneless
    // gray: with the base alone, the almost-white capsules couldn't be told
    // apart from a solid bar.
    readonly property color barBg: isDark ? base : Qt.tint(base, alpha(text, 0.08))
    readonly property color capsule: isDark ? Qt.tint(base, alpha(text, 0.1)) : Qt.tint(base, Qt.rgba(1, 1, 1, 0.6))
    // Text on saturated colors (badges, initials, danger red): white in light
    // mode; in dark mode those colors are pastel and white isn't readable.
    readonly property color onColor: isDark ? crust : "white"
    // Unfocused window border: the same gray niri gives inactive windows
    // (inactive-color in SystemTheme.qml, mix(base, text, 0.3)).
    readonly property color inactiveBorder: Qt.tint(base, Qt.rgba(text.r, text.g, text.b, 0.3))
}
