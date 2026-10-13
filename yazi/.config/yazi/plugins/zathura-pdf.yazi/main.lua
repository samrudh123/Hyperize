-- PDF previews that look like zathura: the page in the theme's colours
-- (zathurarc's recolour, applied by recolor.py), framed in zathura's
-- background, with zathura's statusbar — file name and [page/pages] — along
-- the bottom. Same paging as the built-in `pdf` previewer (J/K, or the wheel),
-- which this replaces; only the look differs. zathura's own keys (w, Ctrl+R,
-- zoom, search …) are not available here; Enter opens the real zathura.
--
-- The cache name carries zathurarc's mtime, so a theme / accent change
-- (set-accent.sh rewrites zathurarc) re-renders pages instead of showing the
-- old colours.
local M = {}

local CONFIG = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local ZATHURARC = CONFIG .. "/zathura/zathurarc"
local HELPER = (os.getenv("YAZI_CONFIG_HOME") or (CONFIG .. "/yazi")) .. "/plugins/zathura-pdf.yazi/recolor.py"

-- statusbar colours from zathurarc (zathura's own defaults if unset)
local function statusbar_colors()
	local bg, fg = "#000000", "#ffffff"
	local f = io.open(ZATHURARC, "r")
	if f then
		for line in f:lines() do
			local k, v = line:match('^%s*set%s+(statusbar%-[bf]g)%s+"?(#%x%x%x%x%x%x)"?')
			if k == "statusbar-bg" then bg = v elseif k == "statusbar-fg" then fg = v end
		end
		f:close()
	end
	return bg, fg
end

local function themed_cache(job)
	local cache = ya.file_cache(job)
	if not cache then
		return nil
	end
	local cha = fs.cha(Url(ZATHURARC))
	local stamp = cha and math.floor(cha.mtime or 0) or 0
	return Url(tostring(cache) .. "-z" .. stamp)
end

local function page_count(path)
	local out = Command("pdfinfo"):arg({ tostring(path) }):stdout(Command.PIPED):stderr(Command.NULL):output()
	return out and tonumber(out.stdout:match("Pages:%s*(%d+)"))
end

function M:peek(job)
	local start, cache = os.clock(), themed_cache(job)
	if not cache then
		return
	end

	local ok, err, bound = self:preload(job)
	if bound and bound > 0 then
		return ya.emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
	elseif not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	local a = job.area
	local bar = ui.Rect { x = a.x, y = a.y + a.h - 1, w = a.w, h = 1 }
	local _, err = ya.image_show(cache, ui.Rect { x = a.x, y = a.y, w = a.w, h = math.max(1, a.h - 1) })
	if err then
		return ya.preview_widget(job, err)
	end

	local bg, fg = statusbar_colors()
	local pages = page_count(job.file.path)
	local right = string.format("[%d/%s] ", job.skip + 1, pages or "?")
	ya.preview_widget(job, {
		ui.Text(""):area(bar):bg(bg),
		ui.Line(" " .. job.file.name):area(bar):fg(fg):bg(bg),
		ui.Line(right):area(bar):align(ui.Align.RIGHT):fg(fg):bg(bg),
	})
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

function M:preload(job)
	local cache = themed_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	-- The previewer and the preloader can render the same page at once, so
	-- each run works on its own temp names and only the final cache is shared.
	local tmp = string.format("%s.%d", tostring(cache), math.floor(ya.time() * 1e6))

	-- stylua: ignore
	local output, err = Command("pdftoppm")
		:arg({
			"-f", job.skip + 1,
			"-l", job.skip + 1,
			"-singlefile", "-png",
			tostring(job.file.path), tmp,
		})
		:output()

	if not output then
		return true, Err("Failed to start `pdftoppm`, error: %s", err)
	elseif not output.status.success then
		local pages = job.skip > 0 and tonumber(output.stderr:match("the last page %((%d+)%)"))
		return true, Err("Failed to convert PDF to image, stderr: %s", output.stderr), pages
	end

	local png, jpg = tmp .. ".png", tmp .. ".jpg"
	local out = Command("/usr/bin/python3")
		:arg({ HELPER, png, jpg, tostring(rt.preview.image_quality) })
		:stderr(Command.PIPED)
		:output()
	if not out or not out.status.success then
		fs.remove("file", Url(png))
		return true, Err("Failed to recolour the page: %s", out and out.stderr or HELPER)
	end

	local ok, perr = ya.image_precache(Url(jpg), cache)
	fs.remove("file", Url(jpg))
	return ok, perr
end

return M
