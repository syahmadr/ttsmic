local InputField = require("lib.input")
local XXH = require("lib.XXHASH")
local Gradient = require("lib.gradient")

local LG = love.graphics
local LW = love.window

local FONT_SIZE        = 18
local FONT_LINE_HEIGHT = 1

local FIELD_TYPE = "normal"

local FIELD_OUTER_X      = 16
local FIELD_OUTER_Y      = 16
local FIELD_OUTER_WIDTH  = LG.getWidth() - 32
local FIELD_OUTER_HEIGHT = 48
local FIELD_PADDING_X    = 16
local FIELD_PADDING_Y    = 12

local FIELD_INNER_X      = FIELD_OUTER_X + FIELD_PADDING_X
local FIELD_INNER_Y      = FIELD_OUTER_Y + FIELD_PADDING_Y
local FIELD_INNER_WIDTH  = FIELD_OUTER_WIDTH  - 2 * FIELD_PADDING_X
local FIELD_INNER_HEIGHT = FIELD_OUTER_HEIGHT - 2 * FIELD_PADDING_Y

-- local SCROLLBAR_WIDTH = 16
local BLINK_INTERVAL  = 0.90

local HANDLE_WIDTH = 96
local HANDLE_HEIGHT = 40
local HANDLE_X = 0.5 * (LG:getWidth() - HANDLE_WIDTH)
local HANDLE_Y = LG:getHeight() - HANDLE_HEIGHT - 16

local DEFAULT_FONT = LG.newFont("assets/IBMPlexSans-Text.ttf", FONT_SIZE)
local EXTRA_FONT = LG.newFont("assets/IBMPlexMono-Regular.ttf", 12)

DEFAULT_FONT:setLineHeight(FONT_LINE_HEIGHT)

local handle = {
	dx = 0,
	dy = 0,
	startX = 0,
	startY = 0,
	displayIndex = 0,
	img = love.graphics.newImage("assets/drag_handle.png"),
	hovering = false,
	dragging = false,
	stepped = false
}
local hovering, dragging, stepped = false, false, false

local field = InputField("", FIELD_TYPE)
field:setFont(DEFAULT_FONT)
field:setDimensions(FIELD_INNER_WIDTH, FIELD_INNER_HEIGHT)

local blueGradient = Gradient.new(
    "horizontal",
    {0, 0, 0, 0},
    {0.271, 0.537, 1, 0.16}
)

local requests_channel = love.thread.getChannel("requests")
local progress_channel = love.thread.getChannel("progress")

local dl_status = {
	finished = false,
	message = ""
}

local function insideField(x, y)
	return x > FIELD_OUTER_X and x < FIELD_OUTER_X + FIELD_OUTER_WIDTH
		and y > FIELD_OUTER_Y and y < FIELD_OUTER_Y + FIELD_OUTER_HEIGHT
end

local function playTTS(filename)
	love.audio.play(love.audio.newSource(filename, "stream"))
end

function love.load()
    LG.setBackgroundColor(0.082, 0.082, 0.082)
    LG.setDefaultFilter("nearest", "nearest")
    LG.setFont(DEFAULT_FONT)
    love.keyboard.setKeyRepeat(true)

	handle.startX, handle.startY, handle.displayIndex = LW.getPosition()

	for _, device in ipairs(love.audio.getPlaybackDevices()) do
		if device == "OpenAL Soft on CABLE Input (VB-Audio Virtual Cable)" then
			local suc, res =  love.audio.setPlaybackDevice(device)
			local debugText = suc and "Found virtual cable!" or res

    		progress_channel:push({message = debugText})

			break
		end
	end
	
	local downloader_thread = love.thread.newThread("lib/post.lua")
	downloader_thread:start()
end

function love.keypressed(key, scancode, isRepeat)
	if field:keypressed(key, isRepeat) then
		-- Event was handled.
	elseif key == "return" then
		local text = string.match(field:getText(), "^%s*(.-)%s*$")

		if text == "" then return end

        field:setText("")

		local hash = XXH.xxh64(text)
		local filename = hash .. ".wav"

		if not love.filesystem.getInfo(filename) then
			requests_channel:push({
				text = text,
				filename = filename
			})
		else
    		progress_channel:push({message = "Found cached sound!"})

			playTTS(filename)
		end

	elseif key == "escape" then
		love.event.quit()
	end
