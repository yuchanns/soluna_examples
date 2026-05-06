#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <stddef.h>

#include "sokol/sokol_gfx.h"
#include "radial_shape.glsl.h"
#include "solunaapi.h"

LUA_API void luaapi_init(lua_State *L);
void sokolapi_init(lua_State *L);
void solunaapi_init(lua_State *L);

#if defined(_WIN32)
#define EXTLUA_EXPORT __declspec(dllexport)
#else
#define EXTLUA_EXPORT __attribute__((visibility("default")))
#endif

#define RADIAL_CORNER_N 4
#define RADIAL_KIND_CIRCLE 0
#define RADIAL_KIND_RING 1
#define RADIAL_KIND_BURST 2

#define RADIAL_KIND_MASK 0x0fu
#define RADIAL_LEN14_MASK 0x3fffu
#define RADIAL_LEN12_MASK 0xfffu
#define RADIAL_LEN_SCALE 8.0f
#define RADIAL_POWER_SCALE 16.0f

struct color {
	unsigned char channel[4];
};

struct radial_payload {
	uint32_t color;
	uint32_t packed0;
	uint32_t packed1;
};

struct radial_inst {
	float pos01[4];
	float pos23[4];
	struct color color;
	uint32_t packed0;
	uint32_t packed1;
};

struct material_radial_shape {
	sg_pipeline pip;
	sg_buffer inst;
	struct soluna_render_bindings bind;
	int base;
	vs_params_t *uniform;
	void *tmp_ptr;
	size_t tmp_size;
};

struct radial_stream_context {
	float extent;
	struct radial_payload payload;
};

static int material_id = 0;

static void *
free_material_stream(void *ud, void *ptr, size_t osize, size_t nsize) {
	(void)ud;
	(void)osize;
	if (nsize == 0) {
		soluna_material_stream_free(ptr);
	}
	return NULL;
}

static inline uint32_t
fixed_len(float value, uint32_t max_value) {
	if (value < 0.0f) {
		value = 0.0f;
	}
	uint32_t fixed = (uint32_t)(value * RADIAL_LEN_SCALE + 0.5f);
	if (fixed > max_value) {
		fixed = max_value;
	}
	return fixed;
}

static inline uint32_t
fixed_power(float value) {
	if (value < 0.0625f) {
		value = 0.0625f;
	}
	uint32_t fixed = (uint32_t)(value * RADIAL_POWER_SCALE + 0.5f);
	if (fixed > 0xffu) {
		fixed = 0xffu;
	}
	return fixed;
}

static inline float
radial_extent(int kind, float radius, float thickness, float outer_softness) {
	if (kind == RADIAL_KIND_RING) {
		return radius + thickness * 0.5f + outer_softness + 1.0f;
	}
	return radius + outer_softness + 1.0f;
}

static struct color
argb_color(uint32_t color) {
	struct color c;
	if (!(color & 0xff000000)) {
		color |= 0xff000000;
	}
	c.channel[0] = (color >> 16) & 0xff;
	c.channel[1] = (color >> 8) & 0xff;
	c.channel[2] = color & 0xff;
	c.channel[3] = (color >> 24) & 0xff;
	return c;
}

static uint32_t
get_argb_color(lua_State *L, int index) {
	lua_getfield(L, index, "color");
	uint32_t color = (uint32_t)luaL_optinteger(L, -1, 0xffffffff);
	lua_pop(L, 1);
	if (!(color & 0xff000000)) {
		color |= 0xff000000;
	}
	return color;
}

static float
get_number_field(lua_State *L, int index, const char *field, float defv) {
	lua_getfield(L, index, field);
	float value = luaL_optnumber(L, -1, defv);
	lua_pop(L, 1);
	return value;
}

static float
get_optional_number_field(lua_State *L, int index, const char *field, float defv, int *has_value) {
	lua_getfield(L, index, field);
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		return defv;
	}
	*has_value = 1;
	float value = luaL_checknumber(L, -1);
	lua_pop(L, 1);
	return value;
}

static soluna_material_error
radial_shape_count(int prim_n, int *out) {
	if (prim_n % RADIAL_CORNER_N != 0) {
		return "Invalid radial shape primitive count";
	}
	*out = prim_n / RADIAL_CORNER_N;
	return NULL;
}

