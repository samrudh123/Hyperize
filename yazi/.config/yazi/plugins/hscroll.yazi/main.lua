--- @sync entry
-- Sideways scrolling for text previews.
--
-- yazi's preview pane cuts long lines off at its right edge (wrap = "no") and
-- has no horizontal scroll of its own. This keeps a column offset for the
-- hovered file and, while it is non-zero, draws the preview itself: bat
-- highlights the visible lines (bat's "Catppuccin Mocha" is the same
-- accent-recoloured theme yazi uses, see set-theme.sh), and the text is shifted
-- with ui.Text:scroll. At offset 0 it is just the built-in `code` previewer, so
-- nothing looks different until you scroll sideways.
--
--   plugin hscroll -- 8      → 8 columns right      (Shift+Right, wheel right)
--   plugin hscroll -- -8     ← 8 columns left       (Shift+Left,  wheel left)
--
-- The offset belongs to one file: hovering anything else starts back at 0.
-- It is clamped so the longest visible line's end stays at the right edge.
local M = {}

local BAT = "batcat"

-- entry: runs on the main thread (@sync), so `self` is the plugin state
function M:entry(job)
	local step = tonumber(job.args[1]) or 0
	local h = cx.active.current.hovered
	if not h or step == 0 then
		return
	end
	local url = tostring(h.url)
	if self.url ~= url then
		self.url, self.off = url, 0
	end
	local off = math.max(0, self.off + step)
	if off == self.off then
		return
	end
	self.off = off
	ya.emit("peek", { cx.active.preview.skip, force = true, only_if = h.url })
end

-- forget the offset as soon as something else is hovered (called from init.lua)
function M:setup()
	ps.sub("hover", function()
		local h = cx.active.current.hovered
		if self.url and (not h or tostring(h.url) ~= self.url) then
			self.url, self.off = nil, 0
		end
	end)
end

local get = ya.sync(function(self, url) return self.url == url and self.off or 0 end)
local set = ya.sync(function(self, url, off)
	if self.url == url then
		self.off = off
	end
end)

local function render(job, off)
	local out = Command(BAT)
		:arg({
			"--color=always", "--style=plain", "--paging=never", "--wrap=never",
			"--tabs=" .. tostring(rt.preview.tab_size),
			"--line-range=" .. (job.skip + 1) .. ":" .. (job.skip + job.area.h),
			tostring(job.file.path),
		})
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()
	if not out or not out.status.success or out.stdout == "" then
		return false
	end

	local widest = 0
	for line in out.stdout:gmatch("[^\n]*") do
		local plain = line:gsub("\27%[[%d;]*m", "")
		widest = math.max(widest, utf8.len(plain) or #plain)
	end
	local max = math.max(0, widest - job.area.w)
	if off > max then
		off = max
		set(tostring(job.file.url), off)
	end
	if off == 0 then
		return false
	end

	ya.preview_widget(job, ui.Text.parse(out.stdout):area(job.area):scroll(off, 0))
	return true
end

function M:peek(job)
	local off = get(tostring(job.file.url))
	if off == 0 or not render(job, off) then
		return require("code"):peek(job)
	end
end

function M:seek(job) require("code"):seek(job) end

return M
