// Zen reads this from <install dir>/defaults/pref/ (build/zen.sh copies it
// there) and then runs <install dir>/rice-live.cfg as privileged JS at every
// start: the live desktop theme + accent for Zen's chrome.
pref("general.config.filename", "rice-live.cfg");
pref("general.config.obscure_value", 0);
pref("general.config.sandbox_enabled", false);
