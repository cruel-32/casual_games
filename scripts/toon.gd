extends RefCounted
## 툰 머티리얼 생성 헬퍼. 사용: const Toon := preload("res://scripts/toon.gd") → Toon.make(color)

const TOON_SHADER := preload("res://shaders/toon.gdshader")


static func make(color: Color, params: Dictionary = {}) -> ShaderMaterial:
    var m := ShaderMaterial.new()
    m.shader = TOON_SHADER
    m.set_shader_parameter("albedo", color)
    for key in params:
        m.set_shader_parameter(key, params[key])
    return m