static void
submit_radial_shape(void *m_, struct soluna_material_stream_context ctx, int n) {
	struct material_radial_shape *m = (struct material_radial_shape *)m_;
	struct radial_inst *tmp = (struct radial_inst *)m->tmp_ptr;
	int out_n;
	soluna_material_error err = radial_shape_count(n, &out_n);
	if (err != NULL) {
		soluna_material_stream_error(ctx, err);
		return;
	}
	for (int i = 0; i < out_n; i++) {
		struct radial_inst *inst = &tmp[i];
		struct radial_payload first_payload = { 0 };
		int base = i * RADIAL_CORNER_N;
		for (int j = 0; j < RADIAL_CORNER_N; j++) {
			struct soluna_material_stream_data item;
			struct radial_payload payload;
			if (!soluna_material_stream_read(ctx, base + j, sizeof(payload), &payload, &item)) {
				return;
			}
			if (j == 0) {
				first_payload = payload;
			} else if (
				payload.color != first_payload.color
				|| payload.packed0 != first_payload.packed0
				|| payload.packed1 != first_payload.packed1
			) {
				soluna_material_stream_error(ctx, "Invalid radial shape stream");
				return;
			}
			switch (j) {
			case 0:
				inst->pos01[0] = item.x;
				inst->pos01[1] = item.y;
				break;
			case 1:
				inst->pos01[2] = item.x;
				inst->pos01[3] = item.y;
				break;
			case 2:
				inst->pos23[0] = item.x;
				inst->pos23[1] = item.y;
				break;
			default:
				inst->pos23[2] = item.x;
				inst->pos23[3] = item.y;
				break;
			}
		}
		inst->color = argb_color(first_payload.color);
		inst->packed0 = first_payload.packed0;
		inst->packed1 = first_payload.packed1;
	}
	sg_append_buffer(m->inst, &(sg_range) { tmp, out_n * sizeof(tmp[0]) });
}

static int
lmaterial_radial_shape_submit(lua_State *L) {
	struct material_radial_shape *m = (struct material_radial_shape *)luaL_checkudata(L, 1, "EXTLUA_MATERIAL_RADIAL_SHAPE");
	int inst_batch_n = (int)(m->tmp_size / sizeof(struct radial_inst));
	if (inst_batch_n < 1) {
		return luaL_error(L, "Radial shape tmp buffer is too small");
	}
	const void *stream = lua_touserdata(L, 2);
	int prim_n = luaL_checkinteger(L, 3);
	soluna_material_error err = soluna_material_submit(stream, prim_n, material_id, inst_batch_n * RADIAL_CORNER_N, m, submit_radial_shape);
	if (err != NULL) {
		return luaL_error(L, "%s", err);
	}
	return 0;
}

static int
lmaterial_radial_shape_draw(lua_State *L) {
	struct material_radial_shape *m = (struct material_radial_shape *)luaL_checkudata(L, 1, "EXTLUA_MATERIAL_RADIAL_SHAPE");
	int prim_n = luaL_checkinteger(L, 3);
	if (prim_n <= 0) {
		return 0;
	}
	int shape_n;
	soluna_material_error err = radial_shape_count(prim_n, &shape_n);
	if (err != NULL) {
		return luaL_error(L, "%s", err);
	}
	sg_apply_pipeline(m->pip);
	sg_apply_uniforms(UB_vs_params, &(sg_range) { m->uniform, sizeof(vs_params_t) });
	sg_bindings bindings = soluna_material_bindings(m->bind);
	bindings.vertex_buffer_offsets[0] += (size_t)m->base * sizeof(struct radial_inst);
	sg_apply_bindings(&bindings);
	sg_draw(0, 4, shape_n);
	m->base += shape_n;
	return 0;
}

static int
lmaterial_radial_shape_reset(lua_State *L) {
	struct material_radial_shape *m = (struct material_radial_shape *)luaL_checkudata(L, 1, "EXTLUA_MATERIAL_RADIAL_SHAPE");
	m->base = 0;
	return 0;
}

static int
lset_material_id(lua_State *L) {
	int id = luaL_checkinteger(L, 1);
	if (id <= 0) {
		return luaL_error(L, "Invalid radial shape material id %d", id);
	}
	material_id = id;
	return 0;
}

