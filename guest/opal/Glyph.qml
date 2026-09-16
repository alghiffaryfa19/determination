import QtQuick
Text {
    property string name:"apps"
    readonly property var glyphs:({apps:"apps",search:"search",close:"close",back:"arrow_back",next:"chevron_right",home:"home",settings:"tune",wifi:"wifi",wifiOff:"wifi_off",bluetooth:"bluetooth",volume:"volume_up",mute:"volume_off",mic:"mic",sun:"light_mode",moon:"dark_mode",play:"play_arrow",pause:"pause",previous:"skip_previous",skip:"skip_next",bell:"notifications",quiet:"do_not_disturb_on",power:"power_settings_new",lock:"lock",restart:"restart_alt",sleep:"bedtime",game:"sports_esports",phone:"smartphone",desktop:"desktop_windows",pin:"keep",check:"check",add:"add",timer:"timer",coffee:"coffee",capture:"screenshot_monitor",folder:"folder",terminal:"terminal",web:"language",battery:"battery_full",charging:"battery_charging_full",cpu:"speed",memory:"memory",palette:"palette",music:"music_note",grid:"grid_view",list:"view_list",calendar:"calendar_month",spark:"auto_awesome",convergence:"devices",expand:"expand_more",link:"link",balanced:"balance",clipboard:"content_paste",copy:"content_copy",trash:"delete",logout:"logout"})
    text:glyphs[name]||name
    font.family:"Material Symbols Rounded"
    font.pixelSize:22
    color:Theme.text
    horizontalAlignment:Text.AlignHCenter
    verticalAlignment:Text.AlignVCenter
    renderType:Text.QtRendering
}
