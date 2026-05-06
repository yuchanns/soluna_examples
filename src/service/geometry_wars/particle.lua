local ltask = require "ltask"
local soluna = require "soluna"
local spritemgr = require "soluna.spritemgr"
local matmask = require "soluna.material.mask"

global require, assert, ipairs, math, string, table, type

local MASK_SIZE <const> = 32
local MAX_PARTICLES <const> = 800
local DEFAULT_DT <const> = 1.0 / 60.0
local DRAG <const> = 4.0
local PARTICLE_GLOW_ALPHA <const> = 80
local PARTICLE_CORE_ALPHA <const> = 120
local FULL_CIRCLE <const> = math.pi * 2.0
local EMPTY <const> = {}

local batches = {
	spritemgr.newbatch(),
	spritemgr.newbatch(),
}
local particles = {}
local masks = {}
local render
local batch_id
local circle
local current_batch
local current_index = 1
local active_n = 0
local ticking = false
local inited = false
local quit = false

local frame = {
	dt = DEFAULT_DT,
	visible = false,
	view_scale = 1.0,
	view_offset_x = 0.0,
	view_offset_y = 0.0,
	camera_x = 0.0,
	camera_y = 0.0,
	shake_x = 0.0,
	shake_y = 0.0,
	screen_shake_y = 0.0,
}

local function argb(a, r, g, b)
	return (a << 24) | (r << 16) | (g << 8) | b
end

local function unpack_argb(color)
	local a = color >> 24 & 0xff
	local r = color >> 16 & 0xff
	local g = color >> 8 & 0xff
	local b = color & 0xff
	return a, r, g, b
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

local function quantize_byte(value, step)
	local q = math.floor((value + step * 0.5) / step) * step
	return clamp(q, 0, 255)
end

local function sample(min_v, max_v)
	if min_v == nil then
		return 0
	end
	if max_v == nil then
		return min_v
	end
	return min_v + math.random() * (max_v - min_v)
end

local function sample_component(value, default)
	if value == nil then
		return default
	end
	if type(value) == "table" then
		return sample(value[1], value[2])
	end
	return value
end

local function particle_alpha(color, alpha)
	local _, r, g, b = unpack_argb(color)
	return argb(quantize_byte(alpha, 16), r, g, b)
end

