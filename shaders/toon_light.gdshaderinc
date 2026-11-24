// 야숨 스타일 툰 라이팅 (공용 include)
// - 빛/그림자를 부드러운 경계의 2단계로 나눔
// - 그림자 영역에 검정 대신 푸른 틴트의 빛을 일부 남김
// - 빛 받는 쪽 실루엣에 림 라이트

uniform vec4 shadow_tint : source_color = vec4(0.45, 0.52, 0.85, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float shade_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float shade_softness : hint_range(0.0, 0.5) = 0.06;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;

void light() {
    float ndl = dot(NORMAL, LIGHT);
    float lit = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl);
    float shadow = smoothstep(0.25, 0.65, ATTENUATION);
    lit = min(lit, shadow);

    vec3 sun = LIGHT_COLOR / PI;
    vec3 band = mix(shadow_tint.rgb * shadow_strength, vec3(1.0), lit);
    DIFFUSE_LIGHT += sun * band;

    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    rim *= smoothstep(-0.2, 0.4, ndl);
    DIFFUSE_LIGHT += sun * rim * rim_strength * lit;
}
