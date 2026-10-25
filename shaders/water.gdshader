shader_type canvas_item;

// Color Settings
uniform vec4 deep_base_color : source_color = vec4(0.05, 0.25, 0.45, 1.0);
uniform vec4 dark_cell_color : source_color = vec4(0.1, 0.35, 0.55, 1.0);
uniform vec4 light_caustic_color : source_color = vec4(0.8, 0.95, 1.0, 1.0);

// Global settings
uniform float pixel_resolution = 128.0;
uniform float wave_speed = 0.5;

// The pre-baked seamless Voronoi noise texture
uniform sampler2D voronoi_texture : repeat_enable, filter_nearest;

// Shared Shape Distortion Settings
uniform vec2 cell_stretch = vec2(0.5, 2.0);
uniform float wave_scale = 2.0;

// Separate Mask Cut-offs
uniform float cell_threshold : hint_range(0.0, 1.0) = 0.4;
uniform float caustic_threshold : hint_range(0.0, 1.0) = 0.6;

void fragment() {
    // Step 1: Base Pixelation
    vec2 pixel_uv = floor(UV * pixel_resolution) / pixel_resolution;
    
    // Stretch coordinates horizontally/vertically for the elongation look
    vec2 shared_stretched_uv = (pixel_uv * cell_stretch) * wave_scale;
    
    // Step 2: Continuous scrolling vectors to simulate organic fluid motion
    vec2 time_offset1 = vec2(sin(TIME * wave_speed), cos(TIME * wave_speed)) * 0.05;
    vec2 time_offset2 = vec2(cos(TIME * wave_speed), sin(TIME * wave_speed)) * 0.05 + vec2(0.1, -0.1);
    
    // --- LAYER 1: Dark Elongated Cells (Cheap single texture lookup) ---
    float cell_pattern = texture(voronoi_texture, shared_stretched_uv + time_offset1).r;
    float cell_mask = step(cell_threshold, cell_pattern);
    vec4 current_color = mix(deep_base_color, dark_cell_color, cell_mask);
    
    // --- LAYER 2: Light Caustics (Second cheap texture lookup) ---
    float caustic_pattern = texture(voronoi_texture, shared_stretched_uv + time_offset2).r;
    float caustic_mask = step(caustic_threshold, caustic_pattern);
    
    // Composite the light caustics on top
    COLOR = mix(current_color, light_caustic_color, caustic_mask);
}
