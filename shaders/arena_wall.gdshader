shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// 아레나 경계: 평소엔 아주 옅게, 플레이어가 다가가면 격자와 함께 선명해진다.
// 땅/물체와 맞닿는 부분은 빛나는 선으로 표시.

global uniform vec3 player_position;

uniform vec4 color : source_color = vec4(0.70, 0.90, 1.0, 1.0);
uniform float base_alpha = 0.05;
uniform float bottom_y = -1.0;
uniform float fade_height = 6.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float h01 = clamp((wpos.y - bottom_y) / fade_height, 0.0, 1.0);
    float fade = 1.0 - smoothstep(0.15, 1.0, h01);

    vec2 g = abs(fract(vec2(wpos.x + wpos.z, wpos.y) * 0.5) - 0.5);
    float line = 1.0 - smoothstep(0.0, 0.035, min(g.x, g.y));

    float near = 1.0 - smoothstep(1.5, 7.0, distance(wpos, player_position + vec3(0.0, 1.0, 0.0)));

    // 땅과 교차하는 부분 하이라이트 (깊이 비교)
    float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float diff = -view.z - (-VERTEX.z);
    float edge = 1.0 - smoothstep(0.0, 0.2, diff);

    float a = base_alpha * fade
            + line * fade * (0.04 + 0.30 * near)
            + near * 0.12 * fade
            + edge * 0.3;
    ALBEDO = color.rgb;
    ALPHA = clamp(a, 0.0, 0.85);
}
