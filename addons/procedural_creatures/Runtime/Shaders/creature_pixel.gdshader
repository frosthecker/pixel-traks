// Procedural Pixel Creatures - GPU pass 1: per-creature G-buffer.
//
// Runs on a canvas sized ColorRect inside the creature's SubViewport. Every pixel walks the short
// per-tile candidate list, evaluates the 2D signed distance fields of the nearby primitives, soft
// unions them per group, resolves the group depth against the frame, and then stylizes the winning
// surface (patterns, micro texture and scutes come from the baked atlas) into a toon shade level.
//
// The target is a plain RGBA8 buffer: the GLES3 compatibility renderer clamps fragment output to
// 0..1 (HDR 2D is unavailable on the Pi's V3D driver), so the G-buffer is packed into normalized
// bytes and decoded by creature_compose.gdshader:
//
//   R,G = 16 bit view depth (high, low byte) over [-GBUF_Z_BIAS, GBUF_Z_RANGE - GBUF_Z_BIAS)
//   B   = material slot (low nibble) | group id bits 0..3 (high nibble)
//   A   = shade level 1..5 (bits 0..2) | thin (3) | no-outline (4)
//         | group no-contour (5) | group interior (6) | group id bit 4 (7)
//
// Background pixels have level 0. All data textures are RGBA half floats; the surface atlas and
// the G-buffer are RGBA8. Everything is read with texelFetch, so no filtering shifts a texel.

shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D prim_tex : filter_nearest, repeat_disable;
uniform sampler2D group_tex : filter_nearest, repeat_disable;
uniform sampler2D tile_tex : filter_nearest, repeat_disable;
uniform sampler2D cand_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform sampler2D style_tex : filter_nearest, repeat_disable;

uniform vec2 frame_size = vec2(1.0, 1.0);
uniform vec2 frame_origin = vec2(0.0, 0.0);
uniform vec2 atlas_size = vec2(1024.0, 64.0);
uniform int tile_cols = 1;
uniform int cand_texels_per_row = 8;

// rows of the creature-to-view rotation (facet directions are baked in creature space)
uniform vec3 ctv_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 ctv_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 ctv_row2 = vec3(0.0, 0.0, 1.0);
uniform vec3 light_view = vec3(0.0, 0.0, 1.0);
uniform vec3 half_view = vec3(0.0, 0.0, 1.0);
uniform vec3 lateral_view = vec3(0.0, 0.0, 1.0);

const int TILE = 8;
// G-buffer depth encoding window: covers [-256, 256) view units with ~1/64 unit precision.
const float GBUF_Z_BIAS = 256.0;
const float GBUF_Z_RANGE = 512.0;

const int FLAG_BACK = 1;
const int FLAG_THIN = 2;
const int FLAG_FILLET = 4;
const int FLAG_NOOUT = 8;
const float PLATE_HALF_THICKNESS = 0.75;

// shade levels (match PixelCreatures.Core.Palettes.Shade)
const int SHADE_DEEP = 1;
const int SHADE_SHADOW = 2;
const int SHADE_BASE = 3;
const int SHADE_LIGHT = 4;
const int SHADE_HIGHLIGHT = 5;

struct Hit {
	float z;
	int group;
	int prim;
	int flags;
	vec3 n;
};

// one pixel of a group accumulation buffer
struct Acc {
	bool inside;
	float z;
	vec3 n;
	int dom;
	int flags;
	float field;
	float fz;
	float fw;
	vec3 fn;
	float fdomw;
	int fdom;
};

vec4 prim_row(int p, int r) { return texelFetch(prim_tex, ivec2(r, p), 0); }

Acc acc_empty() {
	Acc a;
	a.inside = false;
	a.z = 0.0;
	a.n = vec3(0.0);
	a.dom = -1;
	a.flags = 0;
	a.field = 0.0;
	a.fz = 0.0;
	a.fw = 0.0;
	a.fn = vec3(0.0);
	a.fdomw = 0.0;
	a.fdom = -1;
	return a;
}

Hit hit_empty() {
	Hit h;
	h.z = -1e30;
	h.group = -1;
	h.prim = -1;
	h.flags = 0;
	h.n = vec3(0.0, 0.0, 1.0);
	return h;
}

