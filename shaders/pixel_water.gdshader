// Francisco Cidade  |  https://fcidade.com  |  https://fcidade.itch.io
shader_type canvas_item;
// Pixel Water: flowing pixel art water, drawn without any textures.
// Godot 4.x, CanvasItem. Put it on a ColorRect of any size. CC0: use it, change it, sell it with your game.
// Note: the node's modulate is not applied (the shader outputs the final color).

// Size of one big pixel, in screen pixels.
uniform int pixel_size : hint_range(1, 16, 1) = 4;
// Seed: any number gives a different pattern.
uniform float seed : hint_range(0.0, 100.0, 0.1) = 3.0;
// Animation speed, in loops per second. The animation repeats exactly after 1 / speed seconds (0.125 = 8 s).
uniform float speed : hint_range(0.0, 1.0, 0.005) = 0.125;
// Size of the waves (higher = more, smaller waves).
uniform float scale : hint_range(0.5, 8.0, 0.1) = 2.0;
// Direction the water flows, in radians (0 = right, 1.57 = down).
uniform float flow_angle : hint_range(-3.14, 3.14, 0.01) = 0.5;
// How much the waves bend the pattern (0 = straight ripples).
uniform float turbulence : hint_range(0.0, 2.0, 0.01) = 0.8;
// Brightness balance: negative = darker, deeper water; positive = lighter, shallower water.
uniform float depth : hint_range(-0.5, 0.5, 0.01) = 0.0;
// Amount of white crests on top of the waves (0 = none).
uniform float crest_amount : hint_range(0.0, 1.0, 0.01) = 0.5;
// How much land there is (0 = open water, no land at all).
uniform float land_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
// Width of the foam band along the coast (0 = no foam).
uniform float foam_width : hint_range(0.0, 1.0, 0.01) = 0.5;
// Width of the lighter shallow water along the coast.
uniform float shallow_width : hint_range(0.0, 1.0, 0.01) = 0.5;
// Height of the long swells that roll across the open water (0 = none).
uniform float swell : hint_range(0.0, 1.0, 0.01) = 0.5;
// Cloud shadows drifting over everything (0 = none).
uniform float cloud_shadow : hint_range(0.0, 1.0, 0.01) = 0.5;
// Amount of tiny glints that flash on the water (0 = none).
uniform float sparkle_amount : hint_range(0.0, 1.0, 0.01) = 0.5;
// Ready-made color set. "Custom (ocean)" uses the nine color uniforms below (the default is the blue ocean); the others replace all nine colors.
uniform int preset : hint_enum("Custom (ocean)", "Tropical", "Lagoon", "Swamp", "Night") = 0;
// Water colors, from darkest to lightest.
uniform vec4 color_deep : source_color = vec4(0.067, 0.188, 0.384, 1.0);
uniform vec4 color_mid : source_color = vec4(0.114, 0.318, 0.553, 1.0);
uniform vec4 color_light : source_color = vec4(0.208, 0.482, 0.718, 1.0);
uniform vec4 color_crest : source_color = vec4(0.714, 0.89, 0.953, 1.0);

uniform vec4 color_shallow : source_color = vec4(0.412, 0.682, 0.8, 1.0);
uniform vec4 color_foam : source_color = vec4(0.941, 0.973, 0.984, 1.0);
// Land colors: sand on the beach, then two greens.
uniform vec4 color_sand : source_color = vec4(0.867, 0.784, 0.545, 1.0);
uniform vec4 color_grass : source_color = vec4(0.384, 0.612, 0.286, 1.0);
uniform vec4 color_forest : source_color = vec4(0.259, 0.439, 0.239, 1.0);

// Nine colors per preset, in the order: deep, mid, light, shallow, crest, foam, sand, grass, forest.
const vec3 PRESETS[36] = vec3[36](
	vec3(0.039, 0.290, 0.541), vec3(0.059, 0.482, 0.710), vec3(0.098, 0.690, 0.788), vec3(0.435, 0.890, 0.839), vec3(0.824, 0.984, 0.949), vec3(1.000, 1.000, 1.000), vec3(0.949, 0.886, 0.659), vec3(0.498, 0.761, 0.290), vec3(0.247, 0.569, 0.251),
	vec3(0.059, 0.239, 0.251), vec3(0.102, 0.400, 0.420), vec3(0.200, 0.600, 0.580), vec3(0.450, 0.800, 0.700), vec3(0.800, 0.970, 0.900), vec3(0.941, 0.973, 0.984), vec3(0.930, 0.850, 0.600), vec3(0.384, 0.612, 0.286), vec3(0.259, 0.439, 0.239),
	vec3(0.110, 0.165, 0.110), vec3(0.184, 0.290, 0.165), vec3(0.310, 0.420, 0.210), vec3(0.490, 0.540, 0.270), vec3(0.660, 0.690, 0.420), vec3(0.790, 0.770, 0.540), vec3(0.420, 0.350, 0.230), vec3(0.290, 0.420, 0.165), vec3(0.180, 0.290, 0.130),
	vec3(0.020, 0.030, 0.100), vec3(0.043, 0.078, 0.200), vec3(0.090, 0.150, 0.310), vec3(0.160, 0.250, 0.470), vec3(0.500, 0.620, 0.880), vec3(0.780, 0.840, 1.000), vec3(0.230, 0.230, 0.360), vec3(0.120, 0.230, 0.290), vec3(0.080, 0.150, 0.230)
);

