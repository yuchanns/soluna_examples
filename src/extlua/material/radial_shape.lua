local render = require "soluna.render"
local radial = require "ext.material.radial_shape"

local ctx = ...
local state = ctx.state

radial.set_material_id(ctx.id)

local inst_buffer = render.buffer {
	type = "vertex",
	usage = "stream",
	label = "extlua-radial-shape-instance",
	size = radial.instance_size * ctx.settings.draw_instance,
}

local bindings = render.bindings()
bindings:vbuffer(0, inst_buffer)

local cobj = radial.new {
	inst_buffer = inst_buffer,
	bindings = bindings,
	uniform = state.uniform,
	tmp_buffer = ctx.tmp_buffer,
}

local material = {}

function material.reset()
	cobj:reset()
end

function material.submit(ptr, n)
	cobj:submit(ptr, n)
end

function material.draw(ptr, n)
	cobj:draw(ptr, n)
end

return material