static sg_pipeline
make_pipeline(sg_pipeline_desc *desc) {
	sg_shader shd = sg_make_shader(radial_shape_shader_desc(sg_query_backend()));
	desc->shader = shd;
	desc->primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP;
	desc->label = "extlua-radial-shape-pipeline";
	desc->layout.buffers[0].step_func = SG_VERTEXSTEP_PER_INSTANCE;
	desc->colors[0].blend = (sg_blend_state) {
		.enabled = true,
		.src_factor_rgb = SG_BLENDFACTOR_SRC_ALPHA,
		.dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
		.src_factor_alpha = SG_BLENDFACTOR_ONE,
		.dst_factor_alpha = SG_BLENDFACTOR_ZERO,
	};
	return sg_make_pipeline(desc);
}

static void
init_pipeline(struct material_radial_shape *p) {
	sg_pipeline_desc desc = {
		.layout.attrs = {
			[ATTR_radial_shape_pos01].format = SG_VERTEXFORMAT_FLOAT4,
			[ATTR_radial_shape_pos23].format = SG_VERTEXFORMAT_FLOAT4,
			[ATTR_radial_shape_color].format = SG_VERTEXFORMAT_UBYTE4N,
			[ATTR_radial_shape_packed0].format = SG_VERTEXFORMAT_UINT,
			[ATTR_radial_shape_packed1].format = SG_VERTEXFORMAT_UINT,
		},
	};
	p->pip = make_pipeline(&desc);
}

