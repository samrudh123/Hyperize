-- Mouse wheel over the preview pane: at most one page per 0.2 s.
--
-- The built-in handler emits a seek for every wheel event, and a touchpad (or
-- a single notch on some mice) sends several in a burst. PDF pages render
-- through pdftoppm slower than that, so a burst flew past pages and the
-- preview looked like it skipped them. Each kept event still moves exactly one
-- page (yazi clamps PDF seeks to ±1).
local last = 0

function Preview:scroll(event, step)
	local now = ya.time()
	if now - last < 0.2 then
		return
	end
	last = now
	ya.emit("seek", { step > 0 and 1 or -1 })
end

-- A selection belongs to the folder it was made in: changing directory clears
-- it. yazi's default keeps it across folders, so an item selected by accident
-- (Space right after launch selects whatever is first in ~) silently rode
-- along and Enter / o opened it together with — and in nvim, in front of —
-- the files picked later. Yanking (y / x, then p elsewhere) is separate from
-- selecting and still works across folders.
ps.sub("cd", function()
	ya.emit("escape", { select = true })
end)

-- "N selected" on the right of the status bar while anything is selected, so
-- it's visible what Enter / o / d will act on instead of the hovered file.
Status:children_add(function()
	local n = #cx.active.selected
	if n == 0 then
		return ""
	end
	return ui.Line { ui.Span(" 󰒆 " .. n .. " selected "):style(th.mode.select_main), ui.Span(" ") }
end, 500, Status.RIGHT)
