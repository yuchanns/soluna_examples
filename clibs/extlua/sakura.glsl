@vs vs
layout(binding=0) uniform vs_params {
	vec2 framesize;
	vec2 texsize;
};

in vec4 param;
in uint mode;

out vec2 uv;
flat out vec4 prm;
flat out uint kind;

void main() {
	vec2 c = vec2(gl_VertexIndex & 1, gl_VertexIndex >> 1);
	uv = c * 2.0 / abs(framesize);
	gl_Position = vec4(uv * framesize - sign(framesize), 0.0, 1.0);
	prm = param;
	kind = mode;
}
@end

@fs fs
layout(binding=0) uniform texture2D t0;
layout(binding=1) uniform texture2D t1;
layout(binding=2) uniform texture2D t2;
layout(binding=3) uniform texture2D t3;
layout(binding=0) uniform sampler smp;

in vec2 uv;
flat in vec4 prm;
flat in uint kind;
out vec4 frag_color;

const vec2 RES = vec2(320.0, 200.0);
const vec2 ORIGIN = vec2(160.0, 40.0);
const vec2 BACK = vec2(-0.70711, -0.70711);
const vec2 RIGHT = vec2(0.70711, -0.70711);
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

const vec4 BLOCK = vec4(104.0, 22.0, -3.0, 16.0);
const vec2 CHANNEL = vec2(76.0, 93.0);
const vec3 OCC = vec3(-12.0, -12.0, 128.0);
const vec2 OCCZ = vec2(-32.0, 96.0);

const int MAT_FOLIAGE = 1;
const int MAT_WATER = 2;
const int MAT_FALL = 3;
const int MAT_PETAL = 4;

const vec4 LIGHT_POS[6] = vec4[6](
	vec4(53.5, 72.2, 9.0, 24.0),
	vec4(78.5, 72.2, 9.0, 24.0),
	vec4(53.5, 68.8, 8.6, 52.0),
	vec4(78.5, 68.8, 8.6, 52.0),
	vec4(31.0, 67.5, 13.6, 46.0),
	vec4(73.7, 73.7, 12.4, 22.0)
);

const vec4 LIGHT_COL[6] = vec4[6](
	vec4(vec3(1.0, 0.7, 0.4) * 2.6, 1.6),
	vec4(vec3(1.0, 0.7, 0.4) * 2.6, 1.6),
	vec4(vec3(1.0, 0.68, 0.36) * 8.0, 1.4),
	vec4(vec3(1.0, 0.68, 0.36) * 8.0, 1.4),
	vec4(vec3(1.0, 0.6, 0.28) * 4.6, 2.6),
	vec4(vec3(1.0, 0.46, 0.26) * 1.5, 1.4)
);

const vec4 LIGHT_WIN[6] = vec4[6](
	vec4(0.0),
	vec4(0.0),
	vec4(50.0, 57.0, 5.0, 13.0),
	vec4(75.0, 82.0, 5.0, 13.0),
	vec4(0.0),
	vec4(0.0)
);

const vec4 LIGHT_WIN2[6] = vec4[6](
	vec4(0.0),
	vec4(0.0),
	vec4(70.0, 2.0, 9.0, 10.0),
	vec4(70.0, 2.0, 9.0, 10.0),
	vec4(0.0),
	vec4(0.0)
);

const vec3 EMISSIVE[6] = vec3[6](
	vec3(0.0),
	vec3(176.0, 112.0, 46.0) / 255.0,
	vec3(200.0, 74.0, 34.0) / 255.0,
	vec3(255.0, 122.0, 58.0) / 255.0,
	vec3(255.0, 194.0, 122.0) / 255.0,
	vec3(255.0, 184.0, 104.0) / 255.0
);

const vec3 MOUSE_COLOR = vec3(1.0, 0.76, 0.5);
const float MOUSE_RADIUS = 44.0;
const float MOUSE_SRC = 1.6;
const float MOUSE_LIFT = 9.0;

const int BLUR = 20;
const float BLOOM = 2.4;

