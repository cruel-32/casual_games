shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;
// 낙석 착지 예측 표시: 위험 반경 테두리 + 충돌 시점에 가까워질수록 안쪽이 차오르고 깜빡임.

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.12, 1.0);
uniform vec4 early_color : source_color = vec4(1.0, 0.85, 0.30, 1.0);
uniform float progress = 0.0;   // 0: 막 생성 → 1: 착지

void vertex() {
    // 카메라 쪽으로 살짝 당겨 짧은 풀/지형 굴곡에 묻히지 않게
    VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * 0.35;
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.0) {
        discard;
    }
    float edge = smoothstep(0.84, 0.90, r) * (1.0 - smoothstep(0.96, 1.0, r));
    float fill = 1.0 - smoothstep(progress - 0.03, progress, r);
    float danger = smoothstep(0.65, 1.0, progress);
    float blink = mix(1.0, 0.55 + 0.45 * sin(TIME * 28.0), danger);
    ALBEDO = mix(early_color.rgb, color.rgb, smoothstep(0.15, 0.7, progress));
    ALPHA = clamp((edge * 0.95 + fill * 0.42 + 0.08) * blink, 0.0, 1.0);
}
