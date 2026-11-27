extends Node3D
## 가면 쓴 진행자 (모든 게임 공용 장식 NPC). 물리·충돌 없음, 화면 전용
##   - 긴 망토 + 두건 + 흰 가면 (가면 무늬는 variant 마다 다름), 흰 장갑, 금색 장식
##   - look_at_point(): 머리(와 천천히 몸)를 그쪽으로 돌림
##   - gesture("clap" | "point" | "cheer" | "hit_l" | "hit_r" | "nod")
## 사용: var h = MaskedHost.new(); h.variant = 0; add_child(h)

const Toon := preload("res://scripts/world/toon.gd")

## 망토 색 (어두운 보석색), 가면 무늬
const ROBE_COLORS: Array[Color] = [
    Color(0.24, 0.16, 0.38), Color(0.10, 0.12, 0.20), Color(0.36, 0.10, 0.16), Color(0.08, 0.26, 0.28),
]
const MASK_STYLES := ["smile", "dots", "slits", "moon"]

@export var variant := 0
@export var body_scale := 1.25          ## 아이들(캐릭터)보다 키가 큼
@export var turn_body := true           ## 몸도 천천히 바라보는 쪽으로
@export var turn_speed := 1.5           ## 몸 돌리는 빠르기 (face() 로 바꿀 수 있음)

var visual: Node3D
var head: Node3D
var left_arm: Node3D
var right_arm: Node3D
var _target := Vector3.INF
var _gesture := ""
var _g_time := 0.0
var _phase := 0.0
var _base_yaw := 0.0


func _ready() -> void:
    _phase = randf() * TAU
    _base_yaw = rotation.y
    _build()


func _build() -> void:
    var v := posmod(variant, ROBE_COLORS.size())
    var robe_c := ROBE_COLORS[v]
    var robe := Toon.make(robe_c, {"rim_strength": 0.55, "shade_softness": 0.06})
    var robe_dark := Toon.make(robe_c.darkened(0.35), {"rim_strength": 0.3, "shade_softness": 0.08})
    var gold := Toon.make(Color(0.95, 0.74, 0.25), {"rim_strength": 0.6, "shade_softness": 0.04})
    var mask := Toon.make(Color(0.97, 0.95, 0.90), {"rim_strength": 0.4, "shade_softness": 0.05})
    var ink := Toon.make(Color(0.08, 0.08, 0.12), {"rim_strength": 0.0, "shade_softness": 0.3})
    var glove := Toon.make(Color(0.98, 0.97, 0.95), {"rim_strength": 0.35, "shade_softness": 0.05})

    visual = Node3D.new()
    visual.scale = Vector3.ONE * body_scale
    add_child(visual)

    # 망토 (아래로 퍼지는 원뿔) + 밑단 금색 테
    var cone := CylinderMesh.new()
    cone.top_radius = 0.2
    cone.bottom_radius = 0.46
    cone.height = 1.12
    cone.radial_segments = 16
    cone.rings = 1
    _part(visual, cone, Vector3(0, 0.56, 0), robe, true)
    var hem := TorusMesh.new()
    hem.inner_radius = 0.42
    hem.outer_radius = 0.5
    hem.rings = 20
    hem.ring_segments = 6
    var hm := _part(visual, hem, Vector3(0, 0.05, 0), gold)
    hm.scale = Vector3(1, 0.5, 1)
    # 가운데 세로 장식줄 + 가슴 브로치
    var stripe := BoxMesh.new()
    stripe.size = Vector3(0.07, 0.9, 0.03)
    var sp := _part(visual, stripe, Vector3(0, 0.55, -0.31), gold)
    sp.rotation.x = -0.21
    _part(visual, _sphere(0.06), Vector3(0, 1.0, -0.21), gold)
    # 어깨
    var sh := _part(visual, _sphere(0.27), Vector3(0, 1.08, 0), robe, true)
    sh.scale = Vector3(1.25, 0.7, 1.0)

    # 머리: 두건 + 가면 (얼굴은 -Z)
    head = Node3D.new()
    head.position = Vector3(0, 1.4, 0)
    visual.add_child(head)
    var hood := _part(head, _sphere(0.3), Vector3(0, 0.03, 0.03), robe, true)
    hood.scale = Vector3(1.0, 1.12, 1.05)
    var peak := CylinderMesh.new()          # 두건 끝 (뒤로 살짝 뾰족)
    peak.top_radius = 0.0
    peak.bottom_radius = 0.16
    peak.height = 0.3
    peak.radial_segments = 10
    peak.rings = 1
    var pk := _part(head, peak, Vector3(0, 0.3, 0.12), robe)
    pk.rotation.x = 0.5
    var opening := _part(head, _sphere(0.25), Vector3(0, 0.0, -0.12), robe_dark)
    opening.scale = Vector3(0.95, 1.05, 0.7)
    var rim := TorusMesh.new()
    rim.inner_radius = 0.22
    rim.outer_radius = 0.27
    rim.rings = 20
    rim.ring_segments = 6
    var rm := _part(head, rim, Vector3(0, 0.0, -0.2), gold)
    rm.rotation.x = PI * 0.5
    rm.scale = Vector3(0.92, 1.0, 1.12)
    var face := _part(head, _sphere(0.2), Vector3(0, -0.01, -0.21), mask)
    face.scale = Vector3(0.95, 1.18, 0.42)
    _mask_face(MASK_STYLES[v % MASK_STYLES.size()], ink, gold)

    # 팔: 넓은 소매 + 흰 장갑
    left_arm = Node3D.new()
    left_arm.position = Vector3(-0.3, 1.1, 0)
    right_arm = Node3D.new()
    right_arm.position = Vector3(0.3, 1.1, 0)
    for arm in [left_arm, right_arm]:
        visual.add_child(arm)
        var sl := CylinderMesh.new()
        sl.top_radius = 0.09
        sl.bottom_radius = 0.15
        sl.height = 0.5
        sl.radial_segments = 10
        sl.rings = 1
        _part(arm, sl, Vector3(0, -0.24, 0), robe)
        _part(arm, _sphere(0.085), Vector3(0, -0.52, 0), glove)