const int BAYER[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

struct tod_state {
	float t;
	vec2 sun, moon;
	vec3 sky_top, sky_mid, sky_bot;
	vec3 amb;
	vec3 dir_col;
	vec3 dir;
	float dir_soft;
	float lights;
	float night;
	float bloom;
	float exposure;
	vec3 gain, lift;
	float sat, vignette;
	vec3 cloud_lit, cloud_mid, cloud_dark;
};

vec4 tex0(ivec2 p) {
	return texelFetch(sampler2D(t0, smp), p, 0);
}

vec4 tex1(ivec2 p) {
	return texelFetch(sampler2D(t1, smp), p, 0);
}

vec4 tex2(ivec2 p) {
	return texelFetch(sampler2D(t2, smp), p, 0);
}

vec3 dec(vec4 c) {
	vec3 x = c.rgb * c.rgb;
	return x / (1.0 - x);
}

vec4 enc(vec3 c) {
	return vec4(sqrt(c / (1.0 + c)), 1.0);
}

float dither(ivec2 p) {
	return (float(BAYER[(p.y & 3) * 4 + (p.x & 3)]) / 16.0 - 0.5) / 255.0;
}

float height(vec4 g) {
	return (floor(g.r * 255.0 + 0.5) - 128.0) * 0.5;
}

int material(vec4 g) {
	return int(g.g * 255.0 + 0.5);
}

vec3 to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 to_srgb(vec3 c) {
	return pow(c, vec3(1.0 / 2.2));
}

vec3 key3(vec3 a, vec3 b, vec3 c, float t) {
	return t < 0.5 ? mix(a, b, smoothstep(0.0, 0.5, t)) : mix(b, c, smoothstep(0.5, 1.0, t));
}

float key1(float a, float b, float c, float t) {
	return t < 0.5 ? mix(a, b, smoothstep(0.0, 0.5, t)) : mix(b, c, smoothstep(0.5, 1.0, t));
}

vec2 orbit(float s) {
	float a = s * 1.5708;
	return vec2(160.0 + 135.0 * sin(a) + 50.0 * cos(a), 165.0 - 143.0 * cos(a));
}

vec3 toward(vec2 p) {
	float r = (p.x - 160.0) / 145.0;
	float z = (165.0 - p.y) / 165.0;
	return normalize(vec3((sqrt(1.0 - r * r) * BACK + r * RIGHT) * sqrt(1.0 - z * z), max(z, 0.03)));
}

tod_state tod(float day) {
	tod_state o;
	float t = 1.0 - abs(1.0 - 2.0 * day);
	o.t = t;
	o.sun = orbit((fract(day + 0.5) - 0.5) / 0.3);
	o.moon = orbit(clamp((day - 0.5) / 0.15, -2.0, 2.0));
	o.sky_top = key3(vec3(0.32, 0.58, 0.88), vec3(0.22, 0.20, 0.45), vec3(0.015, 0.025, 0.08), t);
	o.sky_mid = key3(vec3(0.53, 0.76, 0.94), vec3(0.78, 0.42, 0.50), vec3(0.04, 0.06, 0.16), t);
	o.sky_bot = key3(vec3(0.80, 0.91, 0.97), vec3(1.00, 0.70, 0.44), vec3(0.09, 0.11, 0.24), t);
	o.amb = key3(vec3(0.60, 0.67, 0.80) * 0.50, vec3(0.50, 0.40, 0.68) * 0.24, vec3(0.18, 0.25, 0.55) * 0.22, t);
	float su = smoothstep(0.0, 0.5, t);
	vec3 sun_col = mix(vec3(1.00, 0.95, 0.86) * 1.45, vec3(1.00, 0.58, 0.32) * 3.0, su);
	if (t < 0.65) {
		o.dir = toward(o.sun);
		o.dir_col = sun_col * (1.0 - smoothstep(0.54, 0.64, t));
		o.dir_soft = mix(0.03, 0.022, su);
	} else {
		o.dir = toward(o.moon);
		o.dir_col = vec3(0.50, 0.62, 1.00) * 0.30 * smoothstep(0.66, 0.86, t);
		o.dir_soft = 0.035;
	}
	o.lights = smoothstep(0.32, 0.78, t);
	o.night = smoothstep(0.55, 0.95, t);
	o.bloom = key1(0.10, 0.40, 0.95, t);
	o.exposure = key1(1.00, 1.05, 1.25, t);
	o.gain = key3(vec3(1.02, 1.00, 0.97), vec3(1.07, 0.96, 0.90), vec3(0.94, 0.98, 1.08), t);
	o.lift = key3(vec3(0.0), vec3(0.025, 0.0, 0.04), vec3(0.008, 0.014, 0.035), t);
	o.sat = key1(1.06, 1.10, 0.96, t);
	o.vignette = key1(0.10, 0.20, 0.30, t);
	o.cloud_lit = key3(vec3(1.00, 1.00, 1.00), vec3(1.00, 0.78, 0.60), vec3(0.42, 0.48, 0.66), t);
	o.cloud_mid = key3(vec3(0.86, 0.91, 0.97), vec3(0.86, 0.55, 0.60), vec3(0.16, 0.19, 0.33), t);
	o.cloud_dark = key3(vec3(0.69, 0.78, 0.89), vec3(0.55, 0.36, 0.52), vec3(0.09, 0.11, 0.21), t);
	return o;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.57 + vnoise(p * 2.03 + 7.1) * 0.29 + vnoise(p * 4.1 + 3.3) * 0.14;
}

vec3 world_pos(vec2 scr, float z) {
	vec2 r = scr - ORIGIN;
	return vec3(r.y + z + r.x * 0.5, r.y + z - r.x * 0.5, z);
}

vec4 star(vec2 p, float cell, float chance, vec2 level, float spread) {
	vec2 id = floor(p / cell);
	vec2 at = id * cell + 1.0 + floor(vec2(hash12(id + 0.3), hash12(id + 0.7)) * (cell - 2.0));
	vec2 d = abs(floor(p) - at);
	float w = step(hash12(id + 0.5), chance) * (d.x + d.y < 0.5 ? 1.0 : (d.x + d.y < 1.5 ? spread : 0.0));
	float v = hash12(id + 0.9);
	vec3 col = v < 0.33 ? vec3(200.0, 200.0, 255.0) : (v < 0.66 ? vec3(180.0, 220.0, 255.0) : vec3(220.0));
	return vec4(col / 255.0, w * mix(level.x, level.y, hash12(id + 0.1)));
}

vec3 sky_color(vec2 scr, tod_state td) {
	float time = prm.y;
	float y = scr.y / RES.y;
	vec3 c = y < 0.5 ? mix(td.sky_top, td.sky_mid, smoothstep(0.0, 0.5, y)) : mix(td.sky_mid, td.sky_bot, smoothstep(0.5, 1.0, y));
	vec2 ps = floor(scr);
	float a = td.night * (1.0 - y) * (1.0 - smoothstep(0.55, 0.8, y));
	vec4 far = star(ps + vec2((prm.x - 0.5) * 40.0, 0.0), 7.0, 0.2, vec2(0.35, 0.6), 0.0);
	vec4 near = star(ps + vec2((prm.x - 0.5) * 100.0, 0.0), 19.0, 0.3, vec2(0.7, 1.0), 0.45);
	c = mix(mix(c, far.rgb, far.a * a), near.rgb, near.a * a);
	float su = smoothstep(0.0, 0.5, td.t);
	float sd = length(ps + 0.5 - td.sun);
	float sun_vis = smoothstep(168.0, 160.0, td.sun.y);
	c = mix(c, mix(vec3(1.0, 0.97, 0.88), vec3(1.0, 0.86, 0.55), su), sun_vis * (1.0 - smoothstep(8.0, 8.5, sd)));
	c += mix(vec3(1.0, 0.9, 0.75), vec3(1.0, 0.55, 0.3), su) * sun_vis * 0.35 * exp(-sd * 0.06);
	float md = length(ps + 0.5 - td.moon);
	float moon_vis = smoothstep(168.0, 160.0, td.moon.y);
	if (md < 7.5) {
		float crater = step(0.72, vnoise(ps * 0.55 + 3.0));
		vec3 mc = mix(vec3(0.93, 0.94, 0.86), vec3(0.74, 0.77, 0.80), crater);
		if (length(ps + 0.5 - td.moon - vec2(2.5, -2.0)) < 7.0 && md > 5.5) {
			mc *= 0.92;
		}
		c = mix(c, mc, moon_vis);
	}
	c += vec3(0.35, 0.45, 0.70) * moon_vis * 0.25 * exp(-md * 0.09);
	float drift = time * 1.5;
	float top = 158.0 + 9.0 * (fbm2(vec2((ps.x + drift) * 0.022, 1.7)) - 0.5) * 2.0 + 4.0 * sin((ps.x + drift) * 0.09);
	float d = ps.y - floor(top);
	if (d >= 0.0) {
		float band = fbm2(vec2((ps.x + drift * 0.6) * 0.05, ps.y * 0.11));
		vec3 cc = d < 1.0 ? td.cloud_lit : (d < 4.0 + band * 6.0 ? td.cloud_mid : td.cloud_dark);
		if (d > 9.0 && band > 0.55) {
			cc = td.cloud_mid;
		}
		c = cc;
	}
	float pu = fbm2(vec2((ps.x - drift * 0.4) * 0.025, ps.y * 0.1));
	float pu_mask = smoothstep(0.04, 0.12, y) * (1.0 - smoothstep(0.2, 0.34, y));
	if (pu * pu_mask > 0.6) {
		float rim = fbm2(vec2((ps.x - drift * 0.4) * 0.025, (ps.y + 1.5) * 0.1)) * pu_mask;
		c = rim > 0.6 ? td.cloud_mid : td.cloud_lit;
	}
	return to_linear(c);
}

float terrain_occ(vec3 s) {
	if (s.x < 0.0 || s.y < 0.0 || s.x > BLOCK.x || s.y > BLOCK.x || s.z < -BLOCK.y) {
		return 0.0;
	}
	float top = (s.x > BLOCK.w && s.y > CHANNEL.x && s.y < CHANNEL.y) ? BLOCK.z : 0.0;
	return s.z < top ? 1.0 : 0.0;
}

vec4 occ_level(vec2 p, float l) {
	float size = OCC.z * exp2(-l);
	vec2 q = clamp(p * size, 0.5, size - 0.5) + vec2(2.0 * (OCC.z - size), 0.0);
	return textureLod(sampler2D(t3, smp), q / vec2(2.0 * OCC.z, OCC.z), 0.0);
}

vec4 occ_map(vec2 p, float lod) {
	lod = min(lod, 7.0);
	float l = floor(lod);
	return mix(occ_level(p, l), occ_level(p, min(l + 1.0, 7.0)), lod - l);
}

float occ_at(vec3 s, float pen) {
	vec2 p = (s.xy - OCC.xy) / OCC.z;
	float t = terrain_occ(s);
	if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0) {
		return t;
	}
	vec4 o = occ_map(p, log2(max(pen, 1.0)));
	if (o.b < 0.004) {
		return t;
	}
	float zmax = mix(OCCZ.x, OCCZ.y, o.r / o.b);
	float zmin = mix(OCCZ.x, OCCZ.y, 1.0 - o.g / o.b);
	float w = 0.4 + pen * 0.5;
	float inside = smoothstep(zmin - w, zmin + w, s.z) * (1.0 - smoothstep(zmax - w, zmax + w, s.z));
	return max(t, o.b * inside);
}

