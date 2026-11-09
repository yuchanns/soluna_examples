local matsakura = require "ext.material.sakura"

local ctx = ...
local state = ctx.state

matsakura.set_texture_id(ctx.id)

local material = {}

function material.submit()
end

function material.draw(ptr, n, tex)
	local textures = state.sakura_textures
	textures[#textures + 1] = tex
end

return material
