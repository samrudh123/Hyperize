--- Used by ~/.config/yazi/yazi-live.sh to reopen yazi in place (it has no way
--- to reload its theme): writes the active tab and, per tab, its folder and
--- hovered entry to $YAZI_LIVE_STATE. The launcher then quits yazi and starts
--- it again on the same folders, re-hovering each entry.
---
--- Quitting is left to the launcher: from in here the plugin itself still
--- counts as a running task, so yazi would ask "unfinished tasks, quit?".
---
---   ya emit-to <client-id> plugin relaunch

local snapshot = ya.sync(function()
	local lines = { tostring(cx.tabs.idx) }
	for i = 1, #cx.tabs do
		local cur = cx.tabs[i].current
		local h = cur.hovered
		lines[#lines + 1] = tostring(cur.cwd) .. "\t" .. (h and tostring(h.url) or "")
	end
	return lines
end)

return {
	entry = function()
		local state = os.getenv("YAZI_LIVE_STATE")
		if not state or state == "" then
			return ya.notify { title = "relaunch", content = "not started by yazi-live.sh", timeout = 3 }
		end
		local ok, err = fs.write(Url(state), table.concat(snapshot(), "\n") .. "\n")
		if not ok then
			ya.notify { title = "relaunch", content = tostring(err), timeout = 5, level = "error" }
		end
	end,
}