float window_cookie(vec4 r, vec4 q, vec3 p, vec3 l, float src) {
	if (p.y <= q.x + 0.05) {
		return 0.0;
	}
	float s = (q.x - l.y) / (p.y - l.y);
	vec2 c = vec2(l.x + (p.x - l.x) * s, l.z + (p.z - l.z) * s);
	float w = 0.08 + src * (1.0 - s) * 0.3;
	float open = smoothstep(r.x - w, r.x + w, c.x) * (1.0 - smoothstep(r.y - w, r.y + w, c.x))
		* smoothstep(r.z - w, r.z + w, c.y) * (1.0 - smoothstep(r.w - w, r.w + w, c.y));
	float ws = w + 0.12;
	float dg = abs(fract((c.x - r.x - q.y * 0.75) / q.y + 0.5) - 0.5) * q.y;
	open *= mix(0.22, 1.0, 1.0 - smoothstep(q.y * 0.25 - ws, q.y * 0.25 + ws, dg));
	open *= 1.0 - 0.7 * smoothstep(q.z - ws, q.z + ws, c.y) * (1.0 - smoothstep(q.w - ws, q.w + ws, c.y));
	return open;
}

float shadow_point(vec3 p, vec3 l, float src, float limit) {
	vec3 d = l - p;
	float dist = length(d);
	vec3 dir = d / dist;
	float end = min(dist - src, limit);
	if (end <= 0.6) {
		return 1.0;
	}
	float dt = max(end / 26.0, 0.6);
	float tr = 1.0;
	float t = 0.6;
	for (int i = 0; i < 26; i++) {
		if (t > end) {
			break;
		}
		float pen = 0.35 + src * t / max(dist - t, 0.5);
		tr *= 1.0 - clamp(occ_at(p + dir * t, pen) * dt * 0.85, 0.0, 1.0);
		if (tr < 0.01) {
			break;
		}
		t += dt;
	}
	return tr;
}

