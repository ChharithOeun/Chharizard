; ============================================================================
; lib/theme.ahk  —  central palette + fonts to match the Chharizard banner.
;
; Every tab file uses these constants instead of hardcoding colors, so a
; single theme swap here re-skins the entire app.
;
; Palette matches assets/banner.png:
;   Brick BG          #0d0810   (deepest black-purple)
;   Panel BG          #1a1018   (slightly lifted, brick tone)
;   Panel BG dim      #150c14   (subtle panels)
;   Cyan neon         #40e0e8   (title / primary accent)
;   Pink neon         #ff2e97   (secondary accent / accent lines)
;   Yellow highlight  #ffd732   (headers / tagline / warnings)
;   Text primary      #e6d9e6   (soft off-white, warm)
;   Text dim          #a68abf   (keyword-strip color)
;   Text muted        #6b5a75
;
; Fonts:
;   Title  Georgia (italic serif, matches banner's Chharizard title)
;   Body   Segoe UI (Windows-native readable sans)
;   Mono   Consolas (log tail)
; ============================================================================

global Theme := {
    ; Colors (hex WITHOUT leading # — AHK v2 GUI SetFont/BackColor wants raw hex)
    bg:            "0d0810",
    panel:         "1a1018",
    panel_dim:     "150c14",
    cyan:          "40e0e8",
    pink:          "ff2e97",
    yellow:        "ffd732",
    text:          "e6d9e6",
    text_dim:      "a68abf",
    text_muted:    "6b5a75",
    ok:            "40e0e8",   ; cyan for "healthy"
    warn:          "ffd732",   ; yellow for "attention"
    err:           "ff2e97",   ; pink for "error"
    accent_line:   "ff2e97",   ; pink like the banner's horizontal lines

    ; Fonts
    font_title:    "Georgia",
    font_body:     "Segoe UI",
    font_mono:     "Consolas",

    ; Sizes
    size_h1:       "s16 bold italic",
    size_h2:       "s12 bold",
    size_h3:       "s10 bold",
    size_body:     "s10",
    size_small:    "s9",
    size_tiny:     "s8"
}

; Convenience helpers so tabs don't repeat verbose SetFont calls.
;
; Usage from a tab file:
;   ThemeApply.title(gui)            ; italic Georgia cyan
;   ThemeApply.h2(gui)               ; bold yellow
;   ThemeApply.body(gui)             ; Segoe UI text color
;   ThemeApply.mono(gui)             ; Consolas cyan (for log-style panels)
;   ThemeApply.status_ok(gui)        ; cyan
;   ThemeApply.status_warn(gui)      ; yellow
;   ThemeApply.status_err(gui)       ; pink
class ThemeApply {
    static title(gui)      { gui.SetFont(Theme.size_h1 . " c" . Theme.cyan,   Theme.font_title) }
    static h2(gui)         { gui.SetFont(Theme.size_h2 . " c" . Theme.yellow, Theme.font_body) }
    static h3(gui)         { gui.SetFont(Theme.size_h3 . " c" . Theme.cyan,   Theme.font_body) }
    static body(gui)       { gui.SetFont(Theme.size_body . " c" . Theme.text, Theme.font_body) }
    static small(gui)      { gui.SetFont(Theme.size_small . " c" . Theme.text_dim, Theme.font_body) }
    static muted(gui)      { gui.SetFont(Theme.size_tiny  . " c" . Theme.text_muted, Theme.font_body) }
    static mono(gui)       { gui.SetFont(Theme.size_small . " c" . Theme.cyan, Theme.font_mono) }
    static status_ok(gui)  { gui.SetFont(Theme.size_body  . " c" . Theme.ok,   Theme.font_body) }
    static status_warn(gui){ gui.SetFont(Theme.size_body  . " c" . Theme.warn, Theme.font_body) }
    static status_err(gui) { gui.SetFont(Theme.size_body  . " c" . Theme.err,  Theme.font_body) }
    static accent_pink(gui){ gui.SetFont(Theme.size_body  . " c" . Theme.pink, Theme.font_body) }
}

; ----------------------------------------------------------------------------
; Enable dark title bar on Windows 10 1809+ / Win11 via DwmSetWindowAttribute.
; Call with the Gui object AFTER gui.Show() so the HWND is valid.
; Silently no-ops on older Windows.
;
; DWMWA_USE_IMMERSIVE_DARK_MODE = 20 on Win11 and Win10 20H1+
;                                 (was 19 on the initial 1903-1909 preview)
; ----------------------------------------------------------------------------
DarkTitleBar(gui) {
    try {
        hwnd := gui.Hwnd
        useDark := 1
        ; Attribute 20 (current)
        DllCall("dwmapi\DwmSetWindowAttribute",
            "Ptr",  hwnd,
            "UInt", 20,
            "Int*", &useDark,
            "UInt", 4)
        ; Fallback attribute 19 (old preview)
        DllCall("dwmapi\DwmSetWindowAttribute",
            "Ptr",  hwnd,
            "UInt", 19,
            "Int*", &useDark,
            "UInt", 4)
    } catch as e {
        ; Silently ignore — older Windows just gets the default title bar.
    }
}
