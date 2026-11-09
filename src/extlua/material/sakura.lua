local render = require "soluna.render"
local matext = require "soluna.material.ext"
local matsakura = require "ext.material.sakura"

local ctx = ...
local state = ctx.state

matsakura.set_material_id(ctx.id)

local inst_buffer = render.buffer {
	type = "vertex",
	usage = "stream",
	label = "extlua-sakura-instance",
	size = matsakura.instance_size * ctx.settings.draw_instance,
}

local bindings = render.bindings()
bindings:vbuffer(0, inst_buffer)
bindings:sampler(0, render.sampler {
	label = "extlua-sakura-sampler",
	min_filter = "linear",
	mag_filter = "linear",
	wrap_u = "edge",
	wrap_v = "edge",
})

local material = matext.new {
	id = ctx.id,
	instance_size = matsakura.instance_size,
	inst_buffer = inst_buffer,
	bindings = bindings,
	uniform = state.uniform,
	sr_buffer = state.srbuffer_mem,
	sprite_bank = ctx.arg.bank_ptr,
	texture_views = state.views,
	texture_view_slot = 0,
	hooks = matsakura.hooks,
	blend = false,
	label = "extlua-sakura-pipeline",
}

local textures = {}
state.sakura_textures = textures

local draw = material.draw

function material.draw(ptr, n, tex)
	local views = state.views
	for i = 1, 3 do
		bindings:view(i, views[(textures[i] or tex) + 1])
		textures[i] = nil
	end
	draw(ptr, n, tex)
end

return material
