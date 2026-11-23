shader_type canvas_item;

// Cheap water shader for the procedural map. The previous version sampled
// several octaves of value noise every fragment, which is expensive on mobile
// GPUs. Two quantized sine bands give the same layered, pixel-art look for a
// fraction of the cost.
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

// Triangle wave with the same period as sin() but no transcendental math.
float triangle_wave(float radians_value) {
	return abs(fract(radians_value * 0.15915494) * 2.0 - 1.0);
}

void vertex() {
	// TileMap supplies VERTEX in each tile's local space. Transform it to
	// world space so the wave pattern does not restart at tile borders.
	local = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Snap to the pixel grid first, then evaluate the waves. This preserves the
	// chunky pixel-art bands while keeping the math per fragment tiny.
	vec2 pos = (floor(local / pixel_size) + 0.5) * pixel_size;
	float phase = TIME * speed * 6.2831853 + seed * 0.37;
	vec2 dir = vec2(cos(flow_angle), sin(flow_angle));

	float band = dot(pos, dir) * 0.045 * scale;
	float h = 0.5 + 0.5 * sin(band + phase);

	float cross_band = dot(pos, vec2(-dir.y, dir.x)) * 0.032 * scale;
	h += triangle_wave(cross_band - phase * 0.7) * 0.35 * (0.5 + turbulence * 0.5);
	h += swell * 0.12 * triangle_wave(band * 0.35 + phase * 0.4);
	h = clamp(h / 1.55 + depth, 0.0, 1.0);

	vec3 col = h > 0.42 ? color_mid.rgb : color_deep.rgb;
	col = h > 0.58 ? color_light.rgb : col;
	float crest = step(0.78, h) * crest_amount;
	col = mix(col, color_crest.rgb, crest);
	COLOR = vec4(col, 1.0);
}
