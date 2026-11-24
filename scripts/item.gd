class_name ItemPickup
extends Area3D
## 아레나에 떨어지는 아이템. 캐릭터가 닿으면 획득 (거부되면 그대로 남음 — 예: 헬멧 2개 꽉 참)

const Toon := preload("res://scripts/toon.gd")

enum Kind { HELMET, FEATHER, BOOTS, SHIELD5, SHIELD10 }

const NAMES := {
    Kind.HELMET: "헬멧",
    Kind.FEATHER: "깃털 (2단 점프)",
    Kind.BOOTS: "무거운 신발",
    Kind.SHIELD5: "무적 5초",
    Kind.SHIELD10: "무적 10초",
}
const COLORS := {
    Kind.HELMET: Color(1.0, 0.82, 0.2),
    Kind.FEATHER: Color(0.85, 0.95, 1.0),
    Kind.BOOTS: Color(0.55, 0.36, 0.22),
    Kind.SHIELD5: Color(0.35, 0.9, 1.0),
    Kind.SHIELD10: Color(1.0, 0.75, 0.15),
}

var game: Node
var kind := Kind.HELMET
var lifetime := 15.0
var _age := 0.0
var _pivot: Node3D


static func kind_name(k: int) -> String:
    return NAMES[k]


func setup(game_ref: Node, k: int, pos: Vector3, life: float) -> void:
    game = game_ref
    kind = k
    lifetime = life
    position = pos


func _ready() -> void:
    collision_layer = 0
    collision_mask = 2          # 캐릭터
    monitoring = true
    monitorable = false
    var col := CollisionShape3D.new()
    var sh := SphereShape3D.new()
    sh.radius = 0.9
    col.shape = sh
    col.position.y = 0.9
    add_child(col)

    var color: Color = COLORS[kind]
    _pivot = Node3D.new()
    _pivot.position.y = 1.0
    add_child(_pivot)
    _build_mesh(color)

    # 멀리서도 보이는 빛기둥
    var beam := CylinderMesh.new()
    beam.top_radius = 0.3
    beam.bottom_radius = 0.45
    beam.height = 5.0
    var bm := StandardMaterial3D.new()
    bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    bm.albedo_color = Color(color.r, color.g, color.b, 0.18)
    bm.cull_mode = BaseMaterial3D.CULL_DISABLED
    var bmi := MeshInstance3D.new()
    bmi.mesh = beam
    bmi.material_override = bm
    bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    bmi.position.y = 2.5
    add_child(bmi)

    var label := Label3D.new()
    label.text = NAMES[kind]
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 34
    label.outline_size = 10
    label.pixel_size = 0.006
    label.modulate = color.lightened(0.3)
    label.position.y = 1.9
    add_child(label)


func _build_mesh(color: Color) -> void:
    var mat := Toon.make(color, {"rim_strength": 1.0, "shade_softness": 0.05})
    var mi := MeshInstance3D.new()
    mi.material_override = mat
    match kind:
        Kind.HELMET:
            var m := SphereMesh.new()
            m.radius = 0.32
            m.height = 0.64
            m.is_hemisphere = true
            mi.mesh = m
        Kind.FEATHER:
            var m := SphereMesh.new()
            m.radius = 0.12
            m.height = 0.24
            mi.mesh = m
            mi.scale = Vector3(0.6, 3.5, 0.25)
            mi.rotation.z = 0.5
        Kind.BOOTS:
            var m := BoxMesh.new()
            m.size = Vector3(0.28, 0.3, 0.45)
            mi.mesh = m
        _:
            var m := SphereMesh.new()   # 다이아몬드(팔면체)
            m.radial_segments = 4
            m.rings = 2
            m.radius = 0.32 if kind == Kind.SHIELD5 else 0.42
            m.height = m.radius * 2.6
            mi.mesh = m
    _pivot.add_child(mi)


func _physics_process(delta: float) -> void:
    _age += delta
    _pivot.rotation.y += delta * 2.0
    _pivot.position.y = 1.0 + sin(_age * 3.0) * 0.12
    if _age > lifetime - 3.0:
        visible = fmod(_age * 6.0, 1.0) < 0.6
    if _age >= lifetime:
        queue_free()
        return
    if game and not game.is_playing():
        return
    for body in get_overlapping_bodies():
        var f := body as Fighter
        if f and not f.dead and f.apply_item(kind):
            if game.has_method(&"on_item_picked"):
                game.on_item_picked(self, f)
            queue_free()
            return
