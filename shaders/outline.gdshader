shader_type canvas_item;

uniform bool enabled = false;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_thickness : hint_range(0.0, 10.0) = 0.4;
uniform float dash_length : hint_range(1.0, 50.0) = 8.0;
uniform float dash_ratio : hint_range(0.0, 1.0) = 0.5;
uniform float speed : hint_range(-20.0, 20.0) = 4.0;
uniform float h_frames : hint_range(1.0, 64.0) = 4.0;

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    
    if (!enabled) {
        COLOR = col;
    } else {
        vec2 size = TEXTURE_PIXEL_SIZE * line_thickness;

        float alpha = col.a;
        float max_alpha = 0.0;

        for (float x = -1.0; x <= 1.0; x += 1.0) {
            for (float y = -1.0; y <= 1.0; y += 1.0) {
                if (x == 0.0 && y == 0.0) continue;
                vec2 offset = vec2(x, y) * size;
                max_alpha = max(max_alpha, texture(TEXTURE, UV + offset).a);
            }
        }

        float is_border = step(0.1, max_alpha) * (1.0 - step(0.1, alpha));
        vec2 frame_uv = vec2(fract(UV.x * h_frames), UV.y);
        vec2 center = frame_uv - vec2(0.5);

        float perimeter_dist = (atan(center.y, center.x) + 3.14159265) * 10.0;
        float pattern = fract((perimeter_dist - TIME * speed) / dash_length);
        float dash_mask = step(pattern, dash_ratio);

        if (is_border > 0.5 && dash_mask > 0.5) {
            COLOR = line_color;
        } else {
            COLOR = col;
        }
    }
}