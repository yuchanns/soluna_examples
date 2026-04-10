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

local DISPLAY_TILES_X = 28
local DISPLAY_TILES_Y = 36
local BOARD_TILE_Y0 = 3
local BOARD_TILE_Y1 = 33
local BOARD_TILES_Y = BOARD_TILE_Y1 - BOARD_TILE_Y0 + 1

local TILE = 8
local SPRITE = 16
local SCALE = 2
local DRAW_TILE = TILE * SCALE
local DRAW_SPRITE = 24

local MAP_X = 24
local MAP_Y = 32
local BOARD_W = DISPLAY_TILES_X * DRAW_TILE
local BOARD_H = BOARD_TILES_Y * DRAW_TILE
local PANEL_X = MAP_X + BOARD_W + 24

local W = 760
local H = 560

local KEY_ESCAPE = 256
local KEY_LEFT = 263
local KEY_RIGHT = 262
local KEY_UP = 265
local KEY_DOWN = 264
local KEY_P = 80
local KEY_R = 82
local KEYSTATE_RELEASE = 0
local KEYSTATE_PRESS = 1

local DIR_RIGHT = 0
local DIR_DOWN = 1
local DIR_LEFT = 2
local DIR_UP = 3

local GHOST_BLINKY = 1
local GHOST_PINKY = 2
local GHOST_INKY = 3
local GHOST_CLYDE = 4
local NUM_GHOSTS = 4

local GHOSTSTATE_NONE = 0
local GHOSTSTATE_CHASE = 1
local GHOSTSTATE_SCATTER = 2
local GHOSTSTATE_FRIGHTENED = 3
local GHOSTSTATE_EYES = 4
local GHOSTSTATE_HOUSE = 5
local GHOSTSTATE_LEAVEHOUSE = 6
local GHOSTSTATE_ENTERHOUSE = 7

local FREEZETYPE_READY = 1 << 0
local FREEZETYPE_EAT_GHOST = 1 << 1
local FREEZETYPE_DEAD = 1 << 2
local FREEZETYPE_WON = 1 << 3

local DISABLED_TICKS = -1

local NUM_LIVES = 3
local NUM_DOTS = 244
local ANTEPORTAS_X = 14 * TILE
local ANTEPORTAS_Y = 14 * TILE + TILE // 2
local GHOST_EATEN_FREEZE_TICKS = 60
local PACMAN_EATEN_TICKS = 60
local PACMAN_DEATH_TICKS = 150
local ROUNDWON_TICKS = 4 * 60
local FRUITACTIVE_TICKS = 10 * 60
local READY_TICKS = 2 * 60 + 10
local FORCE_LEAVE_HOUSE_TICKS = 4 * 60
local FRIGHT_TICKS = 6 * 60

local SCORE_DOT = 10
local SCORE_PILL = 50
local SCORE_FRUIT = 100

local COLOR_BLACK = 0xff000000
local COLOR_WHITE = 0xffffffff
local COLOR_PANEL = 0xff101726
local COLOR_PANEL_LINE = 0xff34435a
local COLOR_WALL = 0xff1b58ff
local COLOR_WALL_INNER = 0xff081f63
local COLOR_FLOOR = 0xff04060c
local COLOR_DOOR = 0xffffb8ff
local COLOR_DOT = 0xffffd070
local COLOR_PILL = 0xfff8f8ff
local COLOR_PACMAN = 0xffffd930
local COLOR_BLINKY = 0xffff5555
local COLOR_PINKY = 0xffff92d0
local COLOR_INKY = 0xff66f6ff
local COLOR_CLYDE = 0xffffb347
local COLOR_FRIGHT = 0xff335dff
local COLOR_FRIGHT_FLASH = 0xffffffff
local COLOR_EYES = 0xffffffff
local COLOR_GREEN = 0xff58d668
local COLOR_YELLOW = 0xffffdf63
local COLOR_GRAY = 0xff9aa6bf
local COLOR_RED = 0xffff6666
local COLOR_CHERRY = 0xffff3a4c
local COLOR_STEM = 0xff78d36d

local PLAYFIELD_ROWS = {
	"0UUUUUUUUUUUU45UUUUUUUUUUUU1",
	"L............rl............R",
	"L.ebbf.ebbbf.rl.ebbbf.ebbf.R",
	"LPr  l.r   l.rl.r   l.r  lPR",
	"L.guuh.guuuh.gh.guuuh.guuh.R",
	"L..........................R",
	"L.ebbf.ef.ebbbbbbf.ef.ebbf.R",
	"L.guuh.rl.guuyxuuh.rl.guuh.R",
	"L......rl....rl....rl......R",
	"2BBBBf.rzbbf rl ebbwl.eBBBB3",
	"     L.rxuuh gh guuyl.R     ",
	"     L.rl          rl.R     ",
	"     L.rl mjs--tjn rl.R     ",
	"UUUUUh.gh i      q gh.gUUUUU",
	"      .   i      q   .      ",
	"BBBBBf.ef i      q ef.eBBBBB",
	"     L.rl okkkkkkp rl.R     ",
	"     L.rl          rl.R     ",
	"     L.rl ebbbbbbf rl.R     ",
	"0UUUUh.gh guuyxuuh gh.gUUUU1",
	"L............rl............R",
	"L.ebbf.ebbbf.rl.ebbbf.ebbf.R",
	"L.guyl.guuuh.gh.guuuh.rxuh.R",
	"LP..rl.......  .......rl..PR",
	"6bf.rl.ef.ebbbbbbf.ef.rl.eb8",
	"7uh.gh.rl.guuyxuuh.rl.gh.gu9",
	"L......rl....rl....rl......R",
	"L.ebbbbwzbbf.rl.ebbwzbbbbf.R",
	"L.guuuuuuuuh.gh.guuuuuuuuh.R",
	"L..........................R",
	"2BBBBBBBBBBBBBBBBBBBBBBBBBB3",
}

local GHOST_COLORS = {
	[GHOST_BLINKY] = COLOR_BLINKY,
	[GHOST_PINKY] = COLOR_PINKY,
	[GHOST_INKY] = COLOR_INKY,
	[GHOST_CLYDE] = COLOR_CLYDE,
}

local GHOST_NAMES = {
	[GHOST_BLINKY] = "Blinky",
	[GHOST_PINKY] = "Pinky",
	[GHOST_INKY] = "Inky",
	[GHOST_CLYDE] = "Clyde",
}

local GHOST_SCATTER_TARGETS = {
	[GHOST_BLINKY] = { x = 25, y = 0 },
	[GHOST_PINKY] = { x = 2, y = 0 },
	[GHOST_INKY] = { x = 27, y = 34 },
	[GHOST_CLYDE] = { x = 0, y = 34 },
}

