shader_type spatial;
// 정육면체 블록 (연쇄폭탄마): 모서리마다 진한 테두리 선을 그려 블록 하나하나가 잘 구분되게
// 상자 메시의 꼭짓점 좌표(-half ~ +half)로 모서리를 찾는다 — 두 축이 동시에 끝에 가까우면 테두리
uniform vec4 albedo : source_color = vec4(0.8, 0.5, 0.2, 1.0);
uniform vec4 edge_color : source_color = vec4(0.18, 0.1, 0.06, 1.0);
uniform float half_size = 1.0;
uniform float edge_width = 0.07;   // 테두리 두께 (블록 한 변 대비)
uniform float top_boost = 1.12;    // 윗면을 조금 밝게
varying vec3 lp;

void vertex() {
    lp = VERTEX / half_size;
}

void fragment() {
    vec3 a = abs(lp);
    float lim = 1.0 - edge_width * 2.0;
    float n = step(lim, a.x) + step(lim, a.y) + step(lim, a.z);
    vec3 c = albedo.rgb;
    if (lp.y > 0.98) {
        c *= top_boost;
    } else if (lp.y < 0.0) {
        c *= 0.9;
    }
    ALBEDO = n >= 2.0 ? edge_color.rgb : c;
    ROUGHNESS = 1.0;
    SPECULAR = 0.1;
}
