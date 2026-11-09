local soluna = require "soluna"
local ltask = require "ltask"
local file = require "soluna.file"
local datalist = require "soluna.datalist"
local matmask = require "soluna.material.mask"
local mattarget = require "soluna.material.target"
local matsakura = require "ext.material.sakura"

local args = ...
local batch = args.batch

local W <const> = 320
local H <const> = 200
local OX <const> = 160
local OY <const> = 40
local DAY <const> = 120
local CRICKETS <const> = 0.7
local PATH <const> = "asset/sakura/"

local OCC_X <const> = -12
local OCC_Y <const> = -12
local OCC_SIZE <const> = 128

local TREE_X <const> = 22
local TREE_Y <const> = 44
local PETAL_NORMAL <const> = 0xffa0b9ed
local MAT_PETAL <const> = 4

local EMISSIVE = {
	[0xb0702e] = 1,
	[0xc84a22] = 2,
	[0xff7a3a] = 3,
	[0xffc27a] = 4,
	[0xffb868] = 5,
}

local NONE <const> = "\0\0\0\0"

local function svg(name)
	local s = file.load(PATH .. name .. ".svg")
	if s == nil then
		return
	end
	local w, h = s:match 'width="(%d+)" height="(%d+)"'
	local img = { w = tonumber(w), h = tonumber(h) }
	for color, rects in s:gmatch '<g fill="#(%x+)">(.-)</g>' do
		local c = tonumber(color, 16)
		for rx, ry, rw, rh in rects:gmatch '<rect x="(%d+)" y="(%d+)" width="(%d+)" height="(%d+)"/>' do
			local x, y = tonumber(rx), tonumber(ry)
			for j = y, y + tonumber(rh) - 1 do
				local row = j * img.w + 1
				for i = x, x + tonumber(rw) - 1 do
					img[row + i] = c
				end
			end
		end
	end
	return img
end

local function rgba(c)
	return c and string.pack(">I3B", c, 255) or NONE
end

local scene = datalist.parse(file.load(PATH .. "scene.dl"))

local images = {}
local bundle = {}

