shader_type spatial;

uniform vec4 color_a : source_color = vec4(0.58, 0.68, 0.80, 1.0);
uniform vec4 color_b : source_color = vec4(0.50, 0.61, 0.75, 1.0);
uniform float tile_size = 2.0;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 cell = floor(world_pos.xz / tile_size);
    float checker = mod(cell.x + cell.y, 2.0);
    ALBEDO = mix(color_a.rgb, color_b.rgb, checker);
    ROUGHNESS = 0.85;
}