float shadow_dir(vec3 p, vec3 dir, float soft) {
	float tr = 1.0;
	float t = 0.6;
	for (int i = 0; i < 56; i++) {
		vec3 s = p + dir * t;
		if (s.z > 62.0) {
			break;
		}
		float dt = 0.9 + t * 0.035;
		tr *= 1.0 - clamp(occ_at(s, 0.35 + t * soft) * dt * 0.85, 0.0, 1.0);
		if (tr < 0.01) {
			break;
		}
		t += dt;
	}
	return tr;
}

float ambient_occ(vec3 p) {
	vec4 o = occ_map((p.xy - OCC.xy) / OCC.z, 2.3);
	if (o.b < 0.004) {
		return 1.0;
	}
	float zmax = mix(OCCZ.x, OCCZ.y, o.r / o.b);
	float zmin = mix(OCCZ.x, OCCZ.y, 1.0 - o.g / o.b);
	float above = smoothstep(p.z + 0.5, p.z + 7.0, zmax) * (1.0 - smoothstep(p.z + 6.0, p.z + 30.0, zmin));
	return 1.0 - 0.6 * min(o.b * 1.3, 1.0) * above;
}

vec3 lamp(vec3 p, vec3 pb, vec3 n, float wrap, vec4 pos, vec4 col, vec4 win, vec4 win2) {
	vec3 d = pos.xyz - p;
	float dist = length(d);
	if (dist > pos.w) {
		return vec3(0.0);
	}
	float nl = (dot(n, d / dist) + wrap) / (1.0 + wrap);
	if (nl <= 0.0) {
		return vec3(0.0);
	}
	float x = dist / pos.w;
	float att = (1.0 - x * x) * (1.0 - x * x) / (1.0 + 10.0 * x * x);
	float limit = 1e4;
	float src = col.w;
	if (win2.y > 0.0) {
		float ck = window_cookie(win, win2, p, pos.xyz, src);
		if (ck < 0.002) {
			return vec3(0.0);
		}
		att *= ck;
		limit = (pb.y - win2.x) / max(pb.y - pos.y, 1e-3) * dist - 1.2;
		src = 0.4;
	}
	return col.rgb * att * nl * shadow_point(pb, pos.xyz, src, limit);
}

