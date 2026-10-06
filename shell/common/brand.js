.pragma library

// The shell's brand, in one place (the "Spore Shell brand" handoff). In prose
// "Spore"; the first time, "Spore Shell". The version is the package's
// (nix/package.nix): change them together.
var name = "Spore Shell"
var shortName = "Spore"
var wordmark = "spore"
var slogan = "From one spore, the whole colony grows."
var description = "A Quickshell desktop for niri on NixOS."
var version = "0.1.0"

// Brand colors (the "Spore Shell brand" sheet): the logo, the wordmark and
// the SHELL label use them fixed, whatever the theme's palette. Only the soil
// and the wordmark change with the background: Ink on light, Bone on dark.
var colors = {
    spore: "#5457b8",
    mycel: "#aeb0e3",
    ink: "#2b2d4a",
    bone: "#ece4e0"
}
