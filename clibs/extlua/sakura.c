#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>

#include "materialapi.h"
#include "sakura.glsl.h"

LUA_API void luaapi_init(lua_State *L);
void materialapi_init(lua_State *L);

#if defined(_WIN32)
#define EXTLUA_EXPORT __declspec(dllexport)
#else
#define EXTLUA_EXPORT __attribute__((visibility("default")))
#endif

struct pass_data {
	float time;
	uint16_t tod;
	int16_t x;
	int16_t y;
	uint16_t mode;
};

struct sakura_inst {
	float param[4];
	uint32_t mode;
};

static int material_id = 0;
static int texture_id = 0;

static material_error
submit_sakura(const struct material_item *item, void *out) {
	const struct pass_data *d = (const struct pass_data *)item->data;
	struct sakura_inst *inst = (struct sakura_inst *)out;
	inst->param[0] = d->tod / 65535.0f;
	inst->param[1] = d->time;
	inst->param[2] = d->x;
	inst->param[3] = d->y;
	inst->mode = d->mode;
	return NULL;
}

static void
pipeline_sakura(sg_pipeline_desc *desc) {
	desc->layout.attrs[ATTR_sakura_param].format = SG_VERTEXFORMAT_FLOAT4;
	desc->layout.attrs[ATTR_sakura_mode].format = SG_VERTEXFORMAT_UINT;
}

static const struct material_hook sakura_hooks[] = {
	{ "shader", { .shader = sakura_shader_desc } },
	{ "pipeline", { .pipeline = pipeline_sakura } },
	{ "submit", { .submit = submit_sakura } },
	{ NULL, { NULL } },
};

static int
lset_material_id(lua_State *L) {
	material_id = luaL_checkinteger(L, 1);
	return 0;
}

static int
lset_texture_id(lua_State *L) {
	texture_id = luaL_checkinteger(L, 1);
	return 0;
}

static int
lpass(lua_State *L) {
	static const char *modes[] = { "light", "water", "bright", "blur_x", "blur_y", "grade", NULL };
	struct pass_data d;
	d.mode = luaL_checkoption(L, 2, NULL, modes);
	d.tod = (uint16_t)(luaL_optnumber(L, 3, 0) * 65535.0 + 0.5);
	d.time = (float)luaL_optnumber(L, 4, 0);
	d.x = (int16_t)luaL_optinteger(L, 5, 0);
	d.y = (int16_t)luaL_optinteger(L, 6, 0);
	struct material_push_item item = {
		.sprite = luaL_checkinteger(L, 1) - 1,
		.data = &d,
	};
	return material_push(L, material_id, &item);
}

static int
ltexture(lua_State *L) {
	struct material_push_item item = {
		.sprite = luaL_checkinteger(L, 1) - 1,
	};
	return material_push(L, texture_id, &item);
}

static int
luaopen_ext_material_sakura(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "set_material_id", lset_material_id },
		{ "set_texture_id", lset_texture_id },
		{ "pass", lpass },
		{ "texture", ltexture },
		{ "instance_size", NULL },
		{ "hooks", NULL },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	lua_pushinteger(L, sizeof(struct sakura_inst));
	lua_setfield(L, -2, "instance_size");
	material_push_hooks(L, sakura_hooks);
	lua_setfield(L, -2, "hooks");
	return 1;
}

EXTLUA_EXPORT int
extlua_init(lua_State *L) {
	luaapi_init(L);
	materialapi_init(L);
	luaL_Reg l[] = {
		{ "ext.material.sakura", luaopen_ext_material_sakura },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	return 1;
}
