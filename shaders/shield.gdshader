shader_type spatial;
// 무적 보호막: 가장자리(fresnel)가 밝게 빛나는 반투명 구. 안쪽 캐릭터가 잘 보이도록 가운데는 거의 투명.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.3, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.97, 0.75, 1.0);
uniform float strength = 1.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	// 위로 흐르는 줄무늬로 '살아 있는' 느낌
	float bands = 0.5 + 0.5 * sin(UV.y * 40.0 - TIME * 4.0);
	vec3 c = mix(color.rgb * 0.25, edge_color.rgb, f) + color.rgb * bands * 0.08;
	ALBEDO = c * strength * (0.15 + 1.1 * f);
}