vec3 light(ivec2 ip, vec2 scr) {
	tod_state td = tod(prm.x);
	vec2 ms = floor(prm.zw) + 0.5;
	vec4 mg = tex2(clamp(ivec2(ms), ivec2(0), ivec2(RES) - 1));
	vec3 mp = world_pos(ms, mg.a > 0.5 ? height(mg) : 0.0) + MOUSE_LIFT;
	vec3 mc = MOUSE_COLOR * mix(1.2, 5.0, smoothstep(0.1, 0.6, td.t));
	vec3 orb = mc * 0.3 * (1.0 - smoothstep(0.9, 1.6, length(scr - ms)));
	vec4 alb = tex0(ip);
	if (alb.a < 0.5) {
		return sky_color(scr, td) + orb;
	}
	vec3 n = normalize(tex1(ip).rgb * 2.0 - 1.0);
	vec4 g = tex2(ip);
	int mat = material(g);
	vec3 p = world_pos(scr, height(g));
	float wrap = (mat == MAT_FOLIAGE || mat == MAT_PETAL) ? 0.5 : 0.0;
	vec3 pb = p + n * 1.1;
	vec3 c = td.amb * (0.72 + 0.28 * n.z) * ambient_occ(p);
	float ndl = (dot(n, td.dir) + wrap) / (1.0 + wrap);
	if (ndl > 0.0 && dot(td.dir_col, vec3(1.0)) > 0.002) {
		c += td.dir_col * ndl * shadow_dir(pb, td.dir, td.dir_soft);
	}
	if (td.lights > 0.001) {
		vec3 pl = vec3(0.0);
		for (int k = 0; k < 6; k++) {
			pl += lamp(p, pb, n, wrap, LIGHT_POS[k], LIGHT_COL[k], LIGHT_WIN[k], LIGHT_WIN2[k]);
		}
		c += pl * td.lights;
	}
	c += lamp(p, pb, n, wrap, vec4(mp, MOUSE_RADIUS), vec4(mc, MOUSE_SRC), vec4(0.0), vec4(0.0));
	return to_linear(alb.rgb) * c + to_linear(EMISSIVE[int(g.b * 255.0 + 0.5)]) * td.lights * 3.4 + orb;
}

