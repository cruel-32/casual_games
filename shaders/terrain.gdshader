shader_type spatial;
// 지형: 노이즈로 얼룩진 풀색 → 경사면은 바위 → 고지대는 눈

uniform vec4 grass_a : source_color = vec4(0.33, 0.55, 0.18, 1.0);
uniform vec4 grass_b : source_color = vec4(0.50, 0.64, 0.22, 1.0);
uniform vec4 rock_color : source_color = vec4(0.50, 0.49, 0.50, 1.0);
uniform vec4 snow_color : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform float snow_height = 30.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

#include "res://shaders/toon_light.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float n1 = texture(noise_tex, wpos.xz * 0.01).r;
    float n2 = texture(noise_tex, wpos.xz * 0.07).r;

    vec3 grass = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.3, 0.7, n1));
    grass *= mix(0.9, 1.08, n2);

    float slope = 1.0 - wnorm.y;
    float rock_w = smoothstep(0.22, 0.36, slope + (n1 - 0.5) * 0.1);
    vec3 col = mix(grass, rock_color.rgb * mix(0.88, 1.06, n1), rock_w);

    float snow_w = smoothstep(snow_height, snow_height + 5.0, wpos.y + n1 * 8.0);
    snow_w *= 1.0 - smoothstep(0.45, 0.65, slope);
    col = mix(col, snow_color.rgb, snow_w);

    ALBEDO = col;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