local function image(name, w, h, content, item)
	local filename = "@sakura/" .. name
	images[#images + 1] = { filename = filename, content = content, w = w, h = h }
	item = item or {}
	item.name = name
	item.filename = filename
	bundle[#bundle + 1] = item
end

for _, s in ipairs(scene.sprites) do
	local color = svg(s.name)
	local normal = svg(s.name .. "_n")
	local height = svg(s.name .. "_h")
	local emissive = svg(s.name .. "_e") or {}
	local c, n, d = {}, {}, {}
	for i = 1, color.w * color.h do
		if color[i] then
			c[i] = rgba(color[i])
			n[i] = rgba(normal[i])
			d[i] = string.pack("BBBB", height[i] >> 16, s.material or 0, EMISSIVE[emissive[i]] or 0, 255)
		else
			c[i], n[i], d[i] = NONE, NONE, NONE
		end
	end
	image(s.name .. ".color", color.w, color.h, table.concat(c))
	image(s.name .. ".normal", color.w, color.h, table.concat(n))
	image(s.name .. ".data", color.w, color.h, table.concat(d))
end

do
	local petals = svg "petals"
	local c = {}
	for i = 1, petals.w * petals.h do
		c[i] = rgba(petals[i])
	end
	image("petals", petals.w, petals.h, table.concat(c), { size = "3x3", number = 5 })
end

do
	local size = OCC_SIZE
	local r, g, b = {}, {}, {}
	for i = 1, size * size do
		r[i], g[i], b[i] = 0, 0, 0
	end
	for _, o in ipairs(scene.occluders) do
		local img = svg(o.name .. "_occ")
		for j = 0, img.h - 1 do
			for i = 0, img.w - 1 do
				local v = img[j * img.w + i + 1]
				if v then
					local k = (o.y - OCC_Y + j) * size + o.x - OCC_X + i + 1
					r[k] = math.max(r[k], v >> 16)
					g[k] = math.max(g[k], v >> 8 & 0xff)
					b[k] = math.max(b[k], v & 0xff)
				end
			end
		end
	end
	local out = {}
	for i = 1, size * 2 * size do
		out[i] = NONE
	end
	local x = 0
	while true do
		for j = 0, size - 1 do
			for i = 0, size - 1 do
				local k = j * size + i + 1
				out[j * OCC_SIZE * 2 + x + i + 1] = string.pack("BBBB", r[k], g[k], b[k], 255)
			end
		end
		if size == 1 then
			break
		end
		local half = size // 2
		local r2, g2, b2 = {}, {}, {}
		for j = 0, half - 1 do
			for i = 0, half - 1 do
				local k = j * 2 * size + i * 2 + 1
				local k2 = k + size
				local n = j * half + i + 1
				r2[n] = (r[k] + r[k + 1] + r[k2] + r[k2 + 1] + 2) // 4
				g2[n] = (g[k] + g[k + 1] + g[k2] + g[k2 + 1] + 2) // 4
				b2[n] = (b[k] + b[k + 1] + b[k2] + b[k2 + 1] + 2) // 4
			end
		end
		x = x + size
		size = half
		r, g, b = r2, g2, b2
	end
	image("occluder", OCC_SIZE * 2, OCC_SIZE, table.concat(out))
end

soluna.preload(images)
local sprites = soluna.load_sprites(bundle)

for _, s in ipairs(scene.sprites) do
	s[1] = sprites[s.name .. ".color"]
	s[2] = sprites[s.name .. ".normal"]
	s[3] = sprites[s.name .. ".data"]
end

local gbuffer = {
	soluna.target(W, H),
	soluna.target(W, H),
	soluna.target(W, H),
}
local occ = soluna.target(OCC_SIZE * 2, OCC_SIZE)
local lit = soluna.target(W, H)
local water = soluna.target(W, H)
local bloom1 = soluna.target(W // 2, H // 2)
local bloom2 = soluna.target(W // 2, H // 2)
local final = soluna.target(W, H)

soluna.load_sounds "asset/sakura/sounds.dl"
soluna.play_sound "water"
local day_guitar = assert(soluna.play_sound "guitar_day")
local night_guitar = assert(soluna.play_sound("guitar_night", { volume = 0 }))
local crickets = assert(soluna.play_sound("crickets", { volume = 0 }))
day_guitar:seek(0)
night_guitar:seek(0)
local fade = 0
local chorus = 0

local petals = {}
for i = 1, 16 do
	local function r(k)
		local x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
		return x - math.floor(x)
	end
	petals[i] = {
		ox = (r(1) - 0.5) * 30,
		oy = (r(2) - 0.5) * 26,
		z0 = 30 + r(3) * 18,
		ph = r(4) * 12,
		sp = 0.8 + r(5) * 0.5,
		sw = r(6) * 6.28,
	}
end

local start = ltask.counter()
local time = 0
local day = 0
local offset = 0
local mouse_x, mouse_y = -1000, -1000
local cursor = 0
local dragging = false
local screen_w, scale, sx, sy

local function resize(w, h)
	screen_w = w
	scale = math.max(1, math.min(w // W, h // H))
	sx = (w - W * scale) // 2
	sy = (h - H * scale) // 2
end

resize(args.width, args.height)

local function pass(target, mode, input, ...)
	batch:add(mattarget.target(target))
	for i = 1, select("#", ...) do
		batch:add(matsakura.texture((select(i, ...))))
	end
	batch:add(matsakura.pass(input, mode, day, time, mouse_x, mouse_y))
	batch:add(mattarget.target())
end

local callback = {}

function callback.frame()
	time = ltask.counter() - start
	day = (time + offset) / DAY % 1
	local tod = 1 - math.abs(1 - day * 2)
	local x = math.min(math.max(tod * 2 - 0.5, 0), 1) * 100 // 1
	if x ~= fade then
		fade = x
		day_guitar:set_volume(math.cos(x * math.pi / 200))
		night_guitar:set_volume(math.sin(x * math.pi / 200))
	end
	local night = math.max(tod - 0.8, 0) * 5
	local v = math.min(night * 4, 1) * (0.2 + 0.8 * night) * CRICKETS * 100 // 1
	if v ~= chorus then
		chorus = v
		crickets:set_volume(v / 100)
	end
	for _, p in ipairs(petals) do
		local u = (time * p.sp + p.ph) % 12
		local x = TREE_X + p.ox + u * 2.6 + math.sin(u * 1.7 + p.sw) * 2.2
		local y = TREE_Y + p.oy + u * 3.4 + math.cos(u * 1.3 + p.sw) * 1.6
		p.z = p.z0 - u * 3.3 + math.sin(u * 2.3 + p.sw) * 1.2
		p.x = math.floor(OX + x - y) - 1
		p.y = math.floor(OY + (x + y) / 2 - p.z) - 1
		p.sprite = sprites.petals[math.floor((u * 3 + p.sw) % 5) + 1]
	end
	for layer, target in ipairs(gbuffer) do
		batch:add(mattarget.target(target))
		for _, s in ipairs(scene.sprites) do
			batch:add(s[layer], OX + s.x, OY + s.y)
		end
		for _, p in ipairs(petals) do
			if p.z >= 0.5 then
				if layer == 1 then
					batch:add(p.sprite, p.x, p.y)
				elseif layer == 2 then
					batch:add(matmask.mask(p.sprite, PETAL_NORMAL), p.x, p.y)
				else
					local height = math.floor(p.z * 2 + 0.5) + 128
					batch:add(matmask.mask(p.sprite, 0xff000000 | height << 16 | MAT_PETAL << 8), p.x, p.y)
				end
			end
		end
		batch:add(mattarget.target())
	end
	batch:add(mattarget.target(occ))
	batch:add(sprites.occluder)
	batch:add(mattarget.target())
	pass(lit, "light", gbuffer[1], gbuffer[2], gbuffer[3], occ)
	pass(water, "water", lit, gbuffer[3])
	pass(bloom1, "bright", water)
	pass(bloom2, "blur_x", bloom1)
	pass(bloom1, "blur_y", bloom2)
	pass(final, "grade", water, bloom1)
	batch:layer(scale, sx, sy)
	batch:add(final)
	batch:layer()
end

function callback.mouse_move(x, y)
	if dragging then
		offset = offset + (x - cursor) / screen_w * DAY
	end
	cursor = x
	mouse_x = (x - sx) // scale
	mouse_y = (y - sy) // scale
end

function callback.mouse_button(button, state)
	if button == 0 then
		dragging = state == 1
	end
end

callback.window_resize = resize

return callback
