// Rice Accent: Firefox's chrome in the desktop theme + accent, live.
//
// host.py (native messaging, "rice_accent") sends the palette + accent at
// start and on every change; each message becomes a browser.theme.update().
// userChrome.css (set-accent.sh template) reads its --ctp-* colours from the
// CSS variables this theme sets, falling back to the hex it was rendered
// with — so without this extension everything still looks right, it just
// needs a restart to change.

"use strict";

// fg mixed over bg, a = share of fg
function blend(fg, bg, a) {
  const ch = (h, i) => parseInt(h.slice(i, i + 2), 16);
  let out = "#";
  for (const i of [1, 3, 5]) {
    const v = Math.round(ch(fg, i) * a + ch(bg, i) * (1 - a));
    out += v.toString(16).padStart(2, "0");
  }
  return out;
}

function themeFor(p, A) {
  return {
    colors: {
      // Theme slots whose CSS variables userChrome.css reads back (see the
      // :root block there) — keep these roles in step with it.
      frame: p.crust,                       // --lwt-accent-color      -> --ctp-crust
      frame_inactive: p.crust,
      tab_background_text: p.subtext0,      // --lwt-text-color        -> --ctp-subtext0
      icons_attention: A,                   // --lwt-toolbarbutton-icon-fill-attention -> --ctp-accent
      tab_line: A,
      tab_loading: A,
      // The rest just match what userChrome.css paints, so nothing flashes
      // a different colour where it doesn't override Firefox.
      tab_selected: p.base,
      tab_text: p.text,
      toolbar: p.mantle,
      toolbar_text: p.text,
      toolbar_field: p.base,
      toolbar_field_text: p.text,
      toolbar_field_border: p.surface0,
      toolbar_field_focus: p.base,
      toolbar_field_text_focus: p.text,
      toolbar_field_border_focus: A,
      toolbar_field_highlight: blend(A, p.base, 0.35),
      toolbar_field_highlight_text: p.text,
      toolbar_top_separator: p.crust,
      toolbar_bottom_separator: p.surface0,
      toolbar_vertical_separator: p.surface0,
      icons: p.subtext0,
      button_background_hover: p.surface0,
      button_background_active: p.surface1,
      popup: p.base,
      popup_text: p.text,
      popup_border: p.surface0,
      popup_highlight: p.surface0,
      popup_highlight_text: p.text,
      sidebar: p.mantle,
      sidebar_text: p.text,
      sidebar_border: p.surface0,
      sidebar_highlight: blend(A, p.base, 0.30),
      sidebar_highlight_text: p.text,
      ntp_background: p.base,
      ntp_text: p.text,
    },
    properties: { color_scheme: "dark", content_color_scheme: "dark" },
  };
}

let retry = 1000;

function connect() {
  const port = browser.runtime.connectNative("rice_accent");
  port.onMessage.addListener((msg) => {
    retry = 1000;
    if (msg && msg.palette && msg.accent) {
      browser.theme.update(themeFor(msg.palette, msg.accent));
    }
  });
  port.onDisconnect.addListener(() => {
    // host missing or crashed: keep whatever theme is applied, try again later
    setTimeout(connect, retry);
    retry = Math.min(retry * 2, 60000);
  });
}

connect();