vec4 water(ivec2 ip, vec2 scr) {
	vec4 base = tex0(ip);
	vec4 g = tex1(ip);
	int mat = material(g);
	if (g.a < 0.5 || (mat != MAT_WATER && mat != MAT_FALL)) {
		return base;
	}
	tod_state td = tod(prm.x);
	float time = prm.y;
	if (mat == MAT_FALL) {
		float col = floor(scr.x);
		float k = hash12(vec2(col, 7.0));
		float v = vnoise(vec2(col * 0.8 + k * 13.0, (scr.y - time * 30.0) * 0.11));
		float v2 = vnoise(vec2(col * 0.5, (scr.y - time * 44.0) * 0.23 + 5.0));
		float streak = step(0.58, v) * 0.45 + step(0.8, v2) * 0.35;
		vec3 c = dec(base) * (0.66 + streak * 0.8);
		c += to_linear(td.sky_mid) * (0.14 + streak * 0.16) * (1.0 - td.night * 0.5);
		float z = height(g);
		if (z < -26.0 && hash12(floor(scr) + floor(time * 9.0) * 17.0) < smoothstep(-26.0, -46.0, z) * 0.7) {
			c = sky_color(scr, td);
		}
		return enc(c);
	}
	vec3 p = world_pos(scr, BLOCK.z);
	float row = scr.y;
	float w1 = sin(row * 0.85 + time * 2.4 - p.x * 0.06);
	float w2 = vnoise(vec2(p.x * 0.08 - time * 0.9, row * 0.45));
	int dx = int(floor(w1 * 0.9 + (w2 - 0.5) * 0.8 + 0.5));
	vec3 refl = sky_color(scr - vec2(0.0, 60.0), td);
	for (int s = 1; s < 140; s++) {
		ivec2 q = ip + ivec2(dx, -s);
		if (q.y < 0) {
			break;
		}
		vec4 gq = tex1(q);
		if (gq.a < 0.5) {
			refl = dec(tex0(q));
			break;
		}
		if (material(gq) == MAT_WATER) {
			continue;
		}
		float zq = height(gq);
		float zr = BLOCK.z + float(s) * 0.5;
		if (zq >= zr - 0.25 && zq - zr < 6.0) {
			refl = dec(tex0(q));
			break;
		}
	}
	vec3 tint = mix(vec3(0.62, 0.80, 0.86), vec3(0.72, 0.84, 0.96), td.night);
	float band = step(0.72, fract(row * 0.34 + w2 * 0.6 - time * 0.35));
	vec3 c = mix(dec(base), refl * tint, 0.62 - band * 0.3);
	float crest = vnoise(vec2(p.x * 0.40 - time * 2.4, p.y * 1.3 + sin(p.x * 0.25) * 0.8));
	if (crest > 0.80) {
		c = c * 1.35 + to_linear(td.sky_mid) * 0.12 * (1.0 - td.night) + refl * 0.25;
	}
	if (hash12(vec2(floor(p.x * 0.5 - time * 2.0), floor(p.y * 0.5)) + 0.5) > 0.985) {
		c = to_linear(vec3(0.97, 0.76, 0.82)) * (td.amb * 1.4 + td.dir_col * 0.6 + vec3(0.05) * td.lights);
	}
	return enc(c);
}