func _mask_face(style: String, ink: Material, gold: Material) -> void:
    var z := -0.295
    match style:
        "smile":            # 웃는 눈 두 개 (∩∩) + 작은 웃는 입
            for s: float in [-1.0, 1.0]:
                var e := _part(head, _capsule(0.016, 0.09), Vector3(s * 0.075, 0.04, z), ink)
                e.rotation = Vector3(0, 0, PI * 0.5)
                e.scale = Vector3(1, 1, 0.6)
                var e2 := _part(head, _sphere(0.03), Vector3(s * 0.075, 0.055, z), ink)
                e2.scale = Vector3(1.4, 0.6, 0.4)
            var m := _part(head, _capsule(0.012, 0.08), Vector3(0, -0.09, z + 0.005), ink)
            m.rotation = Vector3(0, 0, PI * 0.5)
        "dots":             # 둥근 눈구멍 두 개 + 볼 금박
            for s: float in [-1.0, 1.0]:
                var e := _part(head, _sphere(0.035), Vector3(s * 0.075, 0.03, z), ink)
                e.scale = Vector3(1, 1, 0.4)
                var c := _part(head, _sphere(0.025), Vector3(s * 0.11, -0.06, z + 0.01), gold)
                c.scale = Vector3(1.2, 0.8, 0.4)
        "slits":            # 세로로 긴 눈 틈 + 이마 금 장식
            for s: float in [-1.0, 1.0]:
                var e := _part(head, _capsule(0.014, 0.1), Vector3(s * 0.07, 0.02, z), ink)
                e.scale = Vector3(1, 1, 0.5)
            var g := _part(head, _sphere(0.03), Vector3(0, 0.15, z + 0.03), gold)
            g.scale = Vector3(1, 1.3, 0.5)
        _:                  # "moon": 초승달 눈 (한쪽으로 기울어진 짧은 막대) + 금색 줄
            for s: float in [-1.0, 1.0]:
                var e := _part(head, _capsule(0.015, 0.085), Vector3(s * 0.075, 0.035, z), ink)
                e.rotation = Vector3(0, 0, PI * 0.5 + s * 0.45)
                e.scale = Vector3(1, 1, 0.6)
            var l := _part(head, _capsule(0.01, 0.16), Vector3(0, -0.08, z + 0.005), gold)
            l.rotation = Vector3(0, 0, PI * 0.5)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, shadow: bool = false) -> MeshInstance3D:
    if mesh is SphereMesh:
        mesh.radial_segments = clampi(int(mesh.radius * 70.0), 8, 20)
        mesh.rings = mesh.radial_segments / 2
    elif mesh is CapsuleMesh:
        mesh.radial_segments = 8
        mesh.rings = 2
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi


