shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// 바람에 흔들리는 풀. 뿌리 색은 지형과 같은 계산으로 맞춰 경계가 보이지 않게 함.
// 노멀을 위쪽으로 고정해 풀밭 전체가 부드러운 한 덩어리처럼 음영지게 함 (야숨 방식).

global uniform vec3 player_position;

uniform vec4 grass_a : source_color = vec4(0.33, 0.55, 0.18, 1.0);
uniform vec4 grass_b : source_color = vec4(0.50, 0.64, 0.22, 1.0);
uniform vec4 tip_color : source_color = vec4(0.78, 0.84, 0.38, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float wind_strength = 0.35;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float wind_speed = 0.04;
uniform float fade_start = 45.0;
uniform float fade_end = 68.0;

#include "res://shaders/toon_light.gdshaderinc"

varying float blade_h;
varying vec3 root_pos;

void vertex() {
    blade_h = 1.0 - UV.y;
    root_pos = MODEL_MATRIX[3].xyz;

    // 멀어질수록 풀 높이를 줄여 청크 경계 팝인을 숨김
    float dist = distance(root_pos, CAMERA_POSITION_WORLD);
    float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    VERTEX.y = mix(root_pos.y, VERTEX.y, fade);

    // 바람: 흘러가는 노이즈(돌풍) + 잔잔한 흔들림
    vec2 wd = normalize(wind_direction);
    float n = texture(noise_tex, root_pos.xz * 0.015 - wd * TIME * wind_speed).r;
    float gust = n * n * 2.0;
    float sway = sin(TIME * 2.2 + root_pos.x * 0.6 + root_pos.z * 0.4) * 0.08;
    vec2 bend = wd * (gust * wind_strength + sway);

    // 플레이어 주변 풀 눕히기
    vec3 to_p = root_pos - player_position;
    float pd = length(to_p.xz);
    float push = (1.0 - smoothstep(0.4, 1.4, pd)) * (1.0 - smoothstep(0.5, 2.5, abs(to_p.y)));
    bend += normalize(to_p.xz + vec2(0.0001)) * push * 0.9;

    float hh = blade_h * blade_h;
    VERTEX.xz += bend * hh;
    VERTEX.y -= length(bend) * hh * 0.35;
    NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
    float n1 = texture(noise_tex, root_pos.xz * 0.01).r;
    float n2 = texture(noise_tex, root_pos.xz * 0.07).r;
    vec3 g = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.3, 0.7, n1)) * mix(0.9, 1.08, n2);
    vec3 col = mix(g, tip_color.rgb, smoothstep(0.35, 1.0, blade_h) * 0.55);
    col *= mix(0.78, 1.0, blade_h);

    ALBEDO = col;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