vec4 bright(ivec2 ip) {
	ivec2 p = ip * 2;
	vec3 c = (dec(tex0(p)) + dec(tex0(p + ivec2(1, 0))) + dec(tex0(p + ivec2(0, 1))) + dec(tex0(p + ivec2(1, 1)))) * 0.25;
	return enc(c * smoothstep(0.62, 1.22, dot(c, LUMA)));
}

float gauss(float x, float s) {
	return exp(-x * x / (2.0 * s * s)) / s;
}

vec4 blur(ivec2 ip, ivec2 d) {
	ivec2 hi = ivec2(RES * 0.5) - 1;
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int i = -BLUR; i <= BLUR; i++) {
		float x = float(i);
		float k = gauss(x, 1.7) * 0.6 + gauss(x, 3.8) * 0.8 + gauss(x, 7.8);
		c += dec(tex0(clamp(ip + d * i, ivec2(0), hi))) * k;
		w += k;
	}
	return enc(c / w);
}

vec4 grade(ivec2 ip, vec2 scr) {
	tod_state td = tod(prm.x);
	vec2 b = scr * 0.5 - 0.5;
	ivec2 i = ivec2(floor(b));
	vec2 f = b - floor(b);
	ivec2 hi = ivec2(RES * 0.5) - 1;
	vec3 b0 = mix(dec(tex1(clamp(i, ivec2(0), hi))), dec(tex1(clamp(i + ivec2(1, 0), ivec2(0), hi))), f.x);
	vec3 b1 = mix(dec(tex1(clamp(i + ivec2(0, 1), ivec2(0), hi))), dec(tex1(clamp(i + ivec2(1, 1), ivec2(0), hi))), f.x);
	vec3 c = (dec(tex0(ip)) + mix(b0, b1, f.y) * td.bloom * BLOOM) * td.exposure;
	vec3 x = max(c - 0.72, 0.0);
	c = to_srgb(min(c, 0.72) + x / (1.0 + x / 0.28));
	c = td.lift + c * (td.gain - td.lift);
	float l = dot(c, LUMA);
	c = mix(vec3(l), c, mix(td.sat, 0.55, td.night * (1.0 - smoothstep(0.12, 0.45, l))));
	vec2 q = scr / RES - 0.5;
	c *= 1.0 - td.vignette * dot(q, q) * 1.6;
	return vec4(c + dither(ip), 1.0);
}

void main() {
	ivec2 ip = ivec2(uv);
	if (kind == 0u) {
		frag_color = enc(light(ip, uv)) + dither(ip);
	} else if (kind == 1u) {
		frag_color = water(ip, uv);
	} else if (kind == 2u) {
		frag_color = bright(ip);
	} else if (kind == 3u) {
		frag_color = blur(ip, ivec2(1, 0));
	} else if (kind == 4u) {
		frag_color = blur(ip, ivec2(0, 1));
	} else {
		frag_color = grade(ip, uv);
	}
}
@end

@program sakura vs fs
