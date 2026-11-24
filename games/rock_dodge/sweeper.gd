class_name Sweeper
extends Node3D
## 아레나 중앙 축을 중심으로 시계침(풍차)처럼 도는 바닥 기둥. 양쪽 팔이 있어 한 바퀴에 두 번 지나간다.
## - 물리적으로 막는 벽: 어느 쪽에서도 걸어서 통과할 수 없고 점프로 넘어야 한다
## - 회전 진행 방향 쪽에서 닿으면 풀차징 밀치기와 같은 효과(넉백 17 · 띄움 5.5 · 경직 1.8초)
## - 밀려 날아가다 기둥에 부딪히면 아레나 벽과 똑같이 '벽꽝'(경직 1.5배) — arena_wall 그룹

const Toon := preload("res://scripts/world/toon.gd")

@export var arm_length := 17.2
@export var beam_radius := 0.3
@export var beam_height := 0.45        # 기둥 중심 높이(지면 기준). 윗면 = 0.75m
@export var speed_start := 0.35        # rad/s (한 바퀴 약 18초)
@export var speed_end := 0.6           # 최고 난이도 시
@export var hub_radius := 0.9
@export var hit_cooldown := 3.0        # 같은 캐릭터 연속 피격 방지

const HIT_FORCE := 17.0
const HIT_LIFT := 5.5
const HIT_STUN := 1.8

var game: Node
var arena_length_hint := -1.0          # 설정되면 팔 길이 = 아레나 반폭 - 0.8
var angle := 0.0
var _hit_cd := {}
var _beam: AnimatableBody3D


func angular_speed() -> float:
    return lerpf(speed_start, speed_end, game.difficulty())


## 기둥 팔의 방향(월드)
func arm_dir() -> Vector3:
    return Vector3(cos(angle), 0.0, -sin(angle))


## 이 위치에 기둥이 도달하기까지 남은 시간(초). vel: 캐릭터 이동 속도(기둥 쪽으로 달리면 더 빨리 만남)
func time_until_hit(pos: Vector3, vel: Vector3 = Vector3.ZERO) -> float:
    var p := pos - global_position
    p.y = 0.0
    var r := p.length()
    if r < hub_radius + 0.3:
        return INF
    var phi := atan2(-p.z, p.x)
    var delta := wrapf(phi - angle, 0.0, PI)        # 회전 방향(+)으로 남은 각도 (팔이 2개라 π 주기)
    var half_width := (beam_radius + Fighter.RADIUS) / r
    var arc := maxf(delta - half_width, 0.0) * r
    var t_hat := Vector3(p.z, 0.0, -p.x) / r       # 기둥이 움직이는 방향
    var closing := angular_speed() * r - vel.dot(t_hat)
    return arc / maxf(closing, 0.1)


func _ready() -> void:
    if arena_length_hint > 0.0:
        arm_length = arena_length_hint - 0.8
    var stone := Toon.make(Color(0.55, 0.52, 0.5), {"shade_softness": 0.05, "rim_strength": 0.3})

    # 중앙 축 (충돌 있음)
    var hub := StaticBody3D.new()
    add_child(hub)
    var hm := CylinderMesh.new()
    hm.top_radius = hub_radius * 0.85
    hm.bottom_radius = hub_radius
    hm.height = 1.3
    var hmi := MeshInstance3D.new()
    hmi.mesh = hm
    hmi.material_override = stone
    hmi.position.y = 0.65
    hub.add_child(hmi)
    var hs := CylinderShape3D.new()
    hs.radius = hub_radius
    hs.height = 1.3
    var hc := CollisionShape3D.new()
    hc.shape = hs
    hc.position.y = 0.65
    hub.add_child(hc)

    # 회전하는 기둥: 움직이는 물리 벽 (캐릭터만 막는 레이어 4, 벽꽝 대상)
    _beam = AnimatableBody3D.new()
    _beam.collision_layer = 4
    _beam.collision_mask = 0
    _beam.sync_to_physics = true
    _beam.add_to_group(&"arena_wall")
    add_child(_beam)
    var beam_shape := CapsuleShape3D.new()
    beam_shape.radius = beam_radius
    beam_shape.height = arm_length * 2.0 + beam_radius * 2.0
    var col := CollisionShape3D.new()
    col.shape = beam_shape
    col.rotation.z = PI * 0.5                         # Y축 캡슐 → X축으로 눕힘
    col.position.y = beam_height
    _beam.add_child(col)
    var red := Toon.make(Color(0.9, 0.25, 0.2), {"shade_softness": 0.06, "rim_strength": 0.5})
    var white := Toon.make(Color(0.96, 0.94, 0.9), {"shade_softness": 0.06, "rim_strength": 0.5})
    var segs := 14
    var seg_len := arm_length * 2.0 / segs
    for i in segs:
        var cm := CylinderMesh.new()
        cm.top_radius = beam_radius
        cm.bottom_radius = beam_radius
        cm.height = seg_len
        cm.radial_segments = 16
        var mi := MeshInstance3D.new()
        mi.mesh = cm
        mi.material_override = red if i % 2 == 0 else white
        mi.rotation.z = PI * 0.5                      # Y축 원기둥 → X축으로 눕힘
        mi.position = Vector3(-arm_length + seg_len * (i + 0.5), beam_height, 0)
        _beam.add_child(mi)
    for side: float in [-1.0, 1.0]:
        var cap := SphereMesh.new()
        cap.radius = beam_radius * 1.15
        cap.height = beam_radius * 2.3
        var ci := MeshInstance3D.new()
        ci.mesh = cap
        ci.material_override = red
        ci.position = Vector3(side * arm_length, beam_height, 0)
        _beam.add_child(ci)


func _physics_process(delta: float) -> void:
    if game == null:
        return
    if game.is_playing():
        angle = wrapf(angle + angular_speed() * delta, 0.0, TAU)
    _beam.rotation.y = angle
    if not game.is_playing():
        return

    for f in _hit_cd.keys():
        _hit_cd[f] = _hit_cd[f] - delta
        if _hit_cd[f] <= 0.0:
            _hit_cd.erase(f)

    var dir := arm_dir()
    var w := angular_speed()
    for f: Fighter in game.alive_fighters():
        if _hit_cd.has(f):
            continue
        var p := f.global_position - global_position
        var feet := p.y
        p.y = 0.0
        var along := p.dot(dir)
        if absf(along) > arm_length + 0.3:
            continue
        var perp_vec := p - dir * along
        var perp := perp_vec.length()
        # 물리 충돌로 캐릭터는 기둥 표면에 막혀 있으므로 약간의 여유를 둔다
        if perp > beam_radius + Fighter.RADIUS + 0.12:
            continue
        if feet > beam_height + beam_radius - 0.05:
            continue                                   # 점프로 넘음
        # 회전 진행 방향(접선)
        var tangent := Vector3(w * p.z, 0.0, -w * p.x)
        if tangent.length() < 0.3:
            tangent = Vector3(-dir.z, 0.0, dir.x) * signf(along if absf(along) > 0.01 else 1.0)
        # 기둥 뒤쪽(진행 반대편)에서 닿은 것은 그냥 벽 — 쳐내지 않음
        if perp_vec.dot(tangent) < 0.0:
            continue
        var push := tangent.normalized()
        _hit_cd[f] = hit_cooldown
        if f.receive_push(push * HIT_FORCE + Vector3.UP * HIT_LIFT, HIT_STUN, null):
            game.popup_text(f.global_position + Vector3(0, 2.4, 0), "쾅!", Color(1.0, 0.4, 0.3))
