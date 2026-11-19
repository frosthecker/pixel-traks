// Procedural Pixel Creatures - GPU pass 2: compose the G-buffer into final pixel art.
//
// Runs on the main scene Sprite2D whose texture is the creature's SubViewport (the pass 1 G-buffer).
// It samples the four neighbours of every pixel and applies the pixel-art finishing the CPU
// rasterizer does: speck removal, single pixel hole filling, interior peeling, shade cleanup,
// interior contours, the exterior outline (with selective outline), baked eye tiles, nostrils,
// spots and the soft ground shadow. Colours come from the creature's palette ramp and RGBA LUT.
//
// Optimizations:
// - noContour/interior baked into G-buffer alpha bits 6/7 (no group_tex fetch in hot path)
// - Direct slot×level color table (16*6 = 96 colors) replaces ramp→LUT double fetch
// - Bitmasks replace mat_counts/lvl_counts arrays
// - Feature loop moved after main logic, early exit for non-matching pixels
//
// Output is premultiplied alpha, so the sprite blends correctly over the game world.

shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D gbuffer : filter_nearest, repeat_disable;
uniform sampler2D group_tex : filter_nearest, repeat_disable;
uniform sampler2D color_table : filter_nearest, repeat_disable; // 16 x 6 (slot x level), premultiplied RGBA8
uniform sampler2D lut_tex : filter_nearest, repeat_disable; // 256 x 1 for eye tiles
uniform sampler2D feature_tex : filter_nearest, repeat_disable;
uniform sampler2D eye_tex : filter_nearest, repeat_disable;
uniform sampler2D shadow_tex : filter_nearest, repeat_disable;

uniform vec2 frame_size = vec2(1.0, 1.0);
uniform int feature_count = 0;
// canvas rectangle that holds every visible feature; the feature loop is skipped outside it
uniform vec4 feature_bounds = vec4(0.0, 0.0, -1.0, -1.0);
uniform float shadow_used = 0.0;
uniform float contour_depth = 1.6;
uniform float self_contour_depth = 5.0;
uniform float cleanup = 1.0;
uniform float contours = 1.0;
uniform float sel_out = 1.0;

// must match creature_pixel.gdshader
const float GBUF_Z_BIAS = 256.0;
const float GBUF_Z_RANGE = 512.0;

const int EYE_TILE = 24;
// must match CreaturePalette.ShadowIndex: index 1 of the palette LUT is the translucent ground shadow
const int SHADOW_INDEX = 1;
const int FLAG_THIN = 1;
const int FLAG_NOOUT = 2;
const int SHADE_DEEP = 1;
const int SHADE_LIGHT = 4;
const int GFLAG_NO_CONTOUR = 2;
const int GFLAG_INTERIOR = 16;

struct Px {
	bool covered;
	float z;
	int group;
	int slot;
	int level;
	int flags;
};

Px px_empty() {
	Px p;
	p.covered = false;
	p.z = -1e30;
	p.group = -1;
	p.slot = 0;
	p.level = 0;
	p.flags = 0;
	return p;
}

Px fetch_px(ivec2 p) {
	if (p.x < 0 || p.y < 0 || p.x >= int(frame_size.x) || p.y >= int(frame_size.y)) return px_empty();
	vec4 g = texelFetch(gbuffer, p, 0);
	// See creature_pixel.gdshader for the packing layout.
	int a = int(g.a * 255.0 + 0.5);
	int packed = int(g.b * 255.0 + 0.5);
	Px r;
	r.level = a & 7;
	r.covered = r.level != 0;
	r.slot = packed & 15;
	r.group = (packed >> 4) | ((a & 128) != 0 ? 16 : 0);
	r.z = (floor(g.r * 255.0 + 0.5) * 255.0 + floor(g.g * 255.0 + 0.5)) / 65025.0 * GBUF_Z_RANGE - GBUF_Z_BIAS;
	r.flags = ((a & 8) != 0 ? FLAG_THIN : 0) | ((a & 16) != 0 ? FLAG_NOOUT : 0);
	r.flags |= (a & 32) != 0 ? 4 : 0;  // FLAG_NO_CONTOUR
	r.flags |= (a & 64) != 0 ? 8 : 0;  // FLAG_INTERIOR
	if (!r.covered) {
		r.z = -1e30;
		r.group = -1;
		r.slot = 0;
		r.level = 0;
		r.flags = 0;
	}
	return r;
}

vec4 lut_color(int idx) {
	return texelFetch(lut_tex, ivec2(clamp(idx, 0, 255), 0), 0);
}