// Resolves one group's accumulated field/depth against the frame (mirror of the CPU resolve pass).
Hit resolve_group(int g, int gflags, float bias, Acc a, Hit cur) {
	Hit h = cur;
	float zacc;
	vec3 n;
	int dom;
	int af;
	int extra = 0;
	if (a.inside) {
		zacc = a.z;
		n = a.n;
		dom = a.dom;
		af = a.flags;
	} else {
		if (a.field < 0.5 || a.fw <= 0.0 || a.fdom < 0) return h;
		zacc = a.fz / a.fw;
		n = a.fn + vec3(0.0, 0.0, 0.35 * a.fw);
		dom = a.fdom;
		af = 0;
		extra = FLAG_FILLET;
	}
	float zt = zacc + bias;
	if (zt <= h.z) return h;
	float nl = length(n);
	n = nl < 1e-9 ? vec3(0.0, 0.0, 1.0) : n / nl;
	h.z = zt;
	h.group = g;
	h.prim = dom;
	h.n = n;
	h.flags = extra | (af & 3) | ((gflags & 4) != 0 ? FLAG_NOOUT : 0);
	return h;
}

// ------------------------------------------------------------------ primitive fields

float sd_prim(int kind, vec4 p2, vec4 p3, vec4 p4, vec4 p5, vec4 p6, vec4 p7, vec4 p8, vec4 p9, float x, float y) {
	if (kind == 0) {
		float dx = x - p2.x, dy = y - p2.y;
		float q = p3.x * dx * dx + 2.0 * p3.y * dx * dy + p3.w * dy * dy;
		if (q < 1e-12) return -p2.w;
		float rho = sqrt(q);
		float gx = p3.x * dx + p3.y * dy;
		float gy = p3.y * dx + p3.w * dy;
		float gl = length(vec2(gx, gy));
		if (gl < 1e-12) return -p2.w;
		return (rho - 1.0) * rho / gl;
	}
	if (kind == 1) {
		float px = x - p6.x, py = y - p6.y;
		if (p9.z > 0.5) {
			float d1 = sqrt(px * px + py * py) - p6.w;
			float qx = x - p7.x, qy = y - p7.y;
			float d2 = sqrt(qx * qx + qy * qy) - p7.w;
			return min(d1, d2);
		}
		float ly = px * p8.x + py * p8.y;
		float lx = abs(px * p8.y - py * p8.x);
		float k = -p9.y * lx + p9.x * ly;
		if (k < 0.0) return sqrt(lx * lx + ly * ly) - p6.w;
		if (k > p9.x * p8.z) return sqrt(lx * lx + (ly - p8.z) * (ly - p8.z)) - p7.w;
		return lx * p9.x + ly * p9.y - p6.w;
	}
	// triangle / plate
	float e0x = p7.x - p6.x, e0y = p7.y - p6.y;
	float e1x = p8.x - p7.x, e1y = p8.y - p7.y;
	float e2x = p6.x - p8.x, e2y = p6.y - p8.y;
	float v0x = x - p6.x, v0y = y - p6.y;
	float v1x = x - p7.x, v1y = y - p7.y;
	float v2x = x - p8.x, v2y = y - p8.y;
	float t0 = clamp((v0x * e0x + v0y * e0y) / max(1e-12, e0x * e0x + e0y * e0y), 0.0, 1.0);
	float t1 = clamp((v1x * e1x + v1y * e1y) / max(1e-12, e1x * e1x + e1y * e1y), 0.0, 1.0);
	float t2 = clamp((v2x * e2x + v2y * e2y) / max(1e-12, e2x * e2x + e2y * e2y), 0.0, 1.0);
	float q0x = v0x - e0x * t0, q0y = v0y - e0y * t0;
	float q1x = v1x - e1x * t1, q1y = v1y - e1y * t1;
	float q2x = v2x - e2x * t2, q2y = v2y - e2y * t2;
	float s = sign(e0x * e2y - e0y * e2x);
	if (s == 0.0) s = 1.0;
	float d0 = q0x * q0x + q0y * q0y, s0 = s * (v0x * e0y - v0y * e0x);
	float d1 = q1x * q1x + q1y * q1y, s1 = s * (v1x * e1y - v1y * e1x);
	float d2 = q2x * q2x + q2y * q2y, s2 = s * (v2x * e2y - v2y * e2x);
	float dmin = min(d0, min(d1, d2));
	float smin = min(s0, min(s1, s2));
	return -sqrt(dmin) * sign(smin == 0.0 ? -1.0 : smin) - PLATE_HALF_THICKNESS;
}

