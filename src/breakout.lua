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

local W = 640
local H = 480

local BRICK_ROWS = 6
local BRICK_COLS = 10
local BRICK_W = 58
local BRICK_H = 18
local BRICK_GAP = 4
local BRICK_OFFSET_X = 12
local BRICK_OFFSET_Y = 50

local KEY_ESCAPE = 256
local KEY_LEFT = 263
local KEY_RIGHT = 262
local KEY_SPACE = 32
local KEY_R = 82
local KEYSTATE_RELEASE = 0
local KEYSTATE_PRESS = 1

local COLOR_WHITE = 0xffffffff
local COLOR_DARK_GRAY = 0xff505050
local COLOR_RED = 0xffff3030
local COLOR_ORANGE = 0xffff9000
local COLOR_YELLOW = 0xffffff40
local COLOR_GREEN = 0xff30ff30
local COLOR_CYAN = 0xff00ffff
local COLOR_PURPLE = 0xffb040ff
local COLOR_GRAY = 0xff909090

local BRICK_COLORS = {
	COLOR_RED,
	COLOR_ORANGE,
	COLOR_YELLOW,
	COLOR_GREEN,
	COLOR_CYAN,
	COLOR_PURPLE,
}

local function clamp(v, min_v, max_v)
	if v < min_v then
		return min_v
	end
	if v > max_v then
		return max_v
	end
	return v
end

soluna.set_window_title "Breakout"

local fontid = util.font_init(soluna, font, file, {
	error_message = "No available system font for breakout",
})
local fontcobj = font.cobj()

local hud_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local lives_block = mattext.block(fontcobj, fontid, 16, COLOR_GREEN, "LT")
local bricks_block = mattext.block(fontcobj, fontid, 16, COLOR_GRAY, "LT")
local hint_block = mattext.block(fontcobj, fontid, 16, COLOR_YELLOW, "LT")
local game_over_block = mattext.block(fontcobj, fontid, 28, COLOR_RED, "LT")
local game_win_block = mattext.block(fontcobj, fontid, 28, COLOR_GREEN, "LT")

local label = util.label_cache()
local quad = util.quad_cache(matquad)
local view = util.fixed_view(args, W, H)

local bricks = {}
local pad_w = 80
local pad_h = 12
local pad_x = 280
local pad_y = 450

local ball_x = 320.0
local ball_y = 430.0
local ball_vx = 3.0
local ball_vy = -4.0
local ball_r = 5

local score = 0
local lives = 3
local total_bricks = BRICK_ROWS * BRICK_COLS
local started = false
local game_over = false
local game_win = false
local keys_down = {}

local function reset_bricks()
	total_bricks = BRICK_ROWS * BRICK_COLS
	for r = 1, BRICK_ROWS do
		bricks[r] = bricks[r] or {}
		for c = 1, BRICK_COLS do
			bricks[r][c] = true
		end
	end
end

local function reset_game()
	reset_bricks()
	score = 0
	lives = 3
	pad_x = 280
	started = false
	game_over = false
	game_win = false
	ball_x = 320.0
	ball_y = 430.0
	ball_vx = 3.0
	ball_vy = -4.0
end

reset_game()

local function update_ball_on_paddle()
	ball_x = pad_x + pad_w / 2
	ball_y = pad_y - ball_r - 1
end

local function lose_ball()
	lives = lives - 1
	if lives <= 0 then
		game_over = true
	else
		started = false
		ball_vx = 3.0
		ball_vy = -4.0
	end
end

local function update_game()
	if game_over or game_win then
		return
	end

	if keys_down[KEY_LEFT] then
		pad_x = pad_x - 6
	end
	if keys_down[KEY_RIGHT] then
		pad_x = pad_x + 6
	end
	pad_x = clamp(pad_x, 0, W - pad_w)

	if not started then
		update_ball_on_paddle()
		return
	end

	ball_x = ball_x + ball_vx
	ball_y = ball_y + ball_vy

	if ball_x - ball_r < 0 then
		ball_x = ball_r
		ball_vx = -ball_vx
	end
	if ball_x + ball_r > W then
		ball_x = W - ball_r
		ball_vx = -ball_vx
	end
	if ball_y - ball_r < 0 then
		ball_y = ball_r
		ball_vy = -ball_vy
	end
	if ball_y + ball_r > H then
		lose_ball()
		return
	end

	if ball_vy > 0
		and ball_x + ball_r > pad_x
		and ball_x - ball_r < pad_x + pad_w
		and ball_y + ball_r >= pad_y
		and ball_y + ball_r <= pad_y + pad_h + 4 then
		ball_vy = -ball_vy
		ball_y = pad_y - ball_r
		local hit_pos = (ball_x - pad_x) / pad_w
		ball_vx = (hit_pos - 0.5) * 8.0
	end

	for r = 1, BRICK_ROWS do
		for c = 1, BRICK_COLS do
			if bricks[r][c] then
				local bx = BRICK_OFFSET_X + (c - 1) * (BRICK_W + BRICK_GAP)
				local by = BRICK_OFFSET_Y + (r - 1) * (BRICK_H + BRICK_GAP)
				if ball_x + ball_r > bx and ball_x - ball_r < bx + BRICK_W
					and ball_y + ball_r > by and ball_y - ball_r < by + BRICK_H then
					bricks[r][c] = false
					total_bricks = total_bricks - 1
					score = score + 10 * (BRICK_ROWS - (r - 1))

					local overlap_left = (ball_x + ball_r) - bx
					local overlap_right = (bx + BRICK_W) - (ball_x - ball_r)
					local overlap_top = (ball_y + ball_r) - by
					local overlap_bottom = (by + BRICK_H) - (ball_y - ball_r)
					local min_overlap_x = math.min(overlap_left, overlap_right)
					local min_overlap_y = math.min(overlap_top, overlap_bottom)

					if min_overlap_x < min_overlap_y then
						ball_vx = -ball_vx
					else
						ball_vy = -ball_vy
					end

					if total_bricks <= 0 then
						game_win = true
					end
					return
				end
			end
		end
	end
