-- Markdown previewer: renders the hovered file through glow.
--
-- Written locally instead of using Reledia/glow.yazi, which still calls
-- `ya.mgr_emit` / `ya.preview_widgets` — both gone in yazi 26.x. Same shape as
-- the built-in `code` previewer: read only the lines the pane can show, and
-- fall back to `code` (plain text) if glow is missing or fails.
local M = {}

function M:peek(job)
	local child = Command("glow")
		:arg({ "--style", "dark", "--width", tostring(job.area.w), tostring(job.file.url) })
		:env("CLICOLOR_FORCE", "1")
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:spawn()
	if not child then
		return require("code"):peek(job)
	end

	local limit = job.area.h
	local i, lines = 0, ""
	repeat
		local next, event = child:read_line()
		if event == 1 then
			child:start_kill()
			return require("code"):peek(job)
		elseif event ~= 0 then
			break
		end
		i = i + 1
		if i > job.skip then
			lines = lines .. next
		end
	until i >= job.skip + limit
	child:start_kill()

	if job.skip > 0 and i < job.skip + limit then
		ya.emit("peek", { math.max(0, i - limit), only_if = job.file.url, upper_bound = true })
	else
		ya.preview_widget(job, ui.Text.parse(lines):area(job.area))
	end
end

function M:seek(job) require("code"):seek(job) end

return M