vec4 color_table_color(int slot, int level) {
	// color_table is 16 wide (slots 0..15), 6 high (levels 0..5)
	// level 6,7 map to 5 (highlight)
	int l = min(level, 5);
	return texelFetch(color_table, ivec2(clamp(slot, 0, 15), l), 0);
}

void fragment() {
	ivec2 p = ivec2(int(floor(UV.x * frame_size.x)), int(floor(UV.y * frame_size.y)));
	p = clamp(p, ivec2(0), max(ivec2(int(frame_size.x), int(frame_size.y)) - ivec2(1), ivec2(0)));

	Px c = fetch_px(p);
	Px nb[4];
	nb[0] = fetch_px(p + ivec2(1, 0));
	nb[1] = fetch_px(p + ivec2(-1, 0));
	nb[2] = fetch_px(p + ivec2(0, 1));
	nb[3] = fetch_px(p + ivec2(0, -1));

	int covered_n = 0;
	for (int k = 0; k < 4; k++) if (nb[k].covered) covered_n++;

	// --- silhouette cleanup: isolated specks
	if (cleanup > 0.5 && c.covered && (c.flags & FLAG_THIN) == 0 && covered_n == 0) c = px_empty();

	// --- silhouette cleanup: single pixel holes (all covering neighbours in one group)
	if (cleanup > 0.5 && !c.covered && covered_n >= 3) {
		int grp = -1;
		bool same = true;
		int src = -1;
		float bestz = -1e30;
		for (int k = 0; k < 4; k++) {
			if (!nb[k].covered) continue;
			if (grp < 0) grp = nb[k].group;
			else if (nb[k].group != grp) same = false;
			if (nb[k].z > bestz) { bestz = nb[k].z; src = k; }
		}
		if (same && src >= 0) c = nb[src];
	}

	// --- interior parts (mouth insides) are peeled where they touch the background
	if (c.covered && (c.flags & 8) != 0) { // FLAG_INTERIOR
		bool peel = false;
		for (int k = 0; k < 4; k++) if (!nb[k].covered) peel = true;
		if (peel) c = px_empty();
	}

	// --- shade / material cleanup: isolated pattern speck or shade pixel inside one group
	if (cleanup > 0.5 && c.covered && (c.flags & FLAG_THIN) == 0) {
		int same_group = 0, different_mat = 0;
		int mat_mask = 0;
		int lvl_mask = 0;
		int same_lvl = 0, lvl_total = 0;
		for (int k = 0; k < 4; k++) {
			if (!nb[k].covered || nb[k].group != c.group) continue;
			same_group++;
			mat_mask |= 1 << clamp(nb[k].slot, 0, 12);
			if (nb[k].slot != c.slot) different_mat++;
			lvl_total++;
			lvl_mask |= 1 << clamp(nb[k].level, 0, 7);
			if (nb[k].level == c.level) same_lvl++;
		}
		if (same_group >= 3 && different_mat == same_group) {
			// Find most common slot from mat_mask
			int best_m = c.slot, best_c = 0;
			for (int m = 0; m < 13; m++) {
				if ((mat_mask & (1 << m)) != 0) {
					// count occurrences by re-scanning (max 4 neighbours, so cheap)
					int cnt = 0;
					for (int k = 0; k < 4; k++) if (nb[k].covered && nb[k].group == c.group && nb[k].slot == m) cnt++;
					if (cnt > best_c) { best_c = cnt; best_m = m; }
				}
			}
			if (best_c >= 3) c.slot = best_m;
		}
		if (lvl_total >= 3 && same_lvl == 0) {
			// Find most common level from lvl_mask
			int best_l = c.level, best_c = 0;
			for (int lv = 0; lv < 8; lv++) {
				if ((lvl_mask & (1 << lv)) != 0) {
					int cnt = 0;
					for (int k = 0; k < 4; k++) if (nb[k].covered && nb[k].group == c.group && nb[k].level == lv) cnt++;
					if (cnt > best_c) { best_c = cnt; best_l = lv; }
				}
			}
			if (c.level != 5 || best_c >= 4) c.level = best_l;
		}
	}

	vec4 out_color = vec4(0.0);
	bool has = false;
	if (c.covered) {
		out_color = color_table_color(c.slot, c.level);
		has = true;
	}

	// --- interior contours: a pixel directly behind a nearer part becomes a line
	bool is_contour = false;
	if (contours > 0.5 && c.covered) {
		int front_k = -1;
		float front_z = -1e30;
		// blend_self from group_tex, fetched lazily: only self contours need it
		float blend_self = -1.0;
		for (int k = 0; k < 4; k++) {
			if (!nb[k].covered) continue;
			// noContour baked in neighbour flags bit 2 (4)
			if ((nb[k].flags & 4) != 0) continue; // FLAG_NO_CONTOUR
			float gap = nb[k].z - c.z;
			bool edge;
			if (nb[k].group != c.group) {
				edge = gap > contour_depth;
			} else {
				if (blend_self < 0.0) blend_self = texelFetch(group_tex, ivec2(0, max(c.group, 0)), 0).z;
				edge = gap > self_contour_depth + blend_self;
			}
			if (!edge) continue;
			if (nb[k].z > front_z) { front_z = nb[k].z; front_k = k; }
		}
		if (front_k >= 0) {
			float depth_gap = front_z - c.z;
			out_color = (depth_gap > 6.0 || c.level <= SHADE_DEEP)
				? color_table_color(nb[front_k].slot, 0)
				: color_table_color(c.slot, SHADE_DEEP);
			has = true;
			is_contour = true;
		}
	}

	// --- exterior outline (4-neighbourhood -> clean diagonals)
	if (!c.covered) {
		int best_k = -1;
		float best_z = -1e30;
		int lit = 0;
		for (int k = 0; k < 4; k++) {
			if (!nb[k].covered || (nb[k].flags & FLAG_NOOUT) != 0) continue;
			if (nb[k].z > best_z) { best_z = nb[k].z; best_k = k; }
			if (nb[k].level >= SHADE_LIGHT) lit++;
		}
		if (best_k >= 0) {
			bool lit_side = false;
			if (sel_out > 0.5 && lit > 0) {
				bool up = nb[2].covered && (p.y == 0 || !nb[3].covered);
				bool left = nb[0].covered && (p.x == 0 || !nb[1].covered);
				lit_side = up || left;
			}
			out_color = color_table_color(nb[best_k].slot, lit_side ? SHADE_DEEP : 0);
			has = true;
		}
	}

	// --- features: eyes (baked tiles), nostrils, spots
	// The loop costs three texture reads per feature and almost every pixel is far away from the
	// eyes, so it is skipped outside the rectangle that holds them.
	bool in_feature_box = feature_count > 0
		&& float(p.x) >= feature_bounds.x && float(p.x) <= feature_bounds.z
		&& float(p.y) >= feature_bounds.y && float(p.y) <= feature_bounds.w;
	for (int fi = 0; in_feature_box && fi < feature_count; fi++) {
		vec4 f0 = texelFetch(feature_tex, ivec2(0, fi), 0);
		vec4 f1 = texelFetch(feature_tex, ivec2(1, fi), 0);
		if (f1.w < 0.5) continue;
		vec4 f2 = texelFetch(feature_tex, ivec2(2, fi), 0);
		int kind = int(f1.z + 0.5);
		if (kind == 0) {
			if (!c.covered) continue;
			ivec2 o = ivec2(int(f0.x + 0.5), int(f0.y + 0.5));
			ivec2 lp = p - o;
			if (lp.x < 0 || lp.y < 0 || lp.x >= EYE_TILE || lp.y >= EYE_TILE) continue;
			int row = int(f2.x + 0.5);
			float e = texelFetch(eye_tex, ivec2(lp.x, row * EYE_TILE + lp.y), 0).r;
			int idx = int(e * 255.0 + 0.5);
			if (idx != 0) {
				out_color = lut_color(idx);
				has = true;
				is_contour = true;
			}
		} else {
			ivec2 anchor = ivec2(int(f0.z + 0.5), int(f0.w + 0.5));
			if (p != anchor || !c.covered) continue;
			if (kind == 1) {
				if (f2.z > 0.5 && !is_contour) {
					out_color = color_table_color(0, SHADE_DEEP);
					has = true;
				}
			} else if (kind == 2) {
				out_color = color_table_color(int(f2.y + 0.5), 5);
				has = true;
			}
		}
	}

	// --- soft ground shadow (never over the creature)
	// Uses the palette's own translucent shadow colour (LUT index 1), exactly like the CPU renderer:
	// a material shade would tint it with the body colour and pale creatures got a pale shadow.
	if (!has && shadow_used > 0.5) {
		float s = texelFetch(shadow_tex, p, 0).r;
		if (s > 0.5) {
			out_color = lut_color(SHADOW_INDEX);
			has = true;
		}
	}

	COLOR = has ? vec4(out_color.rgb * out_color.a, out_color.a) : vec4(0.0);
}