static int
lnew_material_radial_shape(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	struct material_radial_shape *m = (struct material_radial_shape *)lua_newuserdatauv(L, sizeof(*m), 4);
	int material_index = lua_gettop(L);
	init_pipeline(m);
	m->base = 0;

	if (lua_getfield(L, 1, "inst_buffer") != LUA_TUSERDATA) {
		return luaL_error(L, "Invalid key .inst_buffer");
	}
	luaL_checkudata(L, -1, "SOKOL_BUFFER");
	lua_pushvalue(L, -1);
	lua_setiuservalue(L, material_index, 1);
	lua_pushlightuserdata(L, &m->inst);
	lua_call(L, 1, 0);

	if (lua_getfield(L, 1, "bindings") != LUA_TUSERDATA) {
		return luaL_error(L, "Invalid key .bindings");
	}
	m->bind = (struct soluna_render_bindings) {
		.ctx = luaL_checkudata(L, -1, "SOKOL_BINDINGS"),
	};
	lua_pushvalue(L, -1);
	lua_setiuservalue(L, material_index, 2);
	lua_pop(L, 1);

	if (lua_getfield(L, 1, "uniform") != LUA_TUSERDATA) {
		return luaL_error(L, "Invalid key .uniform");
	}
	m->uniform = (vs_params_t *)luaL_checkudata(L, -1, "SOKOL_UNIFORM");
	lua_pushvalue(L, -1);
	lua_setiuservalue(L, material_index, 3);
	lua_pop(L, 1);

	if (lua_getfield(L, 1, "tmp_buffer") != LUA_TUSERDATA) {
		return luaL_error(L, "Invalid key .tmp_buffer");
	}
	if (lua_getmetatable(L, -1)) {
		return luaL_error(L, "Not an userdata without metatable");
	}
	m->tmp_ptr = lua_touserdata(L, -1);
	m->tmp_size = lua_rawlen(L, -1);
	lua_setiuservalue(L, material_index, 4);

	if (luaL_newmetatable(L, "EXTLUA_MATERIAL_RADIAL_SHAPE")) {
		luaL_Reg l[] = {
			{ "__index", NULL },
			{ "reset", lmaterial_radial_shape_reset },
			{ "submit", lmaterial_radial_shape_submit },
			{ "draw", lmaterial_radial_shape_draw },
			{ NULL, NULL },
		};
		luaL_setfuncs(L, l, 0);
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
	lua_setmetatable(L, -2);
	return 1;
}

static void
write_radial_shape_stream(void *ud, int index, struct soluna_material_stream_item *item) {
	struct radial_stream_context *ctx = (struct radial_stream_context *)ud;
	item->x = (index & 1) ? ctx->extent : -ctx->extent;
	item->y = index < 2 ? -ctx->extent : ctx->extent;
	item->sprite = -1;
	item->payload = &ctx->payload;
}

static int
lradial_shape(int kind, lua_State *L) {
	if (material_id <= 0) {
		return luaL_error(L, "Radial shape material is not registered");
	}
	luaL_checktype(L, 1, LUA_TTABLE);
	float radius = get_number_field(L, 1, "radius", 1.0f);
	float thickness = get_number_field(L, 1, "thickness", kind == RADIAL_KIND_RING ? 1.0f : 0.0f);
	float softness = get_number_field(L, 1, "softness", 0.75f);
	if (radius <= 0.0f) {
		lua_pushliteral(L, "");
		return 1;
	}

	struct radial_stream_context ctx;
	ctx.payload.color = get_argb_color(L, 1);
	int has_inner_softness = 0;
	int has_outer_softness = 0;
	int has_inner_radius = 0;
	int has_power = 0;
	float inner_softness = get_optional_number_field(L, 1, "inner_softness", softness, &has_inner_softness);
	float outer_softness = get_optional_number_field(L, 1, "outer_softness", softness, &has_outer_softness);
	float inner_radius = get_optional_number_field(L, 1, "inner_radius", 0.0f, &has_inner_radius);
	float power = get_optional_number_field(L, 1, "power", 2.0f, &has_power);

	if (kind == RADIAL_KIND_BURST) {
		if (has_inner_radius) {
			thickness = inner_radius;
		} else if (thickness <= 0.0f) {
			thickness = radius * 0.18f;
		}
		if (!has_outer_softness) {
			outer_softness = 1.0f;
		}
		if (!has_power) {
			power = 2.0f;
		}
	} else if (kind == RADIAL_KIND_RING && !has_inner_softness) {
		inner_softness = softness;
	}

	ctx.extent = radial_extent(kind, radius, thickness, outer_softness);
	uint32_t radius_fixed = fixed_len(radius, RADIAL_LEN14_MASK);
	uint32_t thickness_fixed = fixed_len(thickness, RADIAL_LEN14_MASK);
	uint32_t inner_softness_fixed = fixed_len(inner_softness, RADIAL_LEN12_MASK);
	uint32_t outer_softness_fixed = fixed_len(outer_softness, RADIAL_LEN12_MASK);
	ctx.payload.packed0 = ((uint32_t)kind & RADIAL_KIND_MASK) | (radius_fixed << 4) | (thickness_fixed << 18);
	ctx.payload.packed1 = inner_softness_fixed | (outer_softness_fixed << 12) | (fixed_power(power) << 24);

	struct soluna_material_stream stream;
	soluna_material_error err = soluna_material_push_stream(
		material_id,
		RADIAL_CORNER_N,
		sizeof(struct radial_payload),
		write_radial_shape_stream,
		&ctx,
		&stream
	);
	if (err != NULL) {
		return luaL_error(L, "%s", err);
	}
	lua_pushexternalstring(L, stream.data, stream.size, free_material_stream, NULL);
	return 1;
}

static int
lradial_shape_circle(lua_State *L) {
	return lradial_shape(RADIAL_KIND_CIRCLE, L);
}

static int
lradial_shape_ring(lua_State *L) {
	return lradial_shape(RADIAL_KIND_RING, L);
}

static int
lradial_shape_burst(lua_State *L) {
	return lradial_shape(RADIAL_KIND_BURST, L);
}

static int
luaopen_ext_material_radial_shape(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "set_material_id", lset_material_id },
		{ "new", lnew_material_radial_shape },
		{ "circle", lradial_shape_circle },
		{ "ring", lradial_shape_ring },
		{ "burst", lradial_shape_burst },
		{ "instance_size", NULL },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	lua_pushinteger(L, sizeof(struct radial_inst));
	lua_setfield(L, -2, "instance_size");
	return 1;
}

EXTLUA_EXPORT int
extlua_init(lua_State *L) {
	luaapi_init(L);
	sokolapi_init(L);
	solunaapi_init(L);
	luaL_Reg l[] = {
		{ "ext.material.radial_shape", luaopen_ext_material_radial_shape },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	return 1;
}
