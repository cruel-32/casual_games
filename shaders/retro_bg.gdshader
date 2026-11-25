shader_type canvas_item;
// 메뉴 배경 (레트로 장난감): 크림색 바탕 + 천천히 도는 햇살 무늬 + 흩어진 도형 + 아래 빨강·크림 체크 띠
uniform vec4 base : source_color = vec4(1.0, 0.969, 0.91, 1.0);
uniform vec4 ray : source_color = vec4(1.0, 0.91, 0.74, 1.0);
uniform vec4 checker_a : source_color = vec4(0.902, 0.224, 0.275, 1.0);
uniform vec4 checker_b : source_color = vec4(1.0, 0.969, 0.91, 1.0);
uniform vec4 ink : source_color = vec4(0.114, 0.208, 0.341, 1.0);
uniform float check_px = 34.0;      // 체크 한 칸 크기 (픽셀)
uniform float band_px = 102.0;      // 체크 띠 높이 (픽셀)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// 햇살: 화면 가운데 아래쪽을 중심으로 회전
	vec2 c = vec2(res.x * 0.5, res.y * 0.62);
	vec2 d = px - c;
	float a = atan(d.y, d.x) + TIME * 0.04;
	float rays = step(0.5, fract(a / 6.2831853 * 18.0));
	vec3 col = mix(base.rgb, ray.rgb, rays * 0.55);
	// 가운데로 갈수록 밝게
	col = mix(col, base.rgb, smoothstep(res.y * 0.75, 0.0, length(d)) * 0.5);
	// 흩어진 작은 도형 (동그라미)
	vec2 cell = floor(px / 120.0);
	vec2 f = fract(px / 120.0) - 0.5;
	float h = hash(cell);
	if (h > 0.72) {
		vec2 o = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.5 - 0.25;
		float r = 0.06 + 0.05 * hash(cell + 1.3);
		float dd = length(f - o);
		vec3 dot_col = h > 0.9 ? vec3(0.271, 0.482, 0.616) : (h > 0.81 ? vec3(1.0, 0.718, 0.012) : vec3(0.165, 0.616, 0.561));
		col = mix(col, dot_col, (1.0 - smoothstep(r - 0.01, r, dd)) * 0.5);
	}
	// 아래 체크 띠 + 그 위 남색 줄
	float from_bottom = res.y - px.y;
	if (from_bottom < band_px) {
		vec2 q = floor(vec2(px.x + TIME * 18.0, from_bottom) / check_px);
		col = mod(q.x + q.y, 2.0) < 1.0 ? checker_a.rgb : checker_b.rgb;
	} else if (from_bottom < band_px + 8.0) {
		col = ink.rgb;
	}
	COLOR = vec4(col, 1.0);
}
