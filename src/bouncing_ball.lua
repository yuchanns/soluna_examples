local soluna = require "soluna"
local app = require "soluna.app"
local file = require "soluna.file"
local ltask = require "ltask"
local mattext = require "soluna.material.text"
local font = require "soluna.font"
local util = require "utils"

local args = ...
local batch = args.batch

local W = 640
local H = 480

local KEY_ESCAPE = 256
local KEYSTATE_PRESS = 1

local COLOR_WHITE = 0xffffffff
local COLOR_GRAY = 0xff909090
local COLOR_RED = 0xffff3030

local BALL_RADIUS = 20
local MAX_TRAIL = 64
local INITIAL_VX = 4.0
local INITIAL_VY = 3.0

local function clamp(v, min_v, max_v)
	if v < min_v then
		return min_v
	end
	if v > max_v then
		return max_v
	end
	return v
end

local function color_rgba(r, g, b, a)
	return (a << 24) | (r << 16) | (g << 8) | b
end

local function color_rgb(color)
	local r = color >> 16 & 0xff
	local g = color >> 8 & 0xff
	local b = color & 0xff
	return r, g, b
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

	function canvas.set_pixel(px, py, color)
		if px < 0 or px >= width or py < 0 or py >= height then
			return
		end
		pixels[py * width + px + 1] = rgba(color)
	end

	function canvas.to_content()
		return table.concat(pixels)
	end

	return canvas
end

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

local function now_centis()
	local _, now = ltask.now()
	return now
end

local function create_circle_content(radius, color, alpha_scale, feather_ratio)
	local size = radius * 2 + 1
	local canvas = create_canvas(size, size)
	local r, g, b = color_rgb(color)
	local feather = math.max(1.5, radius * feather_ratio)
	local solid_radius = math.max(radius - feather, 0)

	for py = 0, size - 1 do
		local dy = py - radius
		for px = 0, size - 1 do
			local dx = px - radius
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist <= radius then
				local alpha
				if dist <= solid_radius then
					alpha = alpha_scale
				else
					local t = clamp((radius - dist) / feather, 0, 1)
					alpha = math.floor(alpha_scale * smoothstep(t) + 0.5)
				end
				if alpha > 0 then
					canvas.set_pixel(px, py, color_rgba(r, g, b, alpha))
				end
			end
		end
	end

	return canvas:to_content(), size, size
end

local function trail_radius_at(index, radius)
	local t = index / MAX_TRAIL
	local trail_radius = math.floor(2 + (radius - 1) * (t ^ 0.9) + 0.5)

	if index >= MAX_TRAIL - 3 then
		return radius + 1
	end
	if index >= MAX_TRAIL - 7 then
		return radius
	end
	if index >= MAX_TRAIL - 11 then
		return radius - 1
	end

	return trail_radius
end

local function build_ball_sprites(radius)
	local preload = {}
	local bundle = {}
	local trails = {}

	for i = 1, MAX_TRAIL do
		local t = i / MAX_TRAIL
		local trail_radius = trail_radius_at(i, radius)
		local alpha = math.floor(12 + t ^ 1.35 * 176)
		local feather_ratio = 0.72 - 0.30 * t
		local content, width, height = create_circle_content(trail_radius, COLOR_RED, alpha, feather_ratio)
		local filename = "@trail_" .. i
		preload[#preload + 1] = {
			filename = filename,
			content = content,
			w = width,
			h = height,
		}
		bundle[#bundle + 1] = {
			name = "trail_" .. i,
			filename = filename,
		}
		trails[i] = {
			name = "trail_" .. i,
			radius = trail_radius,
		}
	end

	do
		local content, width, height = create_circle_content(radius, COLOR_RED, 255, 0.22)
		preload[#preload + 1] = {
			filename = "@ball_fill",
			content = content,
			w = width,
			h = height,
		}
		bundle[#bundle + 1] = {
			name = "ball_fill",
			filename = "@ball_fill",
		}
	end

	soluna.preload(preload)
	local sprites = soluna.load_sprites(bundle)
	for i = 1, MAX_TRAIL do
		trails[i].sprite = sprites[trails[i].name]
		trails[i].name = nil
	end

	return {
		ball_fill = sprites.ball_fill,
		trails = trails,
	}
end

soluna.set_window_title "Bouncing Ball"

local sprites = build_ball_sprites(BALL_RADIUS)
local fontid = util.font_init(soluna, font, file, {
	error_message = "No available system font for bouncing_ball",
})
local fontcobj = font.cobj()

local hud_block = mattext.block(fontcobj, fontid, 16, COLOR_WHITE, "LT")
local info_block = mattext.block(fontcobj, fontid, 16, COLOR_GRAY, "LT")

local label = util.label_cache()
local view = util.fixed_view(args, W, H)

local x = 320.0
local y = 240.0
local vx = INITIAL_VX
local vy = INITIAL_VY
local r = BALL_RADIUS

local trail_x = {}
local trail_y = {}
local trail_count = 0

local fps = 0
local fps_clock = now_centis()
local fps_frames = 0

local function add_trail(px, py)
	if trail_count < MAX_TRAIL then
		trail_count = trail_count + 1
		trail_x[trail_count] = px
		trail_y[trail_count] = py
		return
	end

	for i = 1, MAX_TRAIL - 1 do
		trail_x[i] = trail_x[i + 1]
		trail_y[i] = trail_y[i + 1]
	end
	trail_x[MAX_TRAIL] = px
	trail_y[MAX_TRAIL] = py
end

local callback = {}

function callback.frame()
	view.begin(batch)

	x = x + vx
	y = y + vy

	if x - r < 0 then
		x = r
		vx = -vx
	end
	if x + r > W then
		x = W - r
		vx = -vx
	end
	if y - r < 0 then
		y = r
		vy = -vy
	end
	if y + r > H then
		y = H - r
		vy = -vy
	end

	add_trail(x, y)

	for i = 1, trail_count - 1 do
		local trail = sprites.trails[i]
		batch:add(trail.sprite, trail_x[i] - trail.radius, trail_y[i] - trail.radius)
	end

	batch:add(sprites.ball_fill, x - r, y - r)

	fps_frames = fps_frames + 1
	local now = now_centis()
	local elapsed = (now - fps_clock) / 100.0
	if elapsed >= 0.25 then
		fps = fps_frames / elapsed
		fps_frames = 0
		fps_clock = now
	end

	batch:add(label { block = hud_block, text = string.format("FPS: %.0f", fps), width = 100, height = 20 }, 10, 10)
	batch:add(
		label {
			block = info_block,
			text = string.format("Ball: %.0f, %.0f  Speed: %.1f, %.1f", x, y, vx, vy),
			width = 260,
			height = 20,
		},
		10,
		25
	)

	view.finish(batch)
end

function callback.key(keycode, state)
	if state == KEYSTATE_PRESS and keycode == KEY_ESCAPE then
		app.quit()
	end
end

function callback.window_resize(w, h)
	view.resize(w, h)
end

return callback