float closest_edge_depth(vec3 a, vec3 b, float x, float y, out float dist) {
	float ex = b.x - a.x, ey = b.y - a.y;
	float t = clamp(((x - a.x) * ex + (y - a.y) * ey) / max(1e-12, ex * ex + ey * ey), 0.0, 1.0);
	float cx = a.x + ex * t, cy = a.y + ey * t;
	dist = (cx - x) * (cx - x) + (cy - y) * (cy - y);
	return a.z + (b.z - a.z) * t;
}

void plate_front(vec4 p6, vec4 p7, vec4 p8, vec4 p9, float x, float y, out float z, out vec3 n) {
	vec3 p0 = p6.xyz, p1 = p7.xyz, p2 = p8.xyz;
	n = p9.xyz;
	float area = p9.w;
	if (abs(area) > 0.25) {
		float l1 = ((x - p0.x) * (p2.y - p0.y) - (y - p0.y) * (p2.x - p0.x)) / area;
		float l2 = ((p1.x - p0.x) * (y - p0.y) - (p1.y - p0.y) * (x - p0.x)) / area;
		float l0 = max(0.0, 1.0 - l1 - l2);
		l1 = max(0.0, l1);
		l2 = max(0.0, l2);
		float s = l0 + l1 + l2;
		if (s < 1e-9) s = 1.0;
		z = (l0 * p0.z + l1 * p1.z + l2 * p2.z) / s;
		return;
	}
	float d01, d12, d20;
	z = closest_edge_depth(p0, p1, x, y, d01);
	float z12 = closest_edge_depth(p1, p2, x, y, d12);
	float z20 = closest_edge_depth(p2, p0, x, y, d20);
	if (d12 < d01) { z = z12; d01 = d12; }
	if (d20 < d01) z = z20;
}

void front_prim(int kind, vec4 p2, vec4 p3, vec4 p4, vec4 p6, vec4 p7, vec4 p8, vec4 p9,
		float x, float y, out float z, out vec3 n) {
	if (kind == 0) {
		float dx = x - p2.x, dy = y - p2.y;
		float bq = p3.z * dx + p4.x * dy;
		float cq = p3.x * dx * dx + 2.0 * p3.y * dx * dy + p3.w * dy * dy - 1.0;
		float disc = max(0.0, bq * bq - p4.y * cq);
		float s = (-bq + sqrt(disc)) / p4.y;
		z = p2.z + s;
		n = vec3(p3.x * dx + p3.y * dy + p3.z * s,
		         p3.y * dx + p3.w * dy + p4.x * s,
		         p3.z * dx + p4.x * dy + p4.y * s);
		return;
	}
	if (kind == 1) {
		// exact ray / round cone intersection (Inigo Quilez)
		vec3 a = p6.xyz, b = p7.xyz;
		float ra = p6.w, rb = p7.w;
		vec3 ro = vec3(x, y, p8.w);
		vec3 rd = vec3(0.0, 0.0, -1.0);
		vec3 ba = b - a;
		vec3 oa = ro - a;
		vec3 ob = ro - b;
		float rr = ra - rb;
		float m0 = dot(ba, ba);
		float m1 = dot(ba, oa);
		float m2 = -ba.z;
		float m3 = -oa.z;
		float m5 = dot(oa, oa);
		float m6 = -ob.z;
		float m7 = dot(ob, ob);
		float d2 = m0 - rr * rr;
		if (d2 > 1e-9) {
			float k2 = d2 - m2 * m2;
			float k1 = d2 * m3 - m1 * m2 + m2 * rr * ra;
			float k0 = d2 * m5 - m1 * m1 + m1 * rr * ra * 2.0 - m0 * ra * ra;
			float h = k1 * k1 - k0 * k2;
			if (h >= 0.0 && abs(k2) > 1e-9) {
				float t = (-sqrt(h) - k1) / k2;
				float yy = m1 - ra * rr + t * m2;
				if (yy > 0.0 && yy < d2 && t >= 0.0) {
					z = p8.w - t;
					n = d2 * (oa + t * rd) - ba * yy;
					return;
				}
			}
		}
		float best = 1e30;
		n = vec3(0.0, 0.0, 1.0);
		float h1 = m3 * m3 - m5 + ra * ra;
		if (h1 > 0.0) {
			float t = -m3 - sqrt(h1);
			if (t < best) { best = t; n = (oa + t * rd) / ra; }
		}
		float h2 = m6 * m6 - m7 + rb * rb;
		if (h2 > 0.0) {
			float t = -m6 - sqrt(h2);
			if (t < best) { best = t; n = (ob + t * rd) / rb; }
		}
		if (best == 1e30) {
			float px = x - a.x, py = y - a.y;
			float t = p8.z > 1e-9 ? clamp((px * p8.x + py * p8.y) / p8.z, 0.0, 1.0) : 0.0;
			z = a.z + (b.z - a.z) * t;
			n = vec3(x - (a.x + (b.x - a.x) * t), y - (a.y + (b.y - a.y) * t), 0.0);
			return;
		}
		z = p8.w - best;
		return;
	}
	plate_front(p6, p7, p8, p9, x, y, z, n);
}

