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