vec3 pal(int k, vec4 custom) {
	return preset == 0 ? custom.rgb : PRESETS[(preset - 1) * 9 + k];
}

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// 4x4 Bayer matrix as a 0..1 threshold for a pixel cell.
float bayer4(vec2 c) {
	int x = int(mod(c.x, 4.0));
	int y = int(mod(c.y, 4.0));
	int idx = y * 4 + x;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030) + seed * 0.013);
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Noise that drifts along `dir` and repeats exactly: two copies of the pattern, one a
// full cycle behind the other, fade into each other as the phase goes from 0 to 1.
float flow_noise(vec2 p, vec2 dir, float phase) {
	float f = fract(phase);
	float a = noise(p - dir * f);
	float b = noise(p - dir * (f - 1.0));
	return mix(a, b, f);
}

void fragment() {
	vec2 pos = (floor(local / float(pixel_size)) + 0.5) * float(pixel_size) / 128.0 * scale;
	float phase = TIME * speed;
	vec2 dir = vec2(cos(flow_angle), sin(flow_angle));
	vec3 c_deep = pal(0, color_deep);
	vec3 c_mid = pal(1, color_mid);
	vec3 c_light = pal(2, color_light);
	vec3 c_shallow = pal(3, color_shallow);
	vec3 c_crest = pal(4, color_crest);
	vec3 c_foam = pal(5, color_foam);
	vec3 c_sand = pal(6, color_sand);
	vec3 c_grass = pal(7, color_grass);
	vec3 c_forest = pal(8, color_forest);

	// First layer bends the second one, so the waves look pushed around.
	// First layer bends the second one, so the waves look pushed around.
	float warp = flow_noise(pos * 0.5 + 5.0, dir * 1.0, phase) - 0.5;
	vec2 bent = pos + vec2(warp, -warp) * turbulence * 1.5;
	// Big soft shapes pick the shade of the water.
	float h = flow_noise(bent * 0.8, dir * 1.0, phase) * 0.75 + flow_noise(bent * 1.7 + 9.0, dir * 2.0, phase) * 0.25;
	// Long swells: wide bands of lighter and darker water rolling along the flow direction.
	h += swell * 0.09 * sin(dot(pos, dir) * 4.0 - phase * 6.2831853 + warp * 4.0);
	h += depth;

	vec3 col = c_deep;
	col = h > 0.42 ? c_mid : col;
	col = h > 0.54 ? c_light : col;

	// Land: a still noise. Where it is above the level there is ground; how far below it
	// is tells how close to the coast a water pixel is.
	float level = land_amount < 0.01 ? 9.0 : mix(0.8, 0.4, land_amount);
	float l = noise(pos * 0.45 + 40.0) * 0.7 + noise(pos * 1.1 + 70.0) * 0.3;
	float d = level - l;

	if (d > 0.0) {
		// Depth: how far from the coast, in steps. The step edges are dithered with a 4x4
		// Bayer pattern, the classic pixel art way to blend two flat colors.
		vec2 cell = floor(local / float(pixel_size));
		float bayer = bayer4(cell);
		float dd = d * 2.2 / max(shallow_width, 0.05) + (bayer - 0.5) * 0.12;
		vec3 shore_col = dd < 0.12 ? c_shallow : (dd < 0.30 ? c_light : (dd < 0.55 ? c_mid : c_deep));
		// Past the shallows the shades of the open water (above) stay as they are.
		col = dd < 0.30 ? shore_col : col;

		// Lapping waves: foam lines that travel from the open water into the beach, one after
		// the other, and fade as they arrive. fract(...) keeps them looping with the phase.
		float wave_pos = fract(d * 9.0 / max(foam_width, 0.05) * 0.5 - phase * 2.0 + l * 3.0);
		float thin = clamp(d / 0.05, 0.35, 1.0);
		float lap = step(wave_pos, 0.17 * thin) * step(d, 0.09) * step(0.012, d);
		col = lap > 0.5 ? c_foam : col;
		// Solid foam right at the sand, breathing.
		float breathe = 0.5 + 0.5 * sin(phase * 6.2831853 + l * 30.0);
		float foam_w = (0.010 + 0.014 * breathe) * foam_width * 2.0;
		col = d < foam_w ? c_foam : col;

		// Crest lines in the open water only.
		float line = step(abs(flow_noise(bent * 1.6 + 21.0, dir * 3.0, phase) - 0.5), 0.035 * crest_amount * 2.0) * step(0.45, h);
		col = dd > 0.55 ? mix(col, c_crest, line) : col;
	} else {
		col = -d < 0.02 ? c_sand : (-d < 0.08 ? c_grass : c_forest);
	}

	// Cloud shadows: a big slow noise; where it is high, everything drops one shade (cool tint).
	float cs = flow_noise(pos * 0.28 + 60.0, dir * 0.5, phase);
	float shade = step(mix(0.85, 0.45, cloud_shadow), cs);
	col = mix(col, col * vec3(0.78, 0.82, 0.92), shade);

	// Sparkles: single pixels that flash for a moment and are gone. Only on water.
	if (d > 0.0 && sparkle_amount > 0.0) {
		vec2 sc = floor(local / float(pixel_size));
		float t = fract(phase * 3.0 + hash(sc) * 1.0);
		float on = step(hash(sc + 17.0), 0.012 * sparkle_amount * 4.0) * step(t, 0.12);
		col = mix(col, c_foam, on);
	}
	COLOR = vec4(col, 1.0);
}