end

function love.textinput(text)
	field:textinput(text)
end

function love.mousepressed(mx, my, mbutton, pressCount)
	if mx > HANDLE_X and mx < HANDLE_X + HANDLE_WIDTH and my > HANDLE_Y and my < HANDLE_Y + HANDLE_HEIGHT then
		dragging = true
		love.mouse.setRelativeMode(true)
	end

	if insideField(mx, my) then
		field:mousepressed(mx - FIELD_INNER_X, my - FIELD_INNER_Y, mbutton, pressCount)
	end
end

function love.mousemoved(mx, my, dx, dy)
	if mx > HANDLE_X and mx < HANDLE_X + HANDLE_WIDTH and my > HANDLE_Y and my < HANDLE_Y + HANDLE_HEIGHT then
		hovering = true
	else
		hovering = false
	end

	if dragging then
		handle.startX, handle.startY, handle.displayIndex = LW.getPosition()

		if stepped then
			stepped = false
			handle.dx, handle.dy = dx, dy
		else
			handle.dx, handle.dy = handle.dx + dx, handle.dy + dy
		end
	end

	field:mousemoved(mx - FIELD_INNER_X, my - FIELD_INNER_Y)
end

function love.mousereleased(mx, my, mbutton, pressCount)
	if dragging then
		dragging = false
		stepped = false
		love.mouse.setRelativeMode(false)
		love.mouse.setPosition(HANDLE_X + HANDLE_WIDTH * 0.5, HANDLE_Y + HANDLE_HEIGHT * 0.5)
	end

	field:mousereleased(mx - FIELD_INNER_X, my - FIELD_INNER_Y, mbutton)
end

function love.wheelmoved(dx, dy)
	field:wheelmoved(dx, dy)
end

function love.update(dt)
	if dragging then
        local display_w, display_h = LW.getDesktopDimensions(handle.displayIndex)
        local win_w, win_h = LG.getWidth(), LG.getHeight()

        local maximum_x = display_w - win_w
        local maximum_y = display_h - win_h

        local target_x = math.max(0, math.min(maximum_x, handle.startX + handle.dx))
        local target_y = math.max(0, math.min(maximum_y, handle.startY + handle.dy))

		hovering = true
		stepped = true
		LW.setPosition(target_x, target_y, handle.displayIndex)
	end

	field:update(dt)

	local progress_update = progress_channel:pop()

	while progress_update do
		if progress_update.finished then
			playTTS(progress_update.finished)

			dl_status.finished = false
		end
		if progress_update.message then
			dl_status.message = progress_update.message
		end
		if progress_update.error then
			dl_status.err = progress_update.error
		end

		progress_update = progress_channel:pop()
	end
end

