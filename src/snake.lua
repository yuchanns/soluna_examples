local soluna = require "soluna"
local app = require "soluna.app"
local file = require "soluna.file"
local matquad = require "soluna.material.quad"
local mattext = require "soluna.material.text"
local font = require "soluna.font"
local util = require "utils"

math.randomseed(os.time())

local args = ...
local batch = args.batch

local W = 600
local H = 480

local GRID_ROWS = 20
local GRID_COLS = 20
local CELL_SIZE = 22
local MAX_SNAKE = 400

local GRID_W = GRID_COLS * CELL_SIZE
local GRID_H = GRID_ROWS * CELL_SIZE
local GRID_X = 10
local GRID_Y = 30
local INFO_X = GRID_X + GRID_W + 15

local KEY_ESCAPE = 256
local KEY_LEFT = 263
local KEY_RIGHT = 262
local KEY_UP = 265
local KEY_DOWN = 264
local KEY_P = 80
local KEY_R = 82
local KEYSTATE_RELEASE = 0
local KEYSTATE_PRESS = 1

local DIR_UP = 0
local DIR_DOWN = 1
local DIR_LEFT = 2
local DIR_RIGHT = 3

local COLOR_WHITE = 0xffffffff
local COLOR_GRAY = 0xff909090
local COLOR_LIGHT_GRAY = 0xffc0c0c0
local COLOR_DARK_GRAY = 0xff505050
local COLOR_RED = 0xffff3030
local COLOR_YELLOW = 0xffffff40
local COLOR_GREEN = 0xff30ff30
local COLOR_DARK_GREEN = 0xff158a15
local COLOR_CYAN = 0xff00ffff
local COLOR_GOLD = 0xffffd040

soluna.set_window_title "Snake"

local fontid = util.font_init(soluna, font, file, {
	error_message = "No available system font for snake",
})
local fontcobj = font.cobj()

local title_block = mattext.block(fontcobj, fontid, 32, COLOR_GREEN, "LT")
local body_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local score_block = mattext.block(fontcobj, fontid, 20, COLOR_GOLD, "LT")
local value_block = mattext.block(fontcobj, fontid, 20, COLOR_CYAN, "LT")
local hint_block = mattext.block(fontcobj, fontid, 14, COLOR_LIGHT_GRAY, "LT")
local muted_block = mattext.block(fontcobj, fontid, 14, COLOR_GRAY, "LT")
local warn_block = mattext.block(fontcobj, fontid, 16, COLOR_YELLOW, "LT")
local over_block = mattext.block(fontcobj, fontid, 18, COLOR_RED, "LT")

local label = util.label_cache()
local quad = util.quad_cache(matquad)
local view = util.fixed_view(args, W, H)

local snake_r = {}
local snake_c = {}
local snake_len = 3
local dir = DIR_RIGHT
local next_dir = DIR_RIGHT
local food_r = 5
local food_c = 15
local score = 0
local game_over = false
local paused = false

local move_interval_frames = 9
local move_timer = 0

local function place_initial_snake()
	snake_len = 3
	snake_r[1], snake_c[1] = 10, 10
	snake_r[2], snake_c[2] = 10, 9
	snake_r[3], snake_c[3] = 10, 8
end

local function spawn_food()
	local on_snake = true
	while on_snake do
		food_r = math.random(0, GRID_ROWS - 1)
		food_c = math.random(0, GRID_COLS - 1)
		on_snake = false
		for i = 1, snake_len do
			if snake_r[i] == food_r and snake_c[i] == food_c then
				on_snake = true
				break
			end
		end
	end
end

local function reset_game()
	place_initial_snake()
	dir = DIR_RIGHT
	next_dir = DIR_RIGHT
	food_r = 5
	food_c = 15
	score = 0
	game_over = false
	paused = false
	move_timer = 0
	move_interval_frames = 9
end

reset_game()

local function step_snake()
	dir = next_dir

	local new_r = snake_r[1]
	local new_c = snake_c[1]
	if dir == DIR_UP then
		new_r = new_r - 1
	elseif dir == DIR_DOWN then
		new_r = new_r + 1
	elseif dir == DIR_LEFT then
		new_c = new_c - 1
	else
		new_c = new_c + 1
	end

	if new_r < 0 or new_r >= GRID_ROWS or new_c < 0 or new_c >= GRID_COLS then
		game_over = true
		return
	end

	for i = 1, snake_len do
		if snake_r[i] == new_r and snake_c[i] == new_c then
			game_over = true
			return
		end
	end

	local ate = new_r == food_r and new_c == food_c
	if ate then
		if snake_len < MAX_SNAKE then
			snake_len = snake_len + 1
		end
	end

	for i = snake_len, 2, -1 do
		snake_r[i] = snake_r[i - 1]
		snake_c[i] = snake_c[i - 1]
	end

	snake_r[1] = new_r
	snake_c[1] = new_c

	if ate then
		score = score + 10
		if move_interval_frames > 4 then
			move_interval_frames = move_interval_frames - 1
		end
		if snake_len < GRID_ROWS * GRID_COLS then
			spawn_food()
		end
	end
