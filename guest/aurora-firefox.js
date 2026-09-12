// Firefox ESR runs as a normal Wayland desktop client, but this display is a
// phone. Advertise the real form factor to sites and enable the touch paths
// that desktop Firefox otherwise leaves in auto-detect limbo. These are
// defaults, not locked policy: a user can still override them in about:config.
pref("general.useragent.override", "Mozilla/5.0 (Android 16; Mobile; rv:140.0) Gecko/140.0 Firefox/140.0");
pref("dom.w3c_touch_events.enabled", 1);
pref("apz.gtk.kinetic_scroll.enabled", true);