function love.draw()
	local drawStartTime = love.timer.getTime()

	-- Drag handle
	if dragging then
		LG.setColor(1, 1, 1, 1)
		LG.rectangle("line", HANDLE_X, HANDLE_Y, HANDLE_WIDTH, HANDLE_HEIGHT)
		LG.setColor(0.322, 0.322, 0.322, 1)
		LG.rectangle("fill", HANDLE_X, HANDLE_Y, HANDLE_WIDTH, HANDLE_HEIGHT)
	elseif hovering then
		LG.setColor(0.553, 0.553, 0.553, 1)
		LG.rectangle("line", HANDLE_X, HANDLE_Y, HANDLE_WIDTH, HANDLE_HEIGHT)
		LG.setColor(0.2, 0.2, 0.2, 1)
		LG.rectangle("fill", HANDLE_X, HANDLE_Y, HANDLE_WIDTH, HANDLE_HEIGHT)
	else
		LG.setColor(0, 0, 0, 0)
		LG.rectangle("line", HANDLE_X, HANDLE_Y, HANDLE_WIDTH, HANDLE_HEIGHT)
		LG.setColor(0.149, 0.149, 0.149, 1)
		LG.rectangle("fill", HANDLE_X, HANDLE_Y, HANDLE_WIDTH, HANDLE_HEIGHT)
	end

	LG.draw(
		handle.img,
		HANDLE_X + 0.5 * (HANDLE_WIDTH - handle.img:getWidth()),
		HANDLE_Y + 0.5 * (HANDLE_HEIGHT - handle.img:getHeight())
	)

	-- Input field
	LG.setScissor(FIELD_OUTER_X, FIELD_OUTER_Y, FIELD_OUTER_WIDTH, FIELD_OUTER_HEIGHT)

	-- Background
	LG.setColor(0.149, 0.149, 0.149)
	LG.rectangle("fill", FIELD_OUTER_X, FIELD_OUTER_Y, FIELD_OUTER_WIDTH, FIELD_OUTER_HEIGHT)

	-- Selection
	LG.setColor(0, 0.471, 0.843)
	for _, selectionX, selectionY, selectionWidth, selectionHeight in field:eachSelection() do
		LG.rectangle("fill", FIELD_INNER_X + selectionX, FIELD_INNER_Y + selectionY, selectionWidth, selectionHeight)
	end

	-- Text
	LG.setFont(DEFAULT_FONT)
	LG.setColor(1, 1, 1)
	for _, lineText, lineX, lineY in field:eachVisibleLine() do
		LG.print(lineText, FIELD_INNER_X + lineX, FIELD_INNER_Y + lineY)
	end

	-- Cursor
	local cursorWidth = 2
	local cursorX, cursorY, cursorHeight = field:getCursorLayout()
	local alpha = ((field:getBlinkPhase() / BLINK_INTERVAL) % 1 < .5) and 1 or 0
	LG.setColor(1, 1, 1, alpha)
	LG.rectangle("fill", FIELD_INNER_X + cursorX - cursorWidth / 2, FIELD_INNER_Y + cursorY, cursorWidth, cursorHeight)

	LG.setScissor()

	-- Scrollbars
	-- local horiOffset, horiCoverage, vertOffset, vertCoverage = field:getScrollHandles()
	-- local horiHandleLength = horiCoverage * FIELD_OUTER_WIDTH
	-- local vertHandleLength = vertCoverage * FIELD_OUTER_HEIGHT
	-- local horiHandlePos    = horiOffset   * FIELD_OUTER_WIDTH
	-- local vertHandlePos    = vertOffset   * FIELD_OUTER_HEIGHT

	-- if vertCoverage < 1 then
	-- 	LG.setColor(0.129, 0.129, 0.133)
	-- 	LG.rectangle("fill", FIELD_OUTER_X + FIELD_OUTER_WIDTH - SCROLLBAR_WIDTH, FIELD_OUTER_Y, SCROLLBAR_WIDTH, FIELD_OUTER_HEIGHT) -- Vertical scrollbar background.
	-- 	LG.setColor(0.467, 0.467, 0.471)
	-- 	LG.rectangle("fill", FIELD_OUTER_X + FIELD_OUTER_WIDTH - SCROLLBAR_WIDTH, FIELD_OUTER_Y + vertHandlePos, SCROLLBAR_WIDTH, vertHandleLength) -- Vertical scrollbar handle.
	-- end
	
	-- Gradient
	LG.setColor(0.471, 0.663, 1)
	LG.rectangle("fill", FIELD_OUTER_X, FIELD_OUTER_Y + FIELD_OUTER_HEIGHT, FIELD_OUTER_WIDTH, 1)
	LG.draw(
		blueGradient,
		FIELD_OUTER_X,
		FIELD_OUTER_Y + FIELD_OUTER_HEIGHT - 32,
		0,
		FIELD_OUTER_WIDTH / blueGradient:getWidth(),
		32 / blueGradient:getHeight()
	)

	-- Stats
	local text = string.format(
		"Memory: %.2f MB\nDraw time: %.1f ms\nIs busy: %s",
		collectgarbage"count" / 1024,
		(love.timer.getTime() - drawStartTime) * 1000,
		tostring(field:isBusy())
	)
	LG.setFont(EXTRA_FONT)
	LG.setColor(1, 1, 1, .5)
	LG.print(text, FIELD_OUTER_X, LG.getHeight() - 3 * EXTRA_FONT:getHeight() - 16)
	LG.printf(
		dl_status.message,
		LG.getWidth() - 16 - 192,
		LG.getHeight() - 3 * EXTRA_FONT:getHeight() - 16,
		192,
		"right"
	)
end