end

local function draw_grid()
	for r = 0, GRID_ROWS do
		batch:add(quad { width = GRID_W, height = 1, color = COLOR_DARK_GRAY }, GRID_X, GRID_Y + r * CELL_SIZE)
	end
	for c = 0, GRID_COLS do
		batch:add(quad { width = 1, height = GRID_H, color = COLOR_DARK_GRAY }, GRID_X + c * CELL_SIZE, GRID_Y)
	end
end

local function draw_cell(row, col, color)
	batch:add(
		quad { width = CELL_SIZE - 1, height = CELL_SIZE - 1, color = color },
		GRID_X + col * CELL_SIZE + 1,
		GRID_Y + row * CELL_SIZE + 1
	)
end

local function draw_panel()
	batch:add(label { block = title_block, text = "SNAKE", width = 120, height = 40 }, GRID_X, 4)

	batch:add(label { block = body_block, text = "Score:", width = 80, height = 20 }, INFO_X, 40)
	batch:add(label { block = score_block, text = tostring(score), width = 80, height = 24 }, INFO_X, 58)

	batch:add(label { block = body_block, text = "Length:", width = 80, height = 20 }, INFO_X, 90)
	batch:add(label { block = value_block, text = tostring(snake_len), width = 80, height = 24 }, INFO_X, 108)

	batch:add(label { block = muted_block, text = "Controls:", width = 90, height = 20 }, INFO_X, 146)
	batch:add(label { block = hint_block, text = "Arrows", width = 90, height = 18 }, INFO_X, 164)
	batch:add(label { block = hint_block, text = "P: Pause", width = 90, height = 18 }, INFO_X, 180)
	batch:add(label { block = hint_block, text = "R: Restart", width = 90, height = 18 }, INFO_X, 196)
end

local function draw_paused()
	if not paused or game_over then
		return
	end
	local x = GRID_X + GRID_W / 2 - 50
	local y = GRID_Y + GRID_H / 2 - 15
	batch:add(quad { width = 100, height = 30, color = COLOR_DARK_GRAY }, x, y)
	batch:add(label { block = warn_block, text = "PAUSED", width = 70, height = 20 }, x + 20, y + 6)
end

local function draw_game_over()
	if not game_over then
		return
	end
	local x = GRID_X + GRID_W / 2 - 80
	local y = GRID_Y + GRID_H / 2 - 30
	batch:add(quad { width = 160, height = 70, color = COLOR_DARK_GRAY }, x, y)
	batch:add(quad { width = 160, height = 2, color = COLOR_WHITE }, x, y)
	batch:add(quad { width = 160, height = 2, color = COLOR_WHITE }, x, y + 68)
	batch:add(quad { width = 2, height = 70, color = COLOR_WHITE }, x, y)
	batch:add(quad { width = 2, height = 70, color = COLOR_WHITE }, x + 158, y)
	batch:add(label { block = over_block, text = "GAME OVER", width = 120, height = 22 }, x + 15, y + 8)
	batch:add(label { block = body_block, text = string.format("Score: %d", score), width = 100, height = 20 }, x + 28,
		y + 32)
	batch:add(label { block = warn_block, text = "R to restart", width = 100, height = 20 }, x + 25, y + 50)
end

local callback = {}

function callback.frame()
	view.begin(batch)

	if not game_over and not paused then
		move_timer = move_timer + 1
		if move_timer >= move_interval_frames then
			move_timer = 0
			step_snake()
		end
	end

	draw_grid()
	draw_cell(food_r, food_c, COLOR_RED)

	for i = 1, snake_len do
		local color = i == 1 and COLOR_GREEN or COLOR_DARK_GREEN
		draw_cell(snake_r[i], snake_c[i], color)
	end

	draw_panel()
	draw_paused()
	draw_game_over()

	view.finish(batch)
end

function callback.key(keycode, state)
	if state == KEYSTATE_RELEASE then
		return
	end

	if state == KEYSTATE_PRESS then
		if keycode == KEY_ESCAPE then
			app.quit()
			return
		end

		if game_over then
			if keycode == KEY_R then
				reset_game()
			end
			return
		end

		if keycode == KEY_P then
			paused = not paused
			return
		end

		if paused then
			return
		end

		if keycode == KEY_UP and dir ~= DIR_DOWN then
			next_dir = DIR_UP
		elseif keycode == KEY_DOWN and dir ~= DIR_UP then
			next_dir = DIR_DOWN
		elseif keycode == KEY_LEFT and dir ~= DIR_RIGHT then
			next_dir = DIR_LEFT
		elseif keycode == KEY_RIGHT and dir ~= DIR_LEFT then
			next_dir = DIR_RIGHT
		end
	end
end

function callback.window_resize(w, h)
	view.resize(w, h)
end

return callback
