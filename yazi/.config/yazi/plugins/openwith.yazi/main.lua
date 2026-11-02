-- Shift+Enter: "Open with" — every app that can open the hovered file (or the
-- selection), not just the one yazi's own opener rules name.
--
--   1-9, a…   the default app, then apps you picked for this type before (★),
--             then every other installed app that handles the type (the same
--             list as GNOME's "Open With")
--   /         search ALL apps in the SUPER+D app grid; the app you click opens
--             the files and is remembered for this type, so it is in this
--             menu next time
--   y         yazi's own openers (nvim, glow, reveal …) — what Shift+Enter
--             used to show; `O` still opens that directly too
--   -         forget the remembered apps for this type
--
-- The work is done by openwith.py next to this file; see its docstring.
local M = {}

local HELPER = (os.getenv("YAZI_CONFIG_HOME") or (os.getenv("HOME") .. "/.config/yazi"))
	.. "/plugins/openwith.yazi/openwith.py"

local KEYS = "123456789abcdefghijklmnopqrstuvwxz"

local targets = ya.sync(function()
	local tab, files = cx.active, {}
	for _, u in pairs(tab.selected) do
		files[#files + 1] = tostring(u)
	end
	if #files == 0 and tab.current.hovered then
		files[1] = tostring(tab.current.hovered.url)
	end
	return files
end)

local function helper(args)
	return Command("/usr/bin/python3"):arg({ HELPER, table.unpack(args) })
end

local function run(args)
	local out, err = helper(args):stdout(Command.PIPED):stderr(Command.PIPED):output()
	if not out or not out.status.success then
		ya.notify {
			title = "Open with",
			content = tostring(out and out.stderr or err),
			timeout = 5,
			level = "error",
		}
		return nil
	end
	return out.stdout
end

local function with_files(args, files)
	for _, f in ipairs(files) do
		args[#args + 1] = f
	end
	return args
end

function M:entry()
	local files = targets()
	if #files == 0 then
		return
	end
	local raw = run({ "menu", files[1] })
	local data = raw and ya.json_decode(raw)
	if not data then
		return
	end

	local cands, actions = {}, {}
	for i, app in ipairs(data.apps) do
		if i > #KEYS then
			break
		end
		local tag = app.tag == "default" and "  · default" or app.tag == "remembered" and "  ★" or ""
		cands[#cands + 1] = { on = KEYS:sub(i, i), desc = app.name .. tag }
		actions[#actions + 1] = { "launch", app.id }
	end
	cands[#cands + 1] = { on = "/", desc = "Search all apps… (app grid)" }
	actions[#actions + 1] = { "pick" }
	cands[#cands + 1] = { on = "y", desc = "yazi's openers…" }
	actions[#actions + 1] = { "yazi" }
	if data.remembered then
		cands[#cands + 1] = { on = "-", desc = "Forget remembered apps for " .. data.desc }
		actions[#actions + 1] = { "forget", data.mime }
	end

	local i = ya.which { cands = cands, silent = false }
	local act = i and actions[i]
	if not act then
		return
	elseif act[1] == "yazi" then
		ya.emit("open", { interactive = true })
	elseif act[1] == "forget" then
		run({ "forget", act[2] })
		ya.notify { title = "Open with", content = "Forgot the remembered apps for " .. data.desc, timeout = 3 }
	elseif act[1] == "pick" then
		run(with_files({ "pick" }, files))
	else
		run(with_files({ "launch", act[2] }, files))
	end
end

return M
