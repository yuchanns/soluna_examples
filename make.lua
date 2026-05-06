local lm = require "luamake"

local function detect_emcc()
	if lm.compiler == "emcc" then
		return true
	end
	return type(lm.cc) == "string" and lm.cc:find("emcc", 1, true) ~= nil
end

local osplat = (function()
	if lm.os == "windows" then
		if lm.compiler == "gcc" then
			return "mingw"
		end
		if lm.cc == "clang-cl" then
			return "clang-cl"
		end
		return "msvc"
	end
	return lm.os
end)()

local plat = detect_emcc() and "emcc" or osplat

lm.platform = plat
lm.basedir = lm:path "."
lm.rootdir = lm.basedir
lm.bindir = "src/bin"

lm:conf {
	emcc = {
		c = "gnu11",
		flags = {
			"-Wall",
			"-pthread",
			"-fPIC",
			"--use-port=emdawnwebgpu",
			"-fwasm-exceptions",
		},
		links = {
			"idbfs.js",
		},
		ldflags = {
			"--use-port=emdawnwebgpu",
			"-s ALLOW_MEMORY_GROWTH",
			"-s FORCE_FILESYSTEM=1",
			"-s USE_PTHREADS=1",
			"-fwasm-exceptions",
		},
		defines = {
			"_POSIX_C_SOURCE=200809L",
			"_GNU_SOURCE",
		},
	},
}

lm:import "clibs/extlua/make.lua"

lm:default "extlua_material"
