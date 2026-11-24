shader_type sky;
// 그림 같은 하늘: 그라데이션 + 태양 글로우 + 흘러가는 노이즈 구름

uniform vec4 zenith_color : source_color = vec4(0.22, 0.45, 0.85, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.72, 0.83, 0.95, 1.0);
uniform vec4 ground_color : source_color = vec4(0.45, 0.52, 0.60, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.68, 0.74, 0.88, 1.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed = 0.004;
uniform float sun_disk_cos = 0.9995;

void sky() {
    vec3 d = EYEDIR;
    float up = clamp(d.y, 0.0, 1.0);
    vec3 col = mix(horizon_color.rgb, zenith_color.rgb, pow(up, 0.55));
    if (d.y < 0.0) {
        col = mix(horizon_color.rgb, ground_color.rgb, clamp(-d.y * 4.0, 0.0, 1.0));
    }

    if (LIGHT0_ENABLED) {
        vec3 lc = LIGHT0_COLOR * LIGHT0_ENERGY;
        float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
        col += lc * (pow(sd, 64.0) * 0.35 + pow(sd, 6.0) * 0.10);
        float disk = smoothstep(sun_disk_cos, sun_disk_cos + 0.0002, sd);
        col = mix(col, lc * 4.0, disk);
    }

    if (d.y > 0.0) {
        vec2 uv = d.xz / (d.y + 0.12) * 0.18;
        vec2 drift = vec2(1.0, 0.4) * TIME * cloud_speed;
        float n = texture(cloud_noise, uv + drift).r * 0.65
                + texture(cloud_noise, uv * 2.3 - drift * 1.5).r * 0.35;
        float c = smoothstep(cloud_coverage, cloud_coverage + 0.16, n);
        float dense = smoothstep(cloud_coverage + 0.05, cloud_coverage + 0.35, n);
        vec3 cc = mix(cloud_color.rgb, cloud_shade.rgb, dense * 0.7);
        col = mix(col, cc, c * smoothstep(0.0, 0.18, d.y) * 0.95);
    }

    COLOR = col;
}
