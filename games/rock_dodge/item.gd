class_name ItemPickup
extends Area3D
## 아레나에 떨어지는 아이템. 캐릭터가 닿으면 획득 (거부되면 그대로 남음 — 예: 헬멧 2개 꽉 참)
## 차징 가속·쿨타임 감소·글러브는 경기 끝까지 유지되고 먹을수록 중첩된다 (최대 Fighter.MAX_STACKS 개)

const Toon := preload("res://scripts/world/toon.gd")

## 순서 = 네트워크로 보내는 번호 (바꾸면 PROTOCOL_VERSION 도 올릴 것)
enum Kind { HELMET, CHARGE_UP, GLOVE, SHIELD5, SHIELD10, COOL_DOWN }

const NAMES := {
    Kind.HELMET: "헬멧",
    Kind.CHARGE_UP: "차징 가속",
    Kind.GLOVE: "글러브",
    Kind.SHIELD5: "무적 5초",
    Kind.SHIELD10: "무적 10초",
    Kind.COOL_DOWN: "쿨타임 감소",
}
const COLORS := {
    Kind.HELMET: Color(1.0, 0.82, 0.2),
    Kind.CHARGE_UP: Color(1.0, 0.45, 0.15),
    Kind.GLOVE: Color(0.95, 0.22, 0.2),
    Kind.SHIELD5: Color(0.35, 0.9, 1.0),
    Kind.SHIELD10: Color(1.0, 0.75, 0.15),
    Kind.COOL_DOWN: Color(0.3, 0.9, 0.45),
}

var game: Node
var kind := Kind.HELMET
var lifetime := 15.0
var net_id := 0                 # 온라인: 서버가 붙인 번호
var _age := 0.0
var _pivot: Node3D


static func kind_name(k: int) -> String:
    return NAMES[k]


## 캐릭터에게 효과 적용. 받을 수 없으면 false (헬멧이 이미 최대) → 아이템이 그대로 남는다
static func apply_to(f: Fighter, k: int) -> bool:
    var ok := true
    match k:
        Kind.HELMET:
            ok = f.add_helmet()
        Kind.CHARGE_UP:
            ok = f.add_charge_stack()
        Kind.COOL_DOWN:
            ok = f.add_cooldown_stack()
        Kind.GLOVE:
            ok = f.add_glove_stack()
        Kind.SHIELD5:
            f.give_invuln(5.0)       # 보호막 소리는 give_invuln 에서
        Kind.SHIELD10:
            f.give_invuln(10.0)
    if ok:
        var snd := {Kind.HELMET: "pickup_helmet", Kind.CHARGE_UP: "pickup_charge", Kind.COOL_DOWN: "pickup_cooldown",
            Kind.GLOVE: "pickup_glove"}.get(k, "pickup") as String
        f._sfx(snd)
    return ok


func setup(game_ref: Node, k: int, pos: Vector3, life: float, age: float = 0.0) -> void:
    game = game_ref
    kind = k
    lifetime = life
    position = pos
    _age = age


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

    if _age < 0.3:
        Sfx.play_at("item_spawn", global_position, self)


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
        Kind.CHARGE_UP:
            # 번개: 기울어진 납작한 막대 2개를 지그재그로
            var m := BoxMesh.new()
            m.size = Vector3(0.14, 0.42, 0.1)
            mi.mesh = m
            mi.position = Vector3(0.06, 0.16, 0)
            mi.rotation.z = -0.5
            var mi2 := MeshInstance3D.new()
            mi2.mesh = m
            mi2.material_override = mat
            mi2.position = Vector3(-0.06, -0.16, 0)
            mi2.rotation.z = -0.5
            _pivot.add_child(mi2)
        Kind.COOL_DOWN:
            # 모래시계: 위아래로 맞붙은 원뿔 2개
            var m := CylinderMesh.new()
            m.top_radius = 0.26
            m.bottom_radius = 0.03
            m.height = 0.3
            mi.mesh = m
            mi.position.y = 0.15
            var mi2 := MeshInstance3D.new()
            var m2 := CylinderMesh.new()
            m2.top_radius = 0.03
            m2.bottom_radius = 0.26
            m2.height = 0.3
            mi2.mesh = m2
            mi2.material_override = mat
            mi2.position.y = -0.15
            _pivot.add_child(mi2)
        Kind.GLOVE:
            # 권투 글러브: 주먹(구) + 엄지 + 흰 손목 띠
            var m := SphereMesh.new()
            m.radius = 0.28
            m.height = 0.56
            mi.mesh = m
            mi.scale = Vector3(1.0, 1.05, 1.2)
            var thumb := MeshInstance3D.new()
            var tm := SphereMesh.new()
            tm.radius = 0.12
            tm.height = 0.24
            thumb.mesh = tm
            thumb.material_override = mat
            thumb.position = Vector3(0.22, 0.04, -0.1)
            _pivot.add_child(thumb)
            var cuff := MeshInstance3D.new()
            var cm := CylinderMesh.new()
            cm.top_radius = 0.2
            cm.bottom_radius = 0.22
            cm.height = 0.16
            cuff.mesh = cm
            cuff.material_override = Toon.make(Color(1.0, 0.97, 0.9), {"rim_strength": 0.6})
            cuff.position = Vector3(0, -0.32, 0)
            _pivot.add_child(cuff)
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
    if game and (not game.is_playing() or game.is_client()):
        return              # 온라인 클라이언트: 줍기 판정은 서버가 한다
    for body in get_overlapping_bodies():
        var f := body as Fighter
        if f and not f.dead and apply_to(f, kind):
            if game.has_method(&"on_item_picked"):
                game.on_item_picked(self, f)
            queue_free()
            return