// Depth/normal of the silhouette rim nearest to a pixel outside the primitive (fillet field).
void rim_prim(int kind, vec4 p2, vec4 p3, vec4 p4, vec4 p5, vec4 p6, vec4 p7, vec4 p8, vec4 p9,
		float x, float y, out float z, out vec3 n) {
	if (kind == 0) {
		float dx = x - p2.x, dy = y - p2.y;
		z = p2.z - (p3.z * dx + p4.x * dy) / p4.y;
		n = vec3(p4.z * dx + p4.w * dy, p4.w * dx + p5.x * dy, 0.0);
		return;
	}
	if (kind == 1) {
		vec3 a = p6.xyz, b = p7.xyz;
		float px = x - a.x, py = y - a.y;
		float t = p8.z > 1e-9 ? clamp((px * p8.x + py * p8.y) / p8.z, 0.0, 1.0) : 0.0;
		z = a.z + (b.z - a.z) * t;
		n = vec3(x - (a.x + (b.x - a.x) * t), y - (a.y + (b.y - a.y) * t), 0.0);
		return;
	}
	plate_front(p6, p7, p8, p9, x, y, z, n);
}

// ------------------------------------------------------------------ surface parametrization

// Returns (u, v) inside the primitive's atlas tile. Mirrors SurfaceAt of the CPU rasterizer, minus
// the parts the baked atlas already resolved (patterns, micro texture, scutes, tips, mask...).
vec2 surface_uv(int kind, vec4 p2, vec4 p5, vec4 p6, vec4 p7, vec4 p8, vec4 p9, vec4 p10, vec4 p14,
		float x, float y, float z) {
	float len = max(1.0, p5.z);
	float u0 = p14.x, u1 = p14.y;
	float du = abs(u1 - u0) > 1e-9 ? (u1 - u0) : 1e-9;
	vec3 pt = vec3(x, y, z);
	if (kind == 0) {
		vec3 rel = pt - p2.xyz;
		vec3 q = vec3(dot(p6.xyz, rel), dot(p7.xyz, rel), dot(p8.xyz, rel));
		float tn = mix(u0, u1, clamp(q.x * 0.5 + 0.5, 0.0, 1.0));
		float theta = atan(q.z, q.y);
		return vec2((tn - u0) / du, theta / 6.28318530718 + 0.5);
	}
	if (kind == 1) {
		vec3 a = p6.xyz, b = p7.xyz;
		vec3 axis = b - a;
		float al = length(axis);
		vec3 dir = al > 1e-9 ? axis / al : vec3(1.0, 0.0, 0.0);
		vec3 rel = pt - a;
		float along = dot(rel, dir);
		float t = al > 1e-9 ? clamp(along / al, 0.0, 1.0) : 0.0;
		float tn = mix(u0, u1, t);
		vec3 perp = rel - dir * along;
		vec3 upv = p10.xyz - dir * dot(p10.xyz, dir);
		upv = length(upv) > 1e-9 ? normalize(upv) : vec3(0.0, 1.0, 0.0);
		vec3 sidev = cross(dir, upv);
		float cu = dot(perp, upv);
		float cs = dot(perp, sidev);
		return vec2((tn - u0) / du, atan(cs, cu) / 6.28318530718 + 0.5);
	}
	vec3 p0 = p6.xyz, p1 = p7.xyz, p2v = p8.xyz;
	float area = p9.w;
	float l1 = 0.0, l2 = 0.0;
	if (abs(area) > 0.25) {
		l1 = ((x - p0.x) * (p2v.y - p0.y) - (y - p0.y) * (p2v.x - p0.x)) / area;
		l2 = ((p1.x - p0.x) * (y - p0.y) - (p1.y - p0.y) * (x - p0.x)) / area;
	}
	float t = clamp(l1 + l2, 0.0, 1.0);
	return vec2(t, 0.5 + (l2 - l1) * 0.5);
}

