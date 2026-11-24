shader_type spatial;
// 단색 오브젝트용 툰 머티리얼 (캐릭터, 나무, 바위, 유적)

uniform vec4 albedo : source_color = vec4(1.0);

#include "res://shaders/toon_light.gdshaderinc"

void fragment() {
    ALBEDO = albedo.rgb;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