local GHOST_STARTING_POS = {
	[GHOST_BLINKY] = { x = 14 * TILE, y = 14 * TILE + TILE // 2 },
	[GHOST_PINKY] = { x = 14 * TILE, y = 17 * TILE + TILE // 2 },
	[GHOST_INKY] = { x = 12 * TILE, y = 17 * TILE + TILE // 2 },
	[GHOST_CLYDE] = { x = 16 * TILE, y = 17 * TILE + TILE // 2 },
}

local GHOST_HOUSE_TARGET_POS = {
	[GHOST_BLINKY] = { x = 14 * TILE, y = 17 * TILE + TILE // 2 },
	[GHOST_PINKY] = { x = 14 * TILE, y = 17 * TILE + TILE // 2 },
	[GHOST_INKY] = { x = 12 * TILE, y = 17 * TILE + TILE // 2 },
	[GHOST_CLYDE] = { x = 16 * TILE, y = 17 * TILE + TILE // 2 },
}

local GHOST_INIT_DIR = {
	[GHOST_BLINKY] = DIR_LEFT,
	[GHOST_PINKY] = DIR_DOWN,
	[GHOST_INKY] = DIR_UP,
	[GHOST_CLYDE] = DIR_UP,
}

local GHOST_DOT_LIMIT = {
	[GHOST_BLINKY] = 0,
	[GHOST_PINKY] = 0,
	[GHOST_INKY] = 30,
	[GHOST_CLYDE] = 60,
}

local GHOST_SCORE_TEXT = {
	[200] = "200",
	[400] = "400",
	[800] = "800",
	[1600] = "1600",
}

local LEVELSPEC = {
	fruit_name = "Cherries",
	bonus_score = SCORE_FRUIT,
	fright_ticks = FRIGHT_TICKS,
}

local function trigger()
	return { tick = DISABLED_TICKS }
end

local function disable(t)
	t.tick = DISABLED_TICKS
end

local function start(t, now_tick)
	t.tick = now_tick
end

local function start_after(t, now_tick, delay)
	t.tick = now_tick + delay
end

local function since(t, now_tick)
	if t.tick == DISABLED_TICKS then
		return DISABLED_TICKS
	end
	return now_tick - t.tick
end

local function now(t, now_tick)
	return t.tick == now_tick
end

local function before(t, now_tick, ticks)
	local s = since(t, now_tick)
	return s ~= DISABLED_TICKS and s < ticks
end

local function after(t, now_tick, ticks)
	local s = since(t, now_tick)
	return s ~= DISABLED_TICKS and s >= ticks
end

local function after_once(t, now_tick, ticks)
	return since(t, now_tick) == ticks
end

local function clamp(v, min_v, max_v)
	if v < min_v then
		return min_v
	end
	if v > max_v then
		return max_v
	end
	return v
end

local function vec(x, y)
	return { x = x, y = y }
end

local function add_i2(a, b)
	return { x = a.x + b.x, y = a.y + b.y }
end

local function sub_i2(a, b)
	return { x = a.x - b.x, y = a.y - b.y }
end

local function mul_i2(a, s)
	return { x = a.x * s, y = a.y * s }
end

local function equal_i2(a, b)
	return a.x == b.x and a.y == b.y
end

local function nearequal_i2(a, b, tolerance)
	return math.abs(a.x - b.x) <= tolerance and math.abs(a.y - b.y) <= tolerance
end

local function squared_distance_i2(a, b)
	local dx = b.x - a.x
	local dy = b.y - a.y
	return dx * dx + dy * dy
end

local function dir_to_vec(dir)
	if dir == DIR_RIGHT then
		return vec(1, 0)
	elseif dir == DIR_DOWN then
		return vec(0, 1)
	elseif dir == DIR_LEFT then
		return vec(-1, 0)
	else
		return vec(0, -1)
	end
end

local function reverse_dir(dir)
	if dir == DIR_RIGHT then
		return DIR_LEFT
	elseif dir == DIR_DOWN then
		return DIR_UP
	elseif dir == DIR_LEFT then
		return DIR_RIGHT
	else
		return DIR_DOWN
	end
end

local function dir_name(dir)
	if dir == DIR_RIGHT then
		return "right"
	elseif dir == DIR_DOWN then
		return "down"
	elseif dir == DIR_LEFT then
		return "left"
	end
	return "up"
end

local function pixel_to_tile_pos(pos)
	return { x = pos.x // TILE, y = pos.y // TILE }
end

local function clamped_tile_pos(tile_pos)
	local out = { x = tile_pos.x, y = tile_pos.y }
	if out.x < 0 then
		out.x = 0
	elseif out.x >= DISPLAY_TILES_X then
		out.x = DISPLAY_TILES_X - 1
	end
	if out.y < BOARD_TILE_Y0 then
		out.y = BOARD_TILE_Y0
	elseif out.y > BOARD_TILE_Y1 then
		out.y = BOARD_TILE_Y1
	end
	return out
end

local function dist_to_tile_mid(pos)
	return {
		x = TILE // 2 - pos.x % TILE,
		y = TILE // 2 - pos.y % TILE,
	}
end

local function screen_from_actor_pos(pos)
	return MAP_X + pos.x * SCALE, MAP_Y + (pos.y - BOARD_TILE_Y0 * TILE) * SCALE
end

local function screen_from_tile_pos(tile_pos)
	return MAP_X + tile_pos.x * DRAW_TILE, MAP_Y + (tile_pos.y - BOARD_TILE_Y0) * DRAW_TILE
end

local function rgba(color)
	local a = color >> 24 & 0xff
	local r = color >> 16 & 0xff
	local g = color >> 8 & 0xff
	local b = color & 0xff
	return string.pack("BBBB", r, g, b, a)
end

local function create_canvas(width, height)
	local pixels = {}
	local clear = rgba(0)
	for i = 1, width * height do
		pixels[i] = clear
	end

	local canvas = {}

	function canvas.set_pixel(x, y, color)
		if x < 0 or x >= width or y < 0 or y >= height then
			return
		end
		pixels[y * width + x + 1] = rgba(color)
	end

	function canvas.fill_rect(x, y, w, h, color)
		local from_x = math.max(0, x)
		local from_y = math.max(0, y)
		local to_x = math.min(width - 1, x + w - 1)
		local to_y = math.min(height - 1, y + h - 1)
		for py = from_y, to_y do
			local base = py * width
			for px = from_x, to_x do
				pixels[base + px + 1] = rgba(color)
			end
		end
	end

	function canvas.fill_disc(cx, cy, radius, color)
		local rr = radius * radius
		for py = cy - radius, cy + radius do
			for px = cx - radius, cx + radius do
				local dx = px - cx
				local dy = py - cy
				if dx * dx + dy * dy <= rr then
					canvas.set_pixel(px, py, color)
				end
			end
		end
	end

	function canvas.to_content()
		return table.concat(pixels)
	end

	return canvas
end

local sprite_serial = 0

local function load_runtime_sprite(prefix, content, width, height, dx, dy)
	sprite_serial = sprite_serial + 1
	local filename = string.format("@pacman_%s_%d", prefix, sprite_serial)
	soluna.preload {
		filename = filename,
		content = content,
		w = width,
		h = height,
	}
	local sprites = soluna.load_sprites {
		{
			name = prefix,
			filename = filename,
			x = dx or 0,
			y = dy or 0,
		},
	}
	return sprites[prefix]
end

local wall_chars = {}
for _, ch in ipairs({
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"U", "L", "R", "B", "b", "e", "f", "g", "h", "l", "r", "u",
	"w", "x", "y", "z", "m", "n", "o", "p", "j", "i", "k", "q", "s", "t",
}) do
	wall_chars[ch] = true
end

local board_template = {}
local dot_rows_source = {}
local pill_positions = {}

for row_index, line in ipairs(PLAYFIELD_ROWS) do
	local tile_y = BOARD_TILE_Y0 + row_index - 1
	board_template[tile_y] = {}
	dot_rows_source[tile_y] = {}
	for x = 0, DISPLAY_TILES_X - 1 do
		local ch = line:sub(x + 1, x + 1)
		local cell = {
			char = ch,
			wall = wall_chars[ch] or false,
			door = ch == "-",
			dot = ch == ".",
			pill = ch == "P",
		}
		board_template[tile_y][x] = cell
		if cell.pill then
			pill_positions[#pill_positions + 1] = { x = x, y = tile_y }
		end
	end
end

local function copy_board()
	local out = {}
	for y = BOARD_TILE_Y0, BOARD_TILE_Y1 do
		out[y] = {}
		for x = 0, DISPLAY_TILES_X - 1 do
			local src = board_template[y][x]
			out[y][x] = {
				char = src.char,
				wall = src.wall,
				door = src.door,
				dot = src.dot,
				pill = src.pill,
			}
		end
	end
	return out
end

local function create_background_content()
	local canvas = create_canvas(W, H)
	canvas.fill_rect(0, 0, W, H, COLOR_BLACK)
	canvas.fill_rect(MAP_X - 10, MAP_Y - 10, BOARD_W + 20, BOARD_H + 20, COLOR_PANEL)
	canvas.fill_rect(MAP_X - 6, MAP_Y - 6, BOARD_W + 12, BOARD_H + 12, COLOR_PANEL_LINE)
	canvas.fill_rect(MAP_X, MAP_Y, BOARD_W, BOARD_H, COLOR_FLOOR)
	canvas.fill_rect(PANEL_X - 12, MAP_Y - 10, W - PANEL_X - 12, BOARD_H + 20, COLOR_PANEL)
	canvas.fill_rect(PANEL_X - 12, MAP_Y - 10, W - PANEL_X - 12, 2, COLOR_PANEL_LINE)

	for y = BOARD_TILE_Y0, BOARD_TILE_Y1 do
		for x = 0, DISPLAY_TILES_X - 1 do
			local cell = board_template[y][x]
			local sx, sy = screen_from_tile_pos({ x = x, y = y })
			if cell.wall then
				canvas.fill_rect(sx, sy, DRAW_TILE, DRAW_TILE, COLOR_WALL)
				canvas.fill_rect(sx + 3, sy + 3, DRAW_TILE - 6, DRAW_TILE - 6, COLOR_WALL_INNER)
			elseif cell.door then
				canvas.fill_rect(sx, sy, DRAW_TILE, DRAW_TILE, COLOR_FLOOR)
				canvas.fill_rect(sx, sy + DRAW_TILE // 2 - 2, DRAW_TILE, 4, COLOR_DOOR)
			end
		end
	end

	return canvas:to_content(), W, H
end

local function create_dot_row_content(source_board, tile_y)
	local canvas = create_canvas(BOARD_W, DRAW_TILE)
	local has_dot = false
	for x = 0, DISPLAY_TILES_X - 1 do
		local cell = source_board[tile_y][x]
		if cell.dot then
			local sx = x * DRAW_TILE
			canvas.fill_rect(sx + DRAW_TILE // 2 - 2, DRAW_TILE // 2 - 2, 4, 4, COLOR_DOT)
			has_dot = true
		end
	end
	if not has_dot then
		return nil
	end
	return canvas:to_content(), BOARD_W, DRAW_TILE
end

local function create_pill_content()
	local canvas = create_canvas(DRAW_TILE, DRAW_TILE)
	canvas.fill_disc(DRAW_TILE // 2, DRAW_TILE // 2, 5, COLOR_PILL)
	return canvas:to_content(), DRAW_TILE, DRAW_TILE
end

local function create_fruit_content()
	local canvas = create_canvas(DRAW_TILE, DRAW_TILE)
	canvas.fill_disc(6, 10, 4, COLOR_CHERRY)
	canvas.fill_disc(11, 8, 4, COLOR_CHERRY)
	canvas.fill_rect(8, 3, 2, 5, COLOR_STEM)
	canvas.fill_rect(10, 2, 3, 2, COLOR_STEM)
	return canvas:to_content(), DRAW_TILE, DRAW_TILE
end

local function wrap_angle(rad)
	while rad <= -math.pi do
		rad = rad + math.pi * 2
	end
	while rad > math.pi do
		rad = rad - math.pi * 2
	end
	return rad
end

local function dir_angle(dir)
	if dir == DIR_UP then
		return -math.pi * 0.5
	elseif dir == DIR_LEFT then
		return math.pi
	elseif dir == DIR_DOWN then
		return math.pi * 0.5
	end
	return 0
end

local function create_pacman_content(dir, mouth_open)
	local size = DRAW_SPRITE
	local cx = size // 2
	local cy = size // 2
	local radius = size // 2 - 3
	local mouth = mouth_open and 0.58 or 0.08
	local face = dir_angle(dir)
	local canvas = create_canvas(size, size)

	for py = 0, size - 1 do
		for px = 0, size - 1 do
			local dx = px - cx
			local dy = py - cy
			if dx * dx + dy * dy <= radius * radius then
				local angle = math.atan(dy, dx)
				local diff = math.abs(wrap_angle(angle - face))
				if diff > mouth then
					canvas.set_pixel(px, py, COLOR_PACMAN)
				end
			end
		end
	end

	local eye_x = cx + 2
	local eye_y = cy - 4
	if dir == DIR_LEFT then
		eye_x = cx - 2
	elseif dir == DIR_UP then
		eye_x = cx - 2
		eye_y = cy - 5
	elseif dir == DIR_DOWN then
		eye_x = cx + 2
		eye_y = cy - 1
	end
	canvas.fill_disc(eye_x, eye_y, 1, COLOR_BLACK)
	return canvas:to_content(), size, size
end

local function create_pacman_death_content(frame)
	local size = DRAW_SPRITE
	local cx = size // 2
	local cy = size // 2
	local radius = size // 2 - 3
	local canvas = create_canvas(size, size)
	local mouth = 0.12 + frame * 0.26

	for py = 0, size - 1 do
		for px = 0, size - 1 do
			local dx = px - cx
			local dy = py - cy
			if dx * dx + dy * dy <= radius * radius then
				local angle = math.atan(dy, dx)
				local diff = math.abs(wrap_angle(angle))
				if diff > mouth then
					canvas.set_pixel(px, py, COLOR_PACMAN)
				end
			end
		end
	end
	return canvas:to_content(), size, size
end

local function create_ghost_content(body_color, dir, mode)
	local size = DRAW_SPRITE
	local cx = size // 2
	local cy = size // 2
	local head_radius = size // 2 - 3
	local body_left = cx - head_radius
	local body_top = cy - head_radius // 2
	local body_width = head_radius * 2 + 1
	local body_height = head_radius + 6
	local canvas = create_canvas(size, size)

	if mode ~= "eyes" then
		canvas.fill_disc(cx, cy - head_radius // 2, head_radius, body_color)
		canvas.fill_rect(body_left, body_top, body_width, body_height, body_color)
		canvas.fill_rect(body_left, cy + head_radius - 1, 3, 3, body_color)
		canvas.fill_rect(cx - 1, cy + head_radius - 1, 3, 3, body_color)
		canvas.fill_rect(cx + head_radius - 2, cy + head_radius - 1, 3, 3, body_color)
	end

	if mode == "frightened" then
		canvas.fill_rect(cx - 6, cy - 3, 4, 4, COLOR_WHITE)
		canvas.fill_rect(cx + 2, cy - 3, 4, 4, COLOR_WHITE)
		canvas.fill_rect(cx - 5, cy + 4, 2, 2, COLOR_WHITE)
		canvas.fill_rect(cx - 1, cy + 5, 2, 2, COLOR_WHITE)
		canvas.fill_rect(cx + 3, cy + 4, 2, 2, COLOR_WHITE)
	else
		canvas.fill_rect(cx - 6, cy - 4, 4, 6, COLOR_EYES)
		canvas.fill_rect(cx + 2, cy - 4, 4, 6, COLOR_EYES)

		local offset_x = 0
		local offset_y = 0
		if dir == DIR_LEFT then
			offset_x = -1
		elseif dir == DIR_RIGHT then
			offset_x = 1
		elseif dir == DIR_UP then
			offset_y = -1
		else
			offset_y = 1
		end

		canvas.fill_rect(cx - 5 + offset_x, cy - 1 + offset_y, 2, 2, COLOR_BLACK)
		canvas.fill_rect(cx + 3 + offset_x, cy - 1 + offset_y, 2, 2, COLOR_BLACK)
	end

	return canvas:to_content(), size, size
end

local function build_sprite_assets()
	local assets = {}

	do
		local content, width, height = create_background_content()
		assets.background = load_runtime_sprite("background", content, width, height, 0, 0)
	end

	do
		local content, width, height = create_pill_content()
		assets.pill = load_runtime_sprite("pill", content, width, height, 0, 0)
	end

	do
		local content, width, height = create_fruit_content()
		assets.fruit = load_runtime_sprite("fruit", content, width, height, 0, 0)
	end

	assets.pacman = {}
	for _, dir in ipairs({ DIR_RIGHT, DIR_DOWN, DIR_LEFT, DIR_UP }) do
		assets.pacman[dir] = {}
		do
			local content, width, height = create_pacman_content(dir, false)
			assets.pacman[dir].closed = load_runtime_sprite("pacman_closed_" .. dir_name(dir), content, width, height, 0, 0)
		end
		do
			local content, width, height = create_pacman_content(dir, true)
			assets.pacman[dir].open = load_runtime_sprite("pacman_open_" .. dir_name(dir), content, width, height, 0, 0)
		end
	end

	assets.pacman_death = {}
	for frame = 1, 8 do
		local content, width, height = create_pacman_death_content(frame)
		assets.pacman_death[frame] = load_runtime_sprite("pacman_death_" .. frame, content, width, height, 0, 0)
	end

	assets.ghost = {}
	assets.ghost_eyes = {}
	for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
		assets.ghost[ghost_type] = {}
		for _, dir in ipairs({ DIR_RIGHT, DIR_DOWN, DIR_LEFT, DIR_UP }) do
			local content, width, height = create_ghost_content(GHOST_COLORS[ghost_type], dir, "normal")
			assets.ghost[ghost_type][dir] = load_runtime_sprite(
				"ghost_" .. ghost_type .. "_" .. dir_name(dir),
				content,
				width,
				height,
				0,
				0
			)
		end
	end

	for _, dir in ipairs({ DIR_RIGHT, DIR_DOWN, DIR_LEFT, DIR_UP }) do
		local content, width, height = create_ghost_content(COLOR_EYES, dir, "eyes")
		assets.ghost_eyes[dir] = load_runtime_sprite("ghost_eyes_" .. dir_name(dir), content, width, height, 0, 0)
	end

	do
		local content, width, height = create_ghost_content(COLOR_FRIGHT, DIR_LEFT, "frightened")
		assets.frightened = load_runtime_sprite("ghost_frightened", content, width, height, 0, 0)
	end
	do
		local content, width, height = create_ghost_content(COLOR_FRIGHT_FLASH, DIR_LEFT, "frightened_flash")
		assets.frightened_flash = load_runtime_sprite("ghost_frightened_flash", content, width, height, 0, 0)
	end

	return assets
end

local sprites = build_sprite_assets()

soluna.set_window_title "PacMan"

local fontid = util.font_init(soluna, font, file, {
	error_message = "No available system font for pacman",
})
local fontcobj = font.cobj()

local title_block = mattext.block(fontcobj, fontid, 28, COLOR_YELLOW, "LT")
local label_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local value_block = mattext.block(fontcobj, fontid, 18, COLOR_YELLOW, "LT")
local hint_block = mattext.block(fontcobj, fontid, 14, COLOR_GRAY, "LT")
local ready_block = mattext.block(fontcobj, fontid, 24, COLOR_YELLOW, "CV")
local over_block = mattext.block(fontcobj, fontid, 26, COLOR_RED, "CV")
local win_block = mattext.block(fontcobj, fontid, 26, COLOR_GREEN, "CV")
local ghost_score_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local fruit_score_block = mattext.block(fontcobj, fontid, 16, COLOR_YELLOW, "LT")

local label = util.label_cache()
local quad = util.quad_cache(matquad)
local view = util.fixed_view(args, W, H)

local input = {
	enabled = true,
	up = false,
	down = false,
	left = false,
	right = false,
}

local game = {
	tick = 0,
	board = copy_board(),
	dot_rows = {},
	initial_dot_rows = {},
	score = 0,
	hiscore = 0,
	round = 0,
	num_lives = NUM_LIVES,
	freeze = 0,
	num_dots_eaten = 0,
	num_ghosts_eaten = 0,
	global_dot_counter_active = false,
	global_dot_counter = 0,
	xorshift = 0x12345678,
	pacman = {
		actor = {
			dir = DIR_LEFT,
			pos = { x = 14 * TILE, y = 26 * TILE + TILE // 2 },
			anim_tick = 0,
		},
	},
	ghost = {},
	active_fruit = false,
	fruit_score_value = nil,
	fruit_score_pos = nil,
	ready_started = trigger(),
	round_started = trigger(),
	round_won = trigger(),
	game_over_trigger = trigger(),
	dot_eaten = trigger(),
	pill_eaten = trigger(),
	ghost_eaten = trigger(),
	pacman_eaten = trigger(),
	fruit_eaten = trigger(),
	force_leave_house = trigger(),
	fruit_active = trigger(),
}

local function xorshift32()
	local x = game.xorshift
	x = ((x ~ (x << 13)) & 0xffffffff)
	x = ((x ~ (x >> 17)) & 0xffffffff)
	x = ((x ~ (x << 5)) & 0xffffffff)
	game.xorshift = x
	return x
end

local function disable_game_timers()
	disable(game.ready_started)
	disable(game.round_started)
	disable(game.round_won)
	disable(game.game_over_trigger)
	disable(game.dot_eaten)
	disable(game.pill_eaten)
	disable(game.ghost_eaten)
	disable(game.pacman_eaten)
	disable(game.fruit_eaten)
	disable(game.force_leave_house)
	disable(game.fruit_active)
end

local function input_disable()
	input.enabled = false
	input.up = false
	input.down = false
	input.left = false
	input.right = false
end

local function input_enable()
	input.enabled = true
	input.up = false
	input.down = false
	input.left = false
	input.right = false
end

local function input_dir(default_dir)
	if not input.enabled then
		return default_dir
	end
	if input.up then
		return DIR_UP
	elseif input.down then
		return DIR_DOWN
	elseif input.right then
		return DIR_RIGHT
	elseif input.left then
		return DIR_LEFT
	end
	return default_dir
end

local function board_cell_at(tile_pos)
	local row = game.board[tile_pos.y]
	return row and row[tile_pos.x] or nil
end

local function is_blocking_tile(tile_pos)
	local cell = board_cell_at(tile_pos)
	return cell == nil or cell.wall or cell.door
end

local function is_dot(tile_pos)
	local cell = board_cell_at(tile_pos)
	return cell ~= nil and cell.dot
end

local function is_pill(tile_pos)
	local cell = board_cell_at(tile_pos)
	return cell ~= nil and cell.pill
end

local function is_tunnel(tile_pos)
	return tile_pos.y == 17 and (tile_pos.x <= 5 or tile_pos.x >= 22)
end

local function is_redzone(tile_pos)
	return tile_pos.x >= 11 and tile_pos.x <= 16 and (tile_pos.y == 14 or tile_pos.y == 26)
end

local function can_move(pos, wanted_dir, allow_cornering)
	local dir_vec = dir_to_vec(wanted_dir)
	local dist_mid = dist_to_tile_mid(pos)
	local move_dist_mid
	local perp_dist_mid

	if dir_vec.y ~= 0 then
		move_dist_mid = dist_mid.y
		perp_dist_mid = dist_mid.x
	else
		move_dist_mid = dist_mid.x
		perp_dist_mid = dist_mid.y
	end

	local tile_pos = pixel_to_tile_pos(pos)
	local check_pos = clamped_tile_pos(add_i2(tile_pos, dir_vec))
	local blocked = is_blocking_tile(check_pos)
	if ((not allow_cornering) and perp_dist_mid ~= 0) or (blocked and move_dist_mid == 0) then
		return false
	end
	return true
end

local function move_pos(pos, dir, allow_cornering)
	local dir_vec = dir_to_vec(dir)
	local next_pos = add_i2(pos, dir_vec)

	if allow_cornering then
		local dist_mid = dist_to_tile_mid(next_pos)
		if dir_vec.x ~= 0 then
			if dist_mid.y < 0 then
				next_pos.y = next_pos.y - 1
			elseif dist_mid.y > 0 then
				next_pos.y = next_pos.y + 1
			end
		else
			if dist_mid.x < 0 then
				next_pos.x = next_pos.x - 1
			elseif dist_mid.x > 0 then
				next_pos.x = next_pos.x + 1
			end
		end
	end

	if next_pos.x < 0 then
		next_pos.x = DISPLAY_TILES_X * TILE - 1
	elseif next_pos.x >= DISPLAY_TILES_X * TILE then
		next_pos.x = 0
	end

	return next_pos
end

local logic = {}

do
local function make_ghost(ghost_type)
	local pos = GHOST_STARTING_POS[ghost_type]
	local state = GHOSTSTATE_HOUSE
	if ghost_type == GHOST_BLINKY then
		state = GHOSTSTATE_SCATTER
	end
	return {
		type = ghost_type,
		actor = {
			dir = GHOST_INIT_DIR[ghost_type],
			pos = { x = pos.x, y = pos.y },
			anim_tick = 0,
		},
		next_dir = GHOST_INIT_DIR[ghost_type],
		target_pos = { x = 0, y = 0 },
		state = state,
		frightened = trigger(),
		eaten = trigger(),
		dot_counter = 0,
		dot_limit = GHOST_DOT_LIMIT[ghost_type],
		eat_score = 0,
	}
end

local function build_dot_row_sprite(source_board, tile_y)
	local content, width, height = create_dot_row_content(source_board, tile_y)
	if not content then
		return nil
	end
	return load_runtime_sprite("dots_row_" .. tile_y, content, width, height, 0, 0)
end

local function build_initial_dot_rows()
	for y = BOARD_TILE_Y0, BOARD_TILE_Y1 do
		game.initial_dot_rows[y] = build_dot_row_sprite(board_template, y)
		game.dot_rows[y] = game.initial_dot_rows[y]
	end
end

local function restore_initial_dot_rows()
	for y = BOARD_TILE_Y0, BOARD_TILE_Y1 do
		game.dot_rows[y] = game.initial_dot_rows[y]
	end
end

local function refresh_dot_row(tile_y)
	game.dot_rows[tile_y] = build_dot_row_sprite(game.board, tile_y)
end

local function game_round_init()
	if game.num_dots_eaten == NUM_DOTS then
		game.round = game.round + 1
		game.num_dots_eaten = 0
		game.board = copy_board()
		restore_initial_dot_rows()
		game.global_dot_counter_active = false
	else
		if game.num_lives ~= NUM_LIVES then
			game.global_dot_counter_active = true
			game.global_dot_counter = 0
		end
		game.num_lives = game.num_lives - 1
	end

	game.active_fruit = false
	game.fruit_score_value = nil
	game.fruit_score_pos = nil
	game.freeze = FREEZETYPE_READY
	game.xorshift = 0x12345678
	game.num_ghosts_eaten = 0
	disable_game_timers()
	start(game.force_leave_house, game.tick)

	game.pacman = {
		actor = {
			dir = DIR_LEFT,
			pos = { x = 14 * TILE, y = 26 * TILE + TILE // 2 },
			anim_tick = 0,
		},
	}

	game.ghost = {}
	for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
		game.ghost[ghost_type] = make_ghost(ghost_type)
	end

	input_enable()
end

local function game_init()
	game.board = copy_board()
	restore_initial_dot_rows()
	disable_game_timers()
	game.round = 0
	game.freeze = 0
	game.num_lives = NUM_LIVES
	game.global_dot_counter_active = false
	game.global_dot_counter = 0
	game.num_dots_eaten = 0
	game.num_ghosts_eaten = 0
	game.score = 0
	game.active_fruit = false
	game.fruit_score_value = nil
	game.fruit_score_pos = nil
	input_enable()
	game_round_init()
	start_after(game.round_started, game.tick, READY_TICKS)
end

local function game_pacman_should_move()
	if now(game.dot_eaten, game.tick) then
		return false
	elseif since(game.pill_eaten, game.tick) ~= DISABLED_TICKS and since(game.pill_eaten, game.tick) < 3 then
		return false
	end
	return game.tick % 8 ~= 0
end

local function game_ghost_speed(ghost)
	if ghost.state == GHOSTSTATE_HOUSE or ghost.state == GHOSTSTATE_LEAVEHOUSE then
		return game.tick & 1
	elseif ghost.state == GHOSTSTATE_FRIGHTENED then
		return game.tick & 1
	elseif ghost.state == GHOSTSTATE_EYES or ghost.state == GHOSTSTATE_ENTERHOUSE then
		return (game.tick & 1) == 1 and 1 or 2
	end

	if is_tunnel(pixel_to_tile_pos(ghost.actor.pos)) then
		return ((game.tick * 2) % 4) ~= 0 and 1 or 0
	end
	return (game.tick % 7) ~= 0 and 1 or 0
end

local function game_scatter_chase_phase()
	local t = since(game.round_started, game.tick)
	if t < 7 * 60 then
		return GHOSTSTATE_SCATTER
	elseif t < 27 * 60 then
		return GHOSTSTATE_CHASE
	elseif t < 34 * 60 then
		return GHOSTSTATE_SCATTER
	elseif t < 54 * 60 then
		return GHOSTSTATE_CHASE
	elseif t < 59 * 60 then
		return GHOSTSTATE_SCATTER
	elseif t < 79 * 60 then
		return GHOSTSTATE_CHASE
	elseif t < 84 * 60 then
		return GHOSTSTATE_SCATTER
	end
	return GHOSTSTATE_CHASE
end

local function game_update_ghost_state(ghost)
	local new_state = ghost.state

	if ghost.state == GHOSTSTATE_EYES then
		if nearequal_i2(ghost.actor.pos, { x = ANTEPORTAS_X, y = ANTEPORTAS_Y }, 1) then
			new_state = GHOSTSTATE_ENTERHOUSE
		end
	elseif ghost.state == GHOSTSTATE_ENTERHOUSE then
		if nearequal_i2(ghost.actor.pos, GHOST_HOUSE_TARGET_POS[ghost.type], 1) then
			new_state = GHOSTSTATE_LEAVEHOUSE
		end
	elseif ghost.state == GHOSTSTATE_HOUSE then
		if after_once(game.force_leave_house, game.tick, FORCE_LEAVE_HOUSE_TICKS) then
			new_state = GHOSTSTATE_LEAVEHOUSE
			start(game.force_leave_house, game.tick)
		elseif game.global_dot_counter_active then
			if ghost.type == GHOST_PINKY and game.global_dot_counter == 7 then
				new_state = GHOSTSTATE_LEAVEHOUSE
			elseif ghost.type == GHOST_INKY and game.global_dot_counter == 17 then
				new_state = GHOSTSTATE_LEAVEHOUSE
			elseif ghost.type == GHOST_CLYDE and game.global_dot_counter == 32 then
				new_state = GHOSTSTATE_LEAVEHOUSE
				game.global_dot_counter_active = false
			end
		elseif ghost.dot_counter == ghost.dot_limit then
			new_state = GHOSTSTATE_LEAVEHOUSE
		end
	elseif ghost.state == GHOSTSTATE_LEAVEHOUSE then
		if ghost.actor.pos.y == ANTEPORTAS_Y then
			new_state = GHOSTSTATE_SCATTER
		end
	else
			if before(ghost.frightened, game.tick, LEVELSPEC.fright_ticks) then
			new_state = GHOSTSTATE_FRIGHTENED
		else
			new_state = game_scatter_chase_phase()
		end
	end

	if new_state ~= ghost.state then
		if ghost.state == GHOSTSTATE_LEAVEHOUSE then
			ghost.next_dir = DIR_LEFT
			ghost.actor.dir = DIR_LEFT
		elseif ghost.state == GHOSTSTATE_ENTERHOUSE then
			disable(ghost.frightened)
		elseif ghost.state == GHOSTSTATE_SCATTER or ghost.state == GHOSTSTATE_CHASE then
			ghost.next_dir = reverse_dir(ghost.actor.dir)
		end
		ghost.state = new_state
	end
end

local function game_update_ghost_target(ghost)
	local pos = ghost.target_pos
	if ghost.state == GHOSTSTATE_SCATTER then
		pos = GHOST_SCATTER_TARGETS[ghost.type]
	elseif ghost.state == GHOSTSTATE_CHASE then
		local pm = game.pacman.actor
		local pm_pos = pixel_to_tile_pos(pm.pos)
		local pm_dir = dir_to_vec(pm.dir)
		if ghost.type == GHOST_BLINKY then
			pos = pm_pos
		elseif ghost.type == GHOST_PINKY then
			pos = add_i2(pm_pos, mul_i2(pm_dir, 4))
		elseif ghost.type == GHOST_INKY then
			local blinky_pos = pixel_to_tile_pos(game.ghost[GHOST_BLINKY].actor.pos)
			local p = add_i2(pm_pos, mul_i2(pm_dir, 2))
			local d = sub_i2(p, blinky_pos)
			pos = add_i2(blinky_pos, mul_i2(d, 2))
		elseif ghost.type == GHOST_CLYDE then
			if squared_distance_i2(pixel_to_tile_pos(ghost.actor.pos), pm_pos) > 64 then
				pos = pm_pos
			else
				pos = GHOST_SCATTER_TARGETS[GHOST_CLYDE]
			end
		end
	elseif ghost.state == GHOSTSTATE_FRIGHTENED then
		pos = { x = xorshift32() % DISPLAY_TILES_X, y = xorshift32() % DISPLAY_TILES_Y }
	elseif ghost.state == GHOSTSTATE_EYES then
		pos = { x = 13, y = 14 }
	end
	ghost.target_pos = pos
end

local function game_update_ghost_dir(ghost)
	if ghost.state == GHOSTSTATE_HOUSE then
		if ghost.actor.pos.y <= 17 * TILE then
			ghost.next_dir = DIR_DOWN
		elseif ghost.actor.pos.y >= 18 * TILE then
			ghost.next_dir = DIR_UP
		end
		ghost.actor.dir = ghost.next_dir
		return true
	elseif ghost.state == GHOSTSTATE_LEAVEHOUSE then
		local pos = ghost.actor.pos
		if pos.x == ANTEPORTAS_X then
			if pos.y > ANTEPORTAS_Y then
				ghost.next_dir = DIR_UP
			end
		else
			local mid_y = 17 * TILE + TILE // 2
			if pos.y > mid_y then
				ghost.next_dir = DIR_UP
			elseif pos.y < mid_y then
				ghost.next_dir = DIR_DOWN
			else
				ghost.next_dir = pos.x > ANTEPORTAS_X and DIR_LEFT or DIR_RIGHT
			end
		end
		ghost.actor.dir = ghost.next_dir
		return true
	elseif ghost.state == GHOSTSTATE_ENTERHOUSE then
		local pos = ghost.actor.pos
		local tile_pos = pixel_to_tile_pos(pos)
		local tgt_pos = GHOST_HOUSE_TARGET_POS[ghost.type]
		if tile_pos.y == 14 then
			if pos.x ~= ANTEPORTAS_X then
				ghost.next_dir = pos.x < ANTEPORTAS_X and DIR_RIGHT or DIR_LEFT
			else
				ghost.next_dir = DIR_DOWN
			end
		elseif pos.y == tgt_pos.y then
			ghost.next_dir = pos.x < tgt_pos.x and DIR_RIGHT or DIR_LEFT
		end
		ghost.actor.dir = ghost.next_dir
		return true
	end

	local dist_mid = dist_to_tile_mid(ghost.actor.pos)
	if dist_mid.x == 0 and dist_mid.y == 0 then
		ghost.actor.dir = ghost.next_dir

		local dir_vec = dir_to_vec(ghost.actor.dir)
		local lookahead_pos = add_i2(pixel_to_tile_pos(ghost.actor.pos), dir_vec)
		local dirs = { DIR_UP, DIR_LEFT, DIR_DOWN, DIR_RIGHT }
		local min_dist = math.huge

		for _, dir in ipairs(dirs) do
			if is_redzone(lookahead_pos) and dir == DIR_UP and ghost.state ~= GHOSTSTATE_EYES then
				goto continue
			end
			local revdir = reverse_dir(dir)
			local test_pos = clamped_tile_pos(add_i2(lookahead_pos, dir_to_vec(dir)))
			if revdir ~= ghost.actor.dir and not is_blocking_tile(test_pos) then
				local dist = squared_distance_i2(test_pos, ghost.target_pos)
				if dist < min_dist then
					min_dist = dist
					ghost.next_dir = dir
				end
			end
			::continue::
		end
	end

	return false
end

local function game_update_ghosthouse_dot_counters()
	if game.global_dot_counter_active then
		game.global_dot_counter = game.global_dot_counter + 1
	else
		for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
			local ghost = game.ghost[ghost_type]
			if ghost.dot_counter < ghost.dot_limit then
				ghost.dot_counter = ghost.dot_counter + 1
				break
			end
		end
	end
end

local function game_update_dots_eaten()
	game.num_dots_eaten = game.num_dots_eaten + 1
	if game.num_dots_eaten == NUM_DOTS then
		start(game.round_won, game.tick)
	elseif game.num_dots_eaten == 70 or game.num_dots_eaten == 170 then
		start(game.fruit_active, game.tick)
	end
end

local function game_update_actors()
	if game_pacman_should_move() then
		local actor = game.pacman.actor
		local wanted_dir = input_dir(actor.dir)
		if can_move(actor.pos, wanted_dir, true) then
			actor.dir = wanted_dir
		end
		if can_move(actor.pos, actor.dir, true) then
			actor.pos = move_pos(actor.pos, actor.dir, true)
			actor.anim_tick = actor.anim_tick + 1
		end

		local tile_pos = pixel_to_tile_pos(actor.pos)
		if is_dot(tile_pos) then
			local cell = board_cell_at(tile_pos)
			cell.dot = false
			game.score = game.score + SCORE_DOT
			start(game.dot_eaten, game.tick)
			start(game.force_leave_house, game.tick)
			game_update_dots_eaten()
			game_update_ghosthouse_dot_counters()
			refresh_dot_row(tile_pos.y)
		end
		if is_pill(tile_pos) then
			local cell = board_cell_at(tile_pos)
			cell.pill = false
			game.score = game.score + SCORE_PILL
			game_update_dots_eaten()
			start(game.pill_eaten, game.tick)
			game.num_ghosts_eaten = 0
			for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
				start(game.ghost[ghost_type].frightened, game.tick)
			end
		end

		if game.active_fruit then
			local test_pos = pixel_to_tile_pos({ x = actor.pos.x + TILE // 2, y = actor.pos.y })
			if equal_i2(test_pos, { x = 14, y = 20 }) then
				start(game.fruit_eaten, game.tick)
					game.score = game.score + LEVELSPEC.bonus_score
					game.fruit_score_value = LEVELSPEC.bonus_score
				game.fruit_score_pos = { x = 14, y = 20 }
				game.active_fruit = false
			end
		end

		for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
			local ghost = game.ghost[ghost_type]
			local ghost_tile_pos = pixel_to_tile_pos(ghost.actor.pos)
			if equal_i2(tile_pos, ghost_tile_pos) then
				if ghost.state == GHOSTSTATE_FRIGHTENED then
					ghost.state = GHOSTSTATE_EYES
					start(ghost.eaten, game.tick)
					start(game.ghost_eaten, game.tick)
					game.num_ghosts_eaten = game.num_ghosts_eaten + 1
					ghost.eat_score = 100 * (1 << game.num_ghosts_eaten)
					game.score = game.score + ghost.eat_score
					game.freeze = game.freeze | FREEZETYPE_EAT_GHOST
				elseif ghost.state == GHOSTSTATE_CHASE or ghost.state == GHOSTSTATE_SCATTER then
					start(game.pacman_eaten, game.tick)
					game.freeze = game.freeze | FREEZETYPE_DEAD
					if game.num_lives > 0 then
						start_after(game.ready_started, game.tick, PACMAN_EATEN_TICKS + PACMAN_DEATH_TICKS)
					else
						start_after(game.game_over_trigger, game.tick, PACMAN_EATEN_TICKS + PACMAN_DEATH_TICKS)
					end
				end
			end
		end
	end

	for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
		local ghost = game.ghost[ghost_type]
		game_update_ghost_state(ghost)
		game_update_ghost_target(ghost)
		local num_move_ticks = game_ghost_speed(ghost)
		for _ = 1, num_move_ticks do
			local force_move = game_update_ghost_dir(ghost)
			local actor = ghost.actor
			if force_move or can_move(actor.pos, actor.dir, false) then
				actor.pos = move_pos(actor.pos, actor.dir, false)
				actor.anim_tick = actor.anim_tick + 1
			end
		end
	end
end

local function game_tick()
	game.tick = game.tick + 1

	if now(game.ready_started, game.tick) then
		game_round_init()
		start_after(game.round_started, game.tick, READY_TICKS)
	end

	if now(game.round_started, game.tick) then
		game.freeze = game.freeze & ~FREEZETYPE_READY
	end

	if now(game.fruit_active, game.tick) then
		game.active_fruit = true
	elseif after_once(game.fruit_active, game.tick, FRUITACTIVE_TICKS) then
		game.active_fruit = false
	end

	if after_once(game.fruit_eaten, game.tick, 2 * 60) then
		game.fruit_score_value = nil
		game.fruit_score_pos = nil
	end

	if (game.freeze & FREEZETYPE_EAT_GHOST) ~= 0 and after_once(game.ghost_eaten, game.tick, GHOST_EATEN_FREEZE_TICKS) then
		game.freeze = game.freeze & ~FREEZETYPE_EAT_GHOST
	end

	if (game.freeze & (FREEZETYPE_READY | FREEZETYPE_DEAD | FREEZETYPE_WON | FREEZETYPE_EAT_GHOST)) == 0 then
		game_update_actors()
	end

	if game.score > game.hiscore then
		game.hiscore = game.score
	end

	if now(game.round_won, game.tick) then
		game.freeze = game.freeze | FREEZETYPE_WON
		start_after(game.ready_started, game.tick, ROUNDWON_TICKS)
	end

	if now(game.game_over_trigger, game.tick) then
		input_disable()
	end
end

logic.build_initial_dot_rows = build_initial_dot_rows
logic.game_init = game_init
logic.game_tick = game_tick
end

local function draw_rect(x, y, width, height, color)
	batch:add(quad { width = width, height = height, color = color }, x, y)
end

local function draw_background_and_dots()
	batch:add(sprites.background, 0, 0)

	for y = BOARD_TILE_Y0, BOARD_TILE_Y1 do
		local sprite = game.dot_rows[y]
		if sprite then
			batch:add(sprite, MAP_X, MAP_Y + (y - BOARD_TILE_Y0) * DRAW_TILE)
		end
	end

	local show_pill = game.freeze ~= 0 or ((game.tick & 0x8) ~= 0)
	if show_pill then
		for _, pos in ipairs(pill_positions) do
			if game.board[pos.y][pos.x].pill then
				local sx, sy = screen_from_tile_pos(pos)
				batch:add(sprites.pill, sx, sy)
			end
		end
	end

	if game.active_fruit then
		local sx, sy = screen_from_tile_pos({ x = 13, y = 19 })
		batch:add(sprites.fruit, sx, sy + DRAW_TILE // 2)
	end
end

local function current_pacman_sprite()
	local actor = game.pacman.actor

	if (game.freeze & FREEZETYPE_EAT_GHOST) ~= 0 then
		return nil
	elseif (game.freeze & FREEZETYPE_READY) ~= 0 then
		return sprites.pacman[actor.dir].closed
	elseif (game.freeze & FREEZETYPE_DEAD) ~= 0 then
		if after(game.pacman_eaten, game.tick, PACMAN_EATEN_TICKS) then
			local death_tick = since(game.pacman_eaten, game.tick) - PACMAN_EATEN_TICKS
			local frame = clamp(death_tick // 12 + 1, 1, #sprites.pacman_death)
			return sprites.pacman_death[frame]
		end
		return sprites.pacman[actor.dir].closed
	end

	local mouth_open = (actor.anim_tick % 4) < 2
	return mouth_open and sprites.pacman[actor.dir].open or sprites.pacman[actor.dir].closed
end

local function current_ghost_sprite(ghost)
	if (game.freeze & FREEZETYPE_DEAD) ~= 0 and after(game.pacman_eaten, game.tick, PACMAN_EATEN_TICKS) then
		return nil
	elseif (game.freeze & FREEZETYPE_WON) ~= 0 then
		return nil
	end

	if ghost.state == GHOSTSTATE_EYES then
		if before(ghost.eaten, game.tick, GHOST_EATEN_FREEZE_TICKS) then
			return false
		end
		return sprites.ghost_eyes[ghost.next_dir]
	elseif ghost.state == GHOSTSTATE_ENTERHOUSE then
		return sprites.ghost_eyes[ghost.actor.dir]
	elseif ghost.state == GHOSTSTATE_FRIGHTENED then
		if since(ghost.frightened, game.tick) > (FRIGHT_TICKS - 60) and (game.tick // 8) % 2 == 0 then
			return sprites.frightened_flash
		end
		return sprites.frightened
	end

	return sprites.ghost[ghost.type][ghost.next_dir]
end

local function draw_actors()
	local pmx, pmy = screen_from_actor_pos(game.pacman.actor.pos)
	local pacman_sprite = current_pacman_sprite()
	if pacman_sprite then
		batch:add(pacman_sprite, pmx - DRAW_SPRITE // 2, pmy - DRAW_SPRITE // 2)
	end

	for ghost_type = GHOST_BLINKY, GHOST_CLYDE do
		local ghost = game.ghost[ghost_type]
		local gx, gy = screen_from_actor_pos(ghost.actor.pos)
		local ghost_sprite = current_ghost_sprite(ghost)
		if ghost_sprite == false then
			local score_text = GHOST_SCORE_TEXT[ghost.eat_score] or tostring(ghost.eat_score)
			batch:add(label { block = ghost_score_block, text = score_text, width = 50, height = 18 }, gx - 12, gy - 8)
		elseif ghost_sprite then
			batch:add(ghost_sprite, gx - DRAW_SPRITE // 2, gy - DRAW_SPRITE // 2)
		end
	end

	if game.fruit_score_value and game.fruit_score_pos then
		local sx, sy = screen_from_tile_pos(game.fruit_score_pos)
		batch:add(label { block = fruit_score_block, text = tostring(game.fruit_score_value), width = 60, height = 18 }, sx - 6,
			sy + 8)
	end
end

local function draw_hud()
	batch:add(label { block = title_block, text = "PAC-MAN", width = 180, height = 32 }, PANEL_X, 36)
	batch:add(label { block = label_block, text = "Score", width = 120, height = 20 }, PANEL_X, 88)
	batch:add(label { block = value_block, text = tostring(game.score), width = 150, height = 22 }, PANEL_X, 110)

	batch:add(label { block = label_block, text = "Hi-Score", width = 120, height = 20 }, PANEL_X, 146)
	batch:add(label { block = value_block, text = tostring(game.hiscore), width = 150, height = 22 }, PANEL_X, 168)

	batch:add(label { block = label_block, text = "Round", width = 120, height = 20 }, PANEL_X, 204)
	batch:add(label { block = value_block, text = tostring(game.round + 1), width = 80, height = 22 }, PANEL_X, 226)

	batch:add(label { block = label_block, text = "Reserve Lives", width = 140, height = 20 }, PANEL_X, 262)
	batch:add(label { block = value_block, text = tostring(math.max(game.num_lives, 0)), width = 80, height = 22 }, PANEL_X, 284)

	batch:add(label { block = label_block, text = "Fruit", width = 120, height = 20 }, PANEL_X, 320)
	batch:add(label { block = value_block, text = LEVELSPEC.fruit_name, width = 140, height = 22 }, PANEL_X, 342)

	batch:add(label { block = label_block, text = "Controls", width = 120, height = 20 }, PANEL_X, 390)
	batch:add(label { block = hint_block, text = "Arrows: Move", width = 160, height = 18 }, PANEL_X, 412)
	batch:add(label { block = hint_block, text = "P: Pause", width = 160, height = 18 }, PANEL_X, 432)
	batch:add(label { block = hint_block, text = "R: Restart", width = 160, height = 18 }, PANEL_X, 452)
	batch:add(label { block = hint_block, text = "Esc: Quit", width = 160, height = 18 }, PANEL_X, 472)
	batch:add(label { block = hint_block, text = "Gameplay follows pacman.c logic.", width = 220, height = 18 }, PANEL_X, 506)
end

local function draw_overlay(paused)
	if paused then
		local x = MAP_X + BOARD_W // 2 - 70
		local y = MAP_Y + BOARD_H // 2 - 18
		draw_rect(x - 16, y - 10, 160, 54, COLOR_PANEL)
		draw_rect(x - 16, y - 10, 160, 2, COLOR_PANEL_LINE)
		batch:add(label { block = ready_block, text = "PAUSED", width = 160, height = 28 }, x - 16, y)
		return
	end

	if (game.freeze & FREEZETYPE_READY) ~= 0 then
		local x = MAP_X + BOARD_W // 2 - 68
		local y = MAP_Y + BOARD_H // 2 - 18
		draw_rect(x - 18, y - 10, 164, 54, COLOR_PANEL)
		draw_rect(x - 18, y - 10, 164, 2, COLOR_PANEL_LINE)
		batch:add(label { block = ready_block, text = "READY!", width = 164, height = 28 }, x - 18, y)
		return
	end

	if input.enabled == false then
		local x = MAP_X + BOARD_W // 2 - 98
		local y = MAP_Y + BOARD_H // 2 - 36
		draw_rect(x - 18, y - 12, 220, 76, COLOR_PANEL)
		draw_rect(x - 18, y - 12, 220, 2, COLOR_PANEL_LINE)
		batch:add(label { block = over_block, text = "GAME OVER", width = 220, height = 30 }, x - 18, y)
		batch:add(label { block = hint_block, text = "Press R to restart", width = 160, height = 18 }, x + 18, y + 34)
	elseif (game.freeze & FREEZETYPE_WON) ~= 0 then
		local x = MAP_X + BOARD_W // 2 - 84
		local y = MAP_Y + BOARD_H // 2 - 36
		draw_rect(x - 18, y - 12, 196, 76, COLOR_PANEL)
		draw_rect(x - 18, y - 12, 196, 2, COLOR_PANEL_LINE)
		batch:add(label { block = win_block, text = "ROUND CLEAR", width = 196, height = 30 }, x - 18, y)
	end
end

logic.build_initial_dot_rows()
logic.game_init()

local paused = false

local callback = {}

function callback.frame()
	if not paused then
		logic.game_tick()
	end

	view.begin(batch)
	draw_background_and_dots()
	draw_actors()
	draw_hud()
	draw_overlay(paused)
	view.finish(batch)
end

function callback.key(keycode, state)
	if keycode == KEY_ESCAPE and state == KEYSTATE_PRESS then
		app.quit()
		return
	end

	if keycode == KEY_R and state == KEYSTATE_PRESS then
		paused = false
		game.tick = 0
		logic.game_init()
		return
	end

	if keycode == KEY_P and state == KEYSTATE_PRESS and input.enabled then
		paused = not paused
		return
	end

	local pressed = state == KEYSTATE_PRESS
	if keycode == KEY_UP then
		input.up = pressed
	elseif keycode == KEY_DOWN then
		input.down = pressed
	elseif keycode == KEY_LEFT then
		input.left = pressed
	elseif keycode == KEY_RIGHT then
		input.right = pressed
	end
end

function callback.window_resize(w, h)
	view.resize(w, h)
end

return callback
