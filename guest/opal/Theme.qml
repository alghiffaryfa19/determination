pragma Singleton
import QtQuick
QtObject {
    readonly property bool light: Hub.prefs.light
    readonly property bool reduceMotion: !!Hub.prefs.reduceMotion
    function motion(ms) {return reduceMotion ? 0 : ms;}
    readonly property var palettes: [
        {name:"Iris", primary:"#cfbdff", onPrimary:"#31205f", secondary:"#c6d6ae", tertiary:"#efb8c8", dark:"#17141f", light:"#f7f0ff", seed:"#7355ad"},
        {name:"Tide", primary:"#9ddbd0", onPrimary:"#00382f", secondary:"#c3caff", tertiary:"#f0c39a", dark:"#101b1b", light:"#ecf8f3", seed:"#006b5d"},
        {name:"Peach", primary:"#ffc09e", onPrimary:"#54220a", secondary:"#d5c1f0", tertiary:"#c8dba5", dark:"#211711", light:"#fff2e9", seed:"#95512d"},
        {name:"Sky", primary:"#b3ccff", onPrimary:"#13305f", secondary:"#d4c4ef", tertiary:"#a6dfc2", dark:"#131923", light:"#eff3ff", seed:"#435f91"}
    ]
    readonly property var palette: palettes[Hub.prefs.palette] || palettes[0]
    readonly property var generated: Hub.prefs.dynamicColors && Hub.prefs.dynamicPalette ? Hub.prefs.dynamicPalette[light ? "light" : "dark"] || {} : {}
    function role(name,fallback) {return generated[name] || fallback;}
    readonly property color primary: role("primary",light ? palette.seed : palette.primary)
    readonly property color onPrimary: generated.on_primary || (light ? "#ffffff" : palette.onPrimary)
    readonly property color primaryContainer: role("primary_container",light ? palette.primary : palette.onPrimary)
    readonly property color onContainer: role("on_primary_container",light ? palette.onPrimary : palette.primary)
    readonly property color secondary: role("secondary",palette.secondary)
    readonly property color tertiary: role("tertiary",palette.tertiary)
    readonly property color base: role("background",light ? palette.light : palette.dark)
    readonly property color text: role("on_surface",light ? "#211d29" : "#f0e9f7")
    readonly property color subtext: role("on_surface_variant",light ? "#635c6d" : "#c5bccf")
    readonly property color muted: light ? "#79717e" : "#a59aaf"
    readonly property color surface: role("surface_container",light ? "#ebe4f1" : "#302b39")
    readonly property color surfaceHigh: role("surface_container_high",light ? "#dfd6e8" : "#403849")
    readonly property color outline: alpha(role("outline_variant",light ? "#604e75" : "#ede1ff"),.14)
    readonly property string font: "Google Sans Flex"
    function alpha(c,a) { const v=Qt.color(c); return Qt.rgba(v.r,v.g,v.b,a); }
}