local function sample_color(emitter)
	local colors = emitter.colors
	if colors ~= nil and #colors > 0 then
		return colors[math.random(1, #colors)]
	end
	if emitter.color ~= nil then
		return emitter.color
	end

	local range = emitter.color_range
	if range == nil then
		return 0xffffffff
	end
	local step = range.step or 16
	return argb(
		quantize_byte(sample_component(range.a, 255), step),
		quantize_byte(sample_component(range.r, 255), step),
		quantize_byte(sample_component(range.g, 255), step),
		quantize_byte(sample_component(range.b, 255), step)
	)
end

local function build_circle_mask()
	local pixels = {}
	local radius = MASK_SIZE * 0.5 - 1
	local radius_sq = radius * radius
	local cx = MASK_SIZE * 0.5
	local cy = MASK_SIZE * 0.5

	for y = 0, MASK_SIZE - 1 do
		for x = 0, MASK_SIZE - 1 do
			local dx = x + 0.5 - cx
			local dy = y + 0.5 - cy
			local alpha = dx * dx + dy * dy <= radius_sq and 255 or 0
			pixels[#pixels + 1] = string.pack("BBBB", 255, 255, 255, alpha)
		end
	end

	soluna.preload {
		filename = "@particle_emitter_circle",
		content = table.concat(pixels),
		w = MASK_SIZE,
		h = MASK_SIZE,
	}

	return assert(soluna.load_sprites {
		{
			name = "circle",
			filename = "@particle_emitter_circle",
			x = -0.5,
			y = -0.5,
		},
	}.circle)
end

local function masked(color)
	local m = masks[color]
	if m == nil then
		m = matmask.mask(circle, color)
		masks[color] = m
	end
	return m
end

local function draw_masked_circle(batch, color, radius, x, y)
	batch:layer(radius * 2.0 / MASK_SIZE, x, y)
	batch:add(masked(color))
	batch:layer()
end

local function spawn_particle(x, y, vx, vy, color, life, size)
	if life <= 0 or size <= 0 then
		return
	end

	for i = 1, MAX_PARTICLES do
		local particle = particles[i]
		if particle.life <= 0 then
			active_n = active_n + 1
			particle.x = x
			particle.y = y
			particle.vx = vx
			particle.vy = vy
			particle.color = color
			particle.life = life
			particle.max_life = life
			particle.size = size
			return
		end
	end
end

local function emitter_angle(emitter, index, count)
	if emitter.radial then
		return (emitter.angle or 0.0) + (index - 1) * FULL_CIRCLE / count
	end

	local spread = emitter.spread or 0.0
	return (emitter.angle or 0.0) + (math.random() - 0.5) * spread
end

local function emit(emitter)
	local count = emitter.count or 1
	local x = emitter.x or 0.0
	local y = emitter.y or 0.0

	for i = 1, count do
		local angle = emitter_angle(emitter, i, count)
		local speed = sample(emitter.speed_min, emitter.speed_max)
		spawn_particle(
			x,
			y,
			math.cos(angle) * speed,
			math.sin(angle) * speed,
			sample_color(emitter),
			sample(emitter.life_min, emitter.life_max),
			sample(emitter.size_min, emitter.size_max)
		)
	end
end

local function update_particles(dt)
	for i = 1, MAX_PARTICLES do
		local particle = particles[i]
		if particle.life > 0 then
			particle.life = particle.life - dt
			particle.vx = particle.vx * (1.0 - DRAG * dt)
			particle.vy = particle.vy * (1.0 - DRAG * dt)
			particle.x = particle.x + particle.vx * dt
			particle.y = particle.y + particle.vy * dt
			if particle.life <= 0 then
				particle.life = 0
				active_n = active_n - 1
			end
		end
	end
end

local function draw_particles(batch)
	if not frame.visible or active_n <= 0 then
		return
	end

	batch:layer(frame.view_scale, frame.view_offset_x, frame.view_offset_y)
	batch:layer(0, frame.screen_shake_y)
	batch:layer(-frame.camera_x + frame.shake_x, -frame.camera_y + frame.shake_y)

	for i = 1, MAX_PARTICLES do
		local particle = particles[i]
		if particle.life > 0 then
			local alpha = particle.life / particle.max_life
			local size = particle.size * alpha
			if size > 0.5 and size < 20 then
				local x = particle.x
				local y = particle.y
				draw_masked_circle(batch, particle.color, size, x, y)
				if size > 1.5 and alpha > 0.2 then
					draw_masked_circle(
						batch,
						particle_alpha(particle.color, alpha * PARTICLE_GLOW_ALPHA),
						size * 2.5,
						x,
						y
					)
				end
				if alpha > 0.6 and size > 2 then
					draw_masked_circle(
						batch,
						argb(quantize_byte(alpha * PARTICLE_CORE_ALPHA, 16), 255, 255, 255),
						size * 1.3,
						x,
						y
					)
				end
			end
		end
	end

	batch:layer()
	batch:layer()
	batch:layer()
end

local function clear_particles()
	for i = 1, MAX_PARTICLES do
		local particle = particles[i]
		particle.life = 0
		particle.max_life = 0
	end
	active_n = 0
end

local S = {}

function S.init()
	if inited then
		return
	end

	inited = true
	render = ltask.uniqueservice "render"
	batch_id = ltask.call(render, "register_batch", ltask.self())
	local _, now = ltask.now()
	math.randomseed(now + 0x6765)
	circle = build_circle_mask()
	current_batch = batches[current_index]
	current_batch:reset()

	ltask.fork(function()
		while not quit do
			if not ticking then
				ticking = true
				ltask.send(ltask.self(), "tick")
			end
			ltask.call(render, "submit_batch", batch_id, current_batch:ptr())
		end
	end)

	ltask.sleep(0)
end

function S.frame(next_frame)
	next_frame = next_frame or EMPTY
	local view = next_frame.view or EMPTY
	local camera = next_frame.camera or EMPTY
	local shake = next_frame.shake or EMPTY

	frame.dt = next_frame.dt or DEFAULT_DT
	frame.visible = next_frame.visible == true
	frame.view_scale = view.scale and view.scale > 0 and view.scale or 1.0
	frame.view_offset_x = view.offset_x or 0.0
	frame.view_offset_y = view.offset_y or 0.0
	frame.camera_x = camera.x or 0.0
	frame.camera_y = camera.y or 0.0
	frame.shake_x = shake.x or 0.0
	frame.shake_y = shake.y or 0.0
	frame.screen_shake_y = shake.screen_y or 0.0
end

function S.emit(emitter)
	if inited then
		emit(emitter)
	end
end

function S.clear()
	clear_particles()
end

function S.tick()
	local index = current_index == 1 and 2 or 1
	local batch = batches[index]
	batch:reset()
	update_particles(frame.dt)
	draw_particles(batch)
	current_index = index
	current_batch = batch
	ticking = false
end

function S.quit()
	quit = true
	current_batch = nil
	S.frame = function() end
	S.emit = function() end
	S.clear = function() end
	S.tick = function() end
	S.quit = function() end
	for i = 1, #batches do
		batches[i]:release()
	end
end

for i = 1, MAX_PARTICLES do
	particles[i] = { life = 0, max_life = 0 }
end

return S