func _sphere(r: float) -> SphereMesh:
    var m := SphereMesh.new()
    m.radius = r
    m.height = r * 2.0
    return m


func _capsule(r: float, h: float) -> CapsuleMesh:
    var m := CapsuleMesh.new()
    m.radius = r
    m.height = maxf(h, r * 2.0)
    return m


# ================================================================ 동작
func look_at_point(p: Vector3) -> void:
    _target = p


func clear_look() -> void:
    _target = Vector3.INF


## 몸을 yaw 쪽으로 (speed: 초당 빠르기 배수 — 술래처럼 홱 돌아볼 때 크게)
func face(yaw: float, speed: float = 1.5) -> void:
    _target = Vector3.INF
    _base_yaw = yaw
    turn_speed = speed


func gesture(kind: String) -> void:
    _gesture = kind
    _g_time = 0.0


func _process(delta: float) -> void:
    if visual == null:
        return
    _phase += delta
    _g_time += delta
    # 숨쉬기
    visual.position.y = sin(_phase * 1.6) * 0.015
    visual.rotation.z = sin(_phase * 0.7) * 0.02
    # 바라보기: 몸은 천천히, 머리는 나머지를 (±60°)
    var want_yaw := _base_yaw
    if _target != Vector3.INF:
        var d := _target - global_position
        if Vector2(d.x, d.z).length() > 0.3:
            want_yaw = atan2(-d.x, -d.z)
    if turn_body:
        rotation.y = lerp_angle(rotation.y, want_yaw, minf(delta * turn_speed, 1.0))
    var rel := clampf(wrapf(want_yaw - rotation.y, -PI, PI), -1.05, 1.05)
    head.rotation.y = lerp_angle(head.rotation.y, rel, minf(delta * 6.0, 1.0))
    var tilt := sin(_phase * 0.9) * 0.05
    # 팔 (x 축 회전: 음수 = 앞으로 듦)
    var la := 0.0
    var ra := 0.0
    var lz := 0.12
    var rz := -0.12
    var g := _g_time
    match _gesture:
        "clap":
            if g < 1.4:
                var c := absf(sin(g * 14.0))
                la = -1.2
                ra = -1.2
                lz = -0.55 + c * 0.35
                rz = 0.55 - c * 0.35
        "point":
            if g < 1.2:
                ra = -1.5 * minf(g * 6.0, 1.0)
                rz = 0.0
        "cheer":
            if g < 1.3:
                var k := minf(g * 6.0, 1.0)
                la = -2.7 * k
                ra = -2.7 * k
                lz = 0.35
                rz = -0.35
                visual.position.y += absf(sin(g * 9.0)) * 0.08
        "hit_l":
            if g < 0.22:
                la = -1.25 + g * 3.0
                lz = -0.15
        "hit_r":
            if g < 0.22:
                ra = -1.25 + g * 3.0
                rz = 0.15
        "nod":
            if g < 0.6:
                tilt += sin(g * 15.0) * 0.18
    var sp := minf(delta * 14.0, 1.0)
    left_arm.rotation.x = lerpf(left_arm.rotation.x, la, sp)
    right_arm.rotation.x = lerpf(right_arm.rotation.x, ra, sp)
    left_arm.rotation.z = lerpf(left_arm.rotation.z, lz, sp)
    right_arm.rotation.z = lerpf(right_arm.rotation.z, rz, sp)
    head.rotation.x = lerpf(head.rotation.x, tilt, sp)