end

local function draw_bricks()
	for r = 1, BRICK_ROWS do
		for c = 1, BRICK_COLS do
			if bricks[r][c] then
				local bx = BRICK_OFFSET_X + (c - 1) * (BRICK_W + BRICK_GAP)
				local by = BRICK_OFFSET_Y + (r - 1) * (BRICK_H + BRICK_GAP)
				local color = BRICK_COLORS[r]
				batch:add(quad { width = BRICK_W, height = BRICK_H, color = color }, bx, by)
				batch:add(quad { width = BRICK_W, height = 2, color = COLOR_WHITE }, bx, by)
				batch:add(quad { width = BRICK_W, height = 2, color = COLOR_WHITE }, bx, by + BRICK_H - 2)
				batch:add(quad { width = 2, height = BRICK_H, color = COLOR_WHITE }, bx, by)
				batch:add(quad { width = 2, height = BRICK_H, color = COLOR_WHITE }, bx + BRICK_W - 2, by)
			end
		end
	end
end

local function draw_ball()
	local d = ball_r * 2 + 1
	for dy = -ball_r, ball_r do
		for dx = -ball_r, ball_r do
			if dx * dx + dy * dy <= ball_r * ball_r then
				batch:add(quad { width = 1, height = 1, color = COLOR_WHITE }, ball_x + dx, ball_y + dy)
			end
		end
	end
end

local function draw_hud()
	batch:add(label { block = hud_block, text = string.format("Score: %d", score), width = 140, height = 20 }, 10, 10)
	batch:add(label { block = lives_block, text = string.format("Lives: %d", lives), width = 120, height = 20 }, 10, 28)
	batch:add(label { block = bricks_block, text = string.format("Bricks: %d", total_bricks), width = 120, height = 20 },
		W - 130, 10)
end

local function draw_launch_hint()
	if not started and not game_over and not game_win then
		batch:add(label { block = hint_block, text = "SPACE to launch", width = 140, height = 20 }, 240, 420)
	end
end

local function draw_result_panel()
	if not game_over and not game_win then
		return
	end

	local x = 200
	local y = 200
	batch:add(quad { width = 240, height = 80, color = COLOR_DARK_GRAY }, x, y)
	batch:add(quad { width = 240, height = 2, color = COLOR_WHITE }, x, y)
	batch:add(quad { width = 240, height = 2, color = COLOR_WHITE }, x, y + 78)
	batch:add(quad { width = 2, height = 80, color = COLOR_WHITE }, x, y)
	batch:add(quad { width = 2, height = 80, color = COLOR_WHITE }, x + 238, y)

	if game_over then
		batch:add(label { block = game_over_block, text = "GAME OVER", width = 170, height = 30 }, 230, 210)
	else
		batch:add(label { block = game_win_block, text = "YOU WIN!", width = 170, height = 30 }, 240, 210)
	end
	batch:add(label { block = hud_block, text = string.format("Score: %d", score), width = 100, height = 20 }, 260, 245)
	batch:add(label { block = hint_block, text = "R to restart", width = 100, height = 20 }, 245, 262)
end

local callback = {}

function callback.frame()
	view.begin(batch)
	update_game()
	draw_hud()
	draw_bricks()
	batch:add(quad { width = pad_w, height = pad_h, color = COLOR_WHITE }, pad_x, pad_y)
	draw_ball()
	draw_launch_hint()
	draw_result_panel()
	view.finish(batch)
end

function callback.key(keycode, state)
	if state == KEYSTATE_RELEASE then
		keys_down[keycode] = false
		return
	end

	keys_down[keycode] = true

	if state == KEYSTATE_PRESS then
		if keycode == KEY_ESCAPE then
			app.quit()
		elseif (game_over or game_win) and keycode == KEY_R then
			reset_game()
		elseif not started and not game_over and not game_win and keycode == KEY_SPACE then
			started = true
			ball_vx = 3.0
			ball_vy = -4.0
		end
	end
end

function callback.window_resize(w, h)
	view.resize(w, h)
end

return callback
