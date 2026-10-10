# curl / wget typed at an interactive prompt → JDownloader (via dl-popup fetch).
# Sourced from ~/.zshrc. Only plain file downloads are taken over:
#     curl -O URL · curl -LO URL · curl -fsSLo FILE URL · wget URL · wget -O FILE URL
# Everything else — API calls, `curl … | sh`, headers/POST/auth, several URLs —
# and anything JD can't fetch falls through to the real tool (exit 3 = fall back).
# Scripts, Makefiles, Dockerfiles and non-interactive shells never see these
# functions: they run /usr/bin/curl directly. The bottom bar still shows their
# progress (dl-popup bar watches running curl/wget processes).
#
# Bypass once:   command curl …      Off for this shell:   export DL_POPUP_FETCH=0

[[ -o interactive ]] || return 0
[[ -n $CLAUDECODE ]] && return 0      # leave agent / tool shells alone

_dl_popup_fetch() {
    local tool=$1; shift
    if [[ ${DL_POPUP_FETCH:-1} == 0 || ! -x ~/.local/bin/dl-popup ]]; then
        command $tool "$@"; return
    fi
    ~/.local/bin/dl-popup fetch $tool "$@"
    local rc=$?
    (( rc == 3 )) && { command $tool "$@"; return; }
    return $rc
}
curl() { _dl_popup_fetch curl "$@"; }
wget() { _dl_popup_fetch wget "$@"; }
