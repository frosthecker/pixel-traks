shader_type canvas_item;

// Enable this only for the currently selected tool.
uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(1.0, 3.0) = 1.0;

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);

	if (!enabled) {
		COLOR = base_color;
	} else {
		vec2 pixel = TEXTURE_PIXEL_SIZE * outline_width;
		float neighboring_alpha = 0.0;

		// Check the eight surrounding texels so the outline stays pixel-shaped.
		for (float x = -1.0; x <= 1.0; x += 1.0) {
			for (float y = -1.0; y <= 1.0; y += 1.0) {
				if (x == 0.0 && y == 0.0) {
					continue;
				}
				neighboring_alpha = max(
					neighboring_alpha,
					texture(TEXTURE, UV + vec2(x, y) * pixel).a
				);
			}
		}

		float is_outline = step(0.01, neighboring_alpha) * (1.0 - step(0.01, base_color.a));
		COLOR = mix(base_color, outline_color, is_outline * outline_color.a);
	}
}