int shade_level(float ndl, float ndh, vec4 style, float specular) {
	float w = ((ndl + style.x) / (1.0 + style.x) - 0.11) * 1.08;
	if (ndh > specular) return SHADE_HIGHLIGHT;
	if (w > style.y) return SHADE_LIGHT;
	if (w > style.z) return SHADE_BASE;
	if (w > style.w) return SHADE_SHADOW;
	return SHADE_DEEP;
}

vec3 facet_normal(int prim, vec3 n) {
	float best_dot = -2.0;
	vec3 best = n;
	for (int k = 0; k < 7; k++) {
		vec3 d = prim_row(prim, 16 + k).xyz;
		vec3 f = vec3(dot(ctv_row0, d), dot(ctv_row1, d), dot(ctv_row2, d));
		float dd = dot(f, n);
		if (dd > best_dot) { best_dot = dd; best = f; }
	}
	if (dot(best, n) < 0.55) return n;
	vec3 m = normalize(best * 0.8 + n * 0.2);
	return m.z < 0.05 ? n : m;
}

// ------------------------------------------------------------------ frame buffer

void fragment() {
	ivec2 size = ivec2(int(frame_size.x), int(frame_size.y));
	ivec2 pix = ivec2(int(floor(UV.x * frame_size.x)), int(floor(UV.y * frame_size.y)));
	pix = clamp(pix, ivec2(0), max(size - ivec2(1), ivec2(0)));
	float cpx = float(pix.x) + 0.5;              // canvas pixel coordinates (bbox / tile space)
	float cpy = float(pix.y) + 0.5;
	float vx = cpx - frame_origin.x;             // view coordinates (SDF / depth space)
	float vy = frame_origin.y - cpy;

	ivec2 tile = ivec2(clamp(pix.x / TILE, 0, max(tile_cols - 1, 0)), pix.y / TILE);
	vec4 range = texelFetch(tile_tex, tile, 0);
	int start = int(range.x + 0.5);
	int count = int(range.y + 0.5);

	Hit best = hit_empty();
	Acc acc = acc_empty();
	int cur_g = -1;
	int cur_gflags = 0;
	float cur_bias = 0.0;
	float blend = 0.0;
	float inv_two_k = 0.0;

	for (int ci = 0; ci < count; ci++) {
		int slot = start + ci;
		int texel = slot >> 1;
		ivec2 cpos = ivec2(texel % cand_texels_per_row, texel / cand_texels_per_row);
		vec4 ctex = texelFetch(cand_tex, cpos, 0);
		int prim = int((slot & 1) == 0 ? ctex.x : ctex.z);
		vec4 p0 = prim_row(prim, 0);
		int g = int(p0.y + 0.5);
		if (g != cur_g) {
			if (cur_g >= 0) best = resolve_group(cur_g, cur_gflags, cur_bias, acc, best);
			acc = acc_empty();
			cur_g = g;
			vec4 g0 = texelFetch(group_tex, ivec2(0, g), 0);
			vec4 g1 = texelFetch(group_tex, ivec2(1, g), 0);
			blend = g0.z;
			cur_bias = g0.w;
			cur_gflags = int(g1.y + 0.5);
			inv_two_k = blend > 0.0 ? 1.0 / (2.0 * blend) : 0.0;
		}

		int kind = int(p0.x + 0.5);
		int pflags = int(p0.w + 0.5);
		bool hard = (pflags & 2) != 0;
		float pad = (blend > 0.0 && !hard) ? ceil(blend) : 0.0;
		vec4 bb = prim_row(prim, 1);
		if (cpx < bb.x - pad || cpx > bb.z + 1.0 + pad || cpy < bb.y - pad || cpy > bb.w + 1.0 + pad) continue;

		vec4 p2 = prim_row(prim, 2);
		vec4 p3 = prim_row(prim, 3);
		vec4 p4 = prim_row(prim, 4);
		vec4 p5 = prim_row(prim, 5);
		vec4 p6 = prim_row(prim, 6);
		vec4 p7 = prim_row(prim, 7);
		vec4 p8 = prim_row(prim, 8);
		vec4 p9 = prim_row(prim, 9);
		float sd = sd_prim(kind, p2, p3, p4, p5, p6, p7, p8, p9, vx, vy);
		int pflag = ((kind == 2 && prim_row(prim, 10).x > 0.5) ? 1 : 0) | ((pflags & 1) != 0 ? 2 : 0);
		if (sd <= 0.0) {
			float z;
			vec3 n;
			front_prim(kind, p2, p3, p4, p6, p7, p8, p9, vx, vy, z, n);
			if (!acc.inside) {
				acc.inside = true;
				acc.z = z;
				acc.n = n;
				acc.dom = prim;
				acc.flags = pflag;
			} else {
				bool dom_hard = (int(prim_row(acc.dom, 0).w + 0.5) & 2) != 0;
				if (blend <= 0.0 || hard || dom_hard) {
					if (z > acc.z) {
						acc.z = z;
						acc.n = n;
						acc.dom = prim;
						acc.flags = pflag;
					}
				} else {
					float zacc = acc.z;
					float h = clamp(0.5 + 0.5 * (z - zacc) / blend, 0.0, 1.0);
					acc.z = zacc + (z - zacc) * h + blend * h * (1.0 - h);
					acc.n = mix(acc.n, n, h);
					if (h > 0.5) {
						acc.dom = prim;
						acc.flags = pflag;
					}
				}
			}
		}
		if (blend > 0.0 && !hard && sd < blend) {
			float gi = min(1.0, 0.5 - sd * inv_two_k);
			if (gi > 0.0) {
				acc.field += gi;
				if (sd > 0.0) {
					float zr;
					vec3 nr;
					rim_prim(kind, p2, p3, p4, p5, p6, p7, p8, p9, vx, vy, zr, nr);
					acc.fz += gi * zr;
					acc.fw += gi;
					acc.fn += gi * nr;
					if (gi > acc.fdomw) {
						acc.fdomw = gi;
						acc.fdom = prim;
					}
				}
			}
		}
	}
	if (cur_g >= 0) best = resolve_group(cur_g, cur_gflags, cur_bias, acc, best);

	COLOR = vec4(0.0);
	if (best.group >= 0) {
	int prim = best.prim;
	vec4 p0 = prim_row(prim, 0);
	int kind = int(p0.x + 0.5);
	int pflags = int(p0.w + 0.5);
	vec4 p2 = prim_row(prim, 2);
	vec4 p3 = prim_row(prim, 3);
	vec4 p4 = prim_row(prim, 4);
	vec4 p5 = prim_row(prim, 5);
	vec4 p6 = prim_row(prim, 6);
	vec4 p7 = prim_row(prim, 7);
	vec4 p8 = prim_row(prim, 8);
	vec4 p9 = prim_row(prim, 9);
	vec4 p10 = prim_row(prim, 10);
	vec4 p14 = prim_row(prim, 14);
	vec4 p15 = prim_row(prim, 15);

	bool has_surface = p5.w > 0.5;
	int slot = int(p0.z + 0.5);
	int bias_add = int(p14.w + 0.5);
	float ndl_off = 0.0;
	bool seam = false;
	if (has_surface) {
		float group_bias = texelFetch(group_tex, ivec2(0, best.group), 0).w;
		vec2 suv = surface_uv(kind, p2, p5, p6, p7, p8, p9, p10, p14, vx, vy, best.z - group_bias);
		// Float math on purpose: the V3D GLES3 driver miscompiles int() of a texel component when
		// it feeds an integer addition, which collapsed the tile origin to zero.
		float lx = clamp(floor(suv.x * p15.z), 0.0, max(p15.z - 1.0, 0.0));
		float ly = clamp(floor((suv.y - floor(suv.y)) * p15.w), 0.0, max(p15.w - 1.0, 0.0));
		int ax = int(p15.x + lx);
		int ay = int(p15.y + ly);
		vec4 at = texelFetch(atlas_tex, ivec2(ax, ay), 0);
		// Atlas R is the raw material slot index (0..12) as an 8 bit value
		slot = int(at.r * 255.0 + 0.5);
		bias_add = int(at.g * 255.0 + 0.5) - 16;
		ndl_off = at.b * 1.5 - 0.75;
		seam = at.a > 0.5;
	}

	vec4 style0 = texelFetch(style_tex, ivec2(slot, 0), 0);
	vec4 style1 = texelFetch(style_tex, ivec2(slot, 1), 0);
	vec3 n = best.n;
	if ((pflags & 4) != 0 || style1.z > 0.5) n = facet_normal(prim, n);

	int level;
	bool scutes = (pflags & 1024) != 0 && kind == 0 && has_surface;
	if ((pflags & 64) != 0 || slot == 8) {
		level = n.z > 0.55 ? SHADE_LIGHT : SHADE_BASE;
	} else {
		float ndl = dot(n, light_view) + ndl_off;
		float ndh = dot(n, half_view);
		level = shade_level(ndl, ndh, style0, style1.x);
		if (level == SHADE_HIGHLIGHT && ((best.flags & FLAG_FILLET) != 0 || scutes)) level = SHADE_LIGHT;
		if (seam) level = min(level, SHADE_SHADOW) - 1;
	}
	level += bias_add;
	vec4 g1 = texelFetch(group_tex, ivec2(1, best.group), 0);
	int gside = int(g1.x + 0.5);
	int gflags = int(g1.y + 0.5);
	if ((best.flags & FLAG_BACK) != 0) level -= 1;
	if ((pflags & 256) != 0 && (best.flags & FLAG_BACK) != 0) level += 1;
	if (gside != 0 && (gflags & 1) == 0 && lateral_view.z * float(gside) < -0.3) level -= 1;
	if ((gflags & 8) != 0 && (best.flags & FLAG_FILLET) != 0 && level > SHADE_SHADOW) level -= 1;
	level = clamp(level, SHADE_DEEP, SHADE_HIGHLIGHT);

	// G-buffer packing into a plain RGBA8 target (the compatibility renderer clamps shader
	// output to 0..1, so every channel carries a normalized 8 bit value):
	//   R,G = 16 bit view depth (high byte, low byte)
	//   B   = material slot (low nibble) | group id low nibble (high nibble)
	//   A   = shade level (bits 0..2) | THIN (3) | NOOUT (4) | NO_CONTOUR (5) | INTERIOR (6)
	//         | group id bit 4 (7)
	float zt = clamp((best.z + GBUF_Z_BIAS) / GBUF_Z_RANGE, 0.0, 1.0);
	float zq = zt * 65025.0;
	float zhi = floor(zq / 255.0);
	float zlo = zq - zhi * 255.0;
	int gid = best.group & 31;
	int packed = slot | ((gid & 15) << 4);
	int fl = level
		| ((best.flags & FLAG_THIN) != 0 ? 8 : 0)
		| ((best.flags & FLAG_NOOUT) != 0 ? 16 : 0)
		| ((gflags & 2) != 0 ? 32 : 0)
		| ((gflags & 16) != 0 ? 64 : 0)
		| ((gid & 16) != 0 ? 128 : 0);
	COLOR = vec4(zhi / 255.0, zlo / 255.0, float(packed) / 255.0, float(fl) / 255.0);
	}
}
