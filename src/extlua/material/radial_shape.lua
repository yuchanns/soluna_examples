local render = require "soluna.render"
local matext = require "soluna.material.ext"
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
bindings:view(0, state.views.storage)

return matext.new {
	id = ctx.id,
	instance_size = radial.instance_size,
	inst_buffer = inst_buffer,
	bindings = bindings,
	uniform = state.uniform,
	sr_buffer = state.srbuffer_mem,
	hooks = radial.hooks,
	label = "extlua-radial-shape-pipeline",
}
