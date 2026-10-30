shader_type canvas_item;

// Water-only version of pixel_water. The procedural map never uses the
// coastline/land path, so those noise passes are omitted while the flowing
// layered waves are retained.
uniform float pixel_size : hint_range(0.5, 16.0, 0.5) = 0.5;
uniform float seed : hint_range(0.0, 100.0, 0.1) = 3.0;
uniform float speed : hint_range(0.0, 1.0, 0.005) = 0.125;
uniform float scale : hint_range(0.5, 8.0, 0.1) = 2.0;
uniform float flow_angle : hint_range(-3.14, 3.14, 0.01) = 0.5;
uniform float turbulence : hint_range(0.0, 2.0, 0.01) = 0.8;
uniform float depth : hint_range(-0.5, 0.5, 0.01) = 0.0;
uniform float crest_amount : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float swell : hint_range(0.0, 1.0, 0.01) = 0.5;

uniform vec4 color_deep : source_color = vec4(0.067, 0.188, 0.384, 1.0);
uniform vec4 color_mid : source_color = vec4(0.114, 0.318, 0.553, 1.0);
uniform vec4 color_light : source_color = vec4(0.208, 0.482, 0.718, 1.0);
uniform vec4 color_crest : source_color = vec4(0.714, 0.89, 0.953, 1.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
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
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two samples make a seamless moving loop without the four-layer shoreline,
// cloud, and sparkle work in the general-purpose shader.
float flow_noise(vec2 p, vec2 dir, float phase) {
	float f = fract(phase);
	return mix(noise(p - dir * f), noise(p - dir * (f - 1.0)), f);
}

void fragment() {
	vec2 pos = (floor(local / pixel_size) + 0.5) * pixel_size / 128.0 * scale;
	float phase = TIME * speed;
	vec2 dir = vec2(cos(flow_angle), sin(flow_angle));

	float warp = flow_noise(pos * 0.5 + 5.0, dir, phase) - 0.5;
	vec2 bent = pos + vec2(warp, -warp) * turbulence * 1.5;
	float h = flow_noise(bent * 0.8, dir, phase) * 0.75;
	h += flow_noise(bent * 1.7 + 9.0, dir * 2.0, phase) * 0.25;
	h += swell * 0.09 * sin(dot(pos, dir) * 4.0 - phase * 6.2831853 + warp * 4.0);
	h += depth;

	vec3 col = h > 0.42 ? color_mid.rgb : color_deep.rgb;
	col = h > 0.54 ? color_light.rgb : col;
	float crest = step(abs(flow_noise(bent * 1.6 + 21.0, dir * 3.0, phase) - 0.5),
		0.035 * crest_amount * 2.0) * step(0.45, h);
	col = mix(col, color_crest.rgb, crest);
	COLOR = vec4(col, 1.0);
}
