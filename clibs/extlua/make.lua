local lm = require "luamake"
local compile_shader = require "compile_shader"

local objdeps = {}
compile_shader(objdeps)

lm:dll "extlua_material" {
	sources = {
		"soluna/extlua/extlua.c",
		"soluna/extlua/sokolapi.c",
		"soluna/extlua/solunaapi.c",
		"clibs/extlua/radial_shape.c",
	},
	objdeps = objdeps,
	includes = {
		"soluna/3rd/lua",
		"soluna/3rd",
		"soluna/extlua",
		"build",
	},
}
