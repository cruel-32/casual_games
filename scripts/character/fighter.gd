class_name Fighter
extends CharacterBody3D
## 대결 캐릭터 (사람/봇 공용)
## - 이동, 점프
## - 밀치기: 짧게 누르면 제자리 밀기, 길게 누르면 차징(이동 감속 + 화살표) → 떼면 화살표 방향으로 돌진하며 밀쳐냄
##   풀차징: 더 멀리 돌진. 차징이 길수록 쿨타임 증가 (무적은 무적 아이템으로만)
## - 맞으면 넉백 + 경직(조작 불가), 몸끼리 부딪히면 살짝 튕김
## - 낙석에 닿으면 사망
## 사람은 입력을, 봇은 BotBrain이 intent_* 값을 채운다.
## 온라인: remote = true 인 캐릭터는 직접 움직이지 않고 네트워크로 받은 상태를 보여주기만 한다
##   (클라이언트: 나 이외 전원 / 서버: 사람 플레이어 — 각자 자기 PC에서 움직임)

signal died(fighter: Fighter)

const Toon := preload("res://scripts/world/toon.gd")
const Procedural := preload("res://scripts/world/procedural.gd")
const SHIELD_SHADER := preload("res://shaders/shield.gdshader")

@export_group("Move")
@export var move_speed := 6.0
@export var jump_velocity := 9.2         # 점프 높이는 예전(6.5 / 중력 1배)과 비슷하게, 대신 빠르게 오르내림
@export var ground_accel := 14.0
@export var air_accel := 4.0
@export var charge_move_mult := 0.55

@export_group("Push")
@export var charge_max_time := 1.2          # 이 시간 이상 누르면 풀차징
@export var tap_threshold := 0.15           # 이보다 짧게 누르면 '탭 밀기'
@export var tap_cooldown := 0.3            # 탭은 제자리 밀기 대신 쿨타임이 짧다
@export var charge_cooldown_min := 0.6
@export var charge_cooldown_max := 1.8
@export var dash_distance_min := 1.0
@export var dash_distance_max := 3.5
@export var push_reach := 1.45
@export var tap_lock_time := 0.3            # 탭 밀치기 동안 제자리 정지
@export var dash_end_lock_min := 0.25       # 차징 돌진 후 제자리 정지 (차징 0%)
@export var dash_end_lock_max := 0.45       # 〃 (풀차징)

@export_group("Look")
@export var body_color := Color(0.78, 0.58, 0.44)
@export var display_name := "Bot"
@export var is_human := false
@export var mouse_sensitivity := 0.0025

## 슬롯(참가 순서)별 몸 색 — 게임 안 캐릭터와 대기룸 초상화(ui/portraits/slot_N.png)가 같은 색을 쓴다
const SLOT_COLORS: Array[Color] = [
    Color(0.85, 0.22, 0.22), Color(0.22, 0.42, 0.90), Color(0.95, 0.68, 0.08),
    Color(0.25, 0.65, 0.22), Color(0.55, 0.28, 0.85), Color(0.95, 0.45, 0.10),
    Color(0.10, 0.65, 0.70), Color(0.88, 0.30, 0.60),
]
const RADIUS := 0.4
const HEIGHT := 1.65
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const BUMP_FORCE := 3.5
const MAX_HELMETS := 2
const JUMP_GRAVITY_MULT := 2.0      # 스스로 점프한 동안의 중력 배수 (넉백으로 뜬 것은 1배)
const MAX_STACKS := 8               # 차징 가속·쿨타임 감소 아이템 최대 중첩
const CHARGE_RATE_PER_STACK := 0.25 # 차징 속도 +25% / 개
const COOLDOWN_PER_STACK := 0.2     # 쿨타임 = 기본 / (1 + 0.2 × 개수)
const BOOTS_TIME := 8.0
const WALL_SLAM_STUN_MULT := 1.5
const CHAIN_MIN_SPEED := 5.0
const CLASH_FORCE := 11.0
const PUSH_FORCE := 17.0         # 밀치기 넉백 (탭·차징 공통 = 풀차징 수준)
const PUSH_LIFT := 5.5

var game: Node
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# 터치 입력 (TouchControls 가 채움)
var touch_mode := false
var touch_move := Vector2.ZERO      # 스틱: x 오른쪽, y 아래(=뒤) — Input.get_vector 와 같은 방향
var touch_jump := false             # 눌린 순간 true, 한 번 쓰고 false
var touch_push := false             # 누르고 있는 동안 true (차징)

# 조작 의도
var intent_move := Vector3.ZERO     # 월드 방향, 길이 0~1
var intent_face := Vector3.ZERO     # 봇: 바라볼 방향 (0이면 이동 방향)
var intent_jump := false
var intent_charge := false          # 밀치기 키를 누르고 있는가

# 온라인 동기화
var slot := 0                       # 게임 안 캐릭터 번호 (네트워크 메시지에서 이 번호로 가리킴)
var peer_id := 0                    # 사람 플레이어의 접속 id (봇·오프라인은 0)
var remote := false
var net_on_floor := true
var net_invuln := false             # 주인이 보낸 무적 여부
var net_buffer: Array = []          # 클라이언트: 보간용 상태 버퍼
var net_history: Array = []         # 서버: [[t, pos], ...] 최근 1초 위치 (판정 검증용)
var net_pending: Array = []         # 서버: 아직 낙석 판정하지 않은 사람 플레이어 상태
var net_lag := 0.15                 # 클라이언트: 이 캐릭터 상태가 도착하기까지 걸리는 시간(추정)
var net_rejects := 0                # 서버: 속도 검사에 걸려 무시한 연속 횟수

# 상태
var dead := false
var control_vel := Vector3.ZERO
var knock := Vector3.ZERO
var stun_timer := 0.0
var invuln_timer := 0.0
var cooldown_timer := 0.0
var cooldown_total := 1.0
var charging := false
var charge_time := 0.0
var dash_timer := 0.0
var dash_speed := 0.0
var lock_timer := 0.0               # >0 이면 이동 불가(제자리). 돌진 시간 + 돌진 후 정지 시간
var push_window := 0.0
var push_power := 0.0
var push_tap := true
var push_anim := 0.0
var bump_cooldown := 0.0
var shake := 0.0

# 아이템
var helmets := 0
var heavy_timer := 0.0
var shield_timer := 0.0             # 무적 아이템 (헬멧이 막은 직후의 짧은 무적 invuln_timer 와 별개 — 보호막 연출용)
var charge_stacks := 0              # 차징 가속 아이템 개수 (경기 끝까지 유지, 중첩)
var cooldown_stacks := 0            # 쿨타임 감소 아이템 개수 (〃)
var _jump_arc := false              # 스스로 점프해서 떠 있는 중 (중력 배수 적용)

# 밀치기 상호작용
var kills := 0
var last_attacker: Fighter = null
var last_attacker_time := -100.0
var wall_slam_armed := false
var chain_armed := false
var chain_hits: Array[Fighter] = []

var _charge_was_pressed := false
var _push_hits: Array[Fighter] = []
var _coyote := 0.0
var _jump_buffer := 0.0
var _t := 0.0
var _anim_time := 0.0
var _anim_amp := 0.0
var _air_blend := 0.0

# 노드
var visual: Node3D
var head: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var skin_mat: ShaderMaterial
var arrow: Node3D
var arrow_shaft: MeshInstance3D
var arrow_head: MeshInstance3D
var arrow_mat: StandardMaterial3D
var name_tag: Label3D
var helmet_mi: Node3D
var helmet_mat: ShaderMaterial
var helmet_trim_mat: ShaderMaterial
var helmet_extra: Node3D
var boots: Array[Node3D] = []
var shield_mi: Node3D
var shield_mat: ShaderMaterial
var shield_rings: Array[MeshInstance3D] = []
var pitch_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D


func _ready() -> void:
    add_to_group(&"fighters")
    collision_layer = 2               # 캐릭터
    collision_mask = 1 | 2 | 4        # 지형/오브젝트, 캐릭터, 아레나 벽
    floor_snap_length = 0.3
    _build_collision()
    _build_mannequin()
    _build_item_visuals()
    _build_arrow()
    _build_name_tag()
    if is_human:
        _build_camera()
        if not touch_device():
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ================================================================ 조회
func facing() -> Vector3:
    var f := -global_transform.basis.z
    f.y = 0.0
    return f.normalized()


func get_charge_ratio() -> float:
    if not charging:
        return 0.0
    return clampf((charge_time - tap_threshold) / (charge_full_time() - tap_threshold), 0.0, 1.0)


## 풀차징까지 걸리는 시간 (차징 가속 아이템이 많을수록 짧아짐)
func charge_full_time() -> float:
    return tap_threshold + (charge_max_time - tap_threshold) / (1.0 + CHARGE_RATE_PER_STACK * charge_stacks)


## 쿨타임 배수 (쿨타임 감소 아이템이 많을수록 작아짐)
func cooldown_mult() -> float:
    return 1.0 / (1.0 + COOLDOWN_PER_STACK * cooldown_stacks)


func dash_distance_for(c: float) -> float:
    return lerpf(dash_distance_min, dash_distance_max, c)


func is_invulnerable() -> bool:
    return invuln_timer > 0.0 or shield_timer > 0.0 or net_invuln


func is_stunned() -> bool:
    return stun_timer > 0.0


func can_act() -> bool:
    return not dead and (game == null or game.is_playing())


# ================================================================ 구성
func _build_collision() -> void:
    var col := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = RADIUS
    shape.height = HEIGHT
    col.shape = shape
    col.position.y = HEIGHT * 0.5
    add_child(col)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)
    return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
    var m := CapsuleMesh.new()
    m.radius = radius
    m.height = height
    return m


func _sphere(radius: float) -> SphereMesh:
    var m := SphereMesh.new()
    m.radius = radius
    m.height = radius * 2.0
    return m


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
    var p := Node3D.new()
    p.position = pos
    parent.add_child(p)
    return p


func _build_mannequin() -> void:
    # 2등신: 머리가 몸통만큼 크고 팔다리가 짧다
    skin_mat = Toon.make(body_color, {"rim_strength": 0.45, "shade_softness": 0.05})       # 옷 (캐릭터 색)
    var face := Toon.make(Color(1.0, 0.87, 0.76), {"rim_strength": 0.35, "shade_softness": 0.08})
    var dark := Toon.make(Color(0.24, 0.25, 0.32), {"rim_strength": 0.3, "shade_softness": 0.05})
    var eye := Toon.make(Color(0.07, 0.07, 0.1), {"rim_strength": 0.0, "shade_softness": 0.3})
    var shine := Toon.make(Color(1, 1, 1), {"rim_strength": 0.0, "shade_softness": 0.5, "shadow_strength": 1.0})
    var cheek := Toon.make(Color(1.0, 0.55, 0.6), {"rim_strength": 0.0, "shade_softness": 0.3})

    visual = Node3D.new()
    visual.name = "Chibi"
    add_child(visual)

    # 몸통 (짧고 통통)
    _part(visual, _capsule(0.27, 0.62), Vector3(0, 0.66, 0), skin_mat)

    # 머리
    head = _pivot(visual, Vector3(0, 1.22, 0))
    _part(head, _sphere(0.42), Vector3.ZERO, face)
    for side: float in [-1.0, 1.0]:
        var e := _part(head, _sphere(0.06), Vector3(side * 0.14, 0.03, -0.395), eye)
        e.scale = Vector3(1.0, 1.5, 0.6)
        var sh := _part(head, _sphere(0.018), Vector3(side * 0.14 + 0.02, 0.07, -0.43), shine)
        sh.scale = Vector3(1, 1, 0.5)
        var c := _part(head, _sphere(0.065), Vector3(side * 0.25, -0.1, -0.33), cheek)
        c.scale = Vector3(1.3, 0.7, 0.4)
    # 머리 위 방울 (캐릭터 색)
    _part(head, _sphere(0.09), Vector3(0, 0.5, 0.02), skin_mat)
    _part(head, _capsule(0.025, 0.12), Vector3(0, 0.43, 0.02), skin_mat)

    # 팔 (어깨 피벗에서 아래로)
    left_arm = _pivot(visual, Vector3(-0.32, 0.86, 0))
    right_arm = _pivot(visual, Vector3(0.32, 0.86, 0))
    for arm in [left_arm, right_arm]:
        _part(arm, _capsule(0.085, 0.34), Vector3(0, -0.15, 0), skin_mat)
        _part(arm, _sphere(0.1), Vector3(0, -0.32, 0), face)

    # 다리 (엉덩이 피벗에서 아래로) + 발
    left_leg = _pivot(visual, Vector3(-0.13, 0.36, 0))
    right_leg = _pivot(visual, Vector3(0.13, 0.36, 0))
    for leg in [left_leg, right_leg]:
        _part(leg, _capsule(0.1, 0.34), Vector3(0, -0.16, 0), dark)
        var foot := _part(leg, _sphere(0.11), Vector3(0, -0.31, -0.04), dark)
        foot.scale = Vector3(1.0, 0.7, 1.35)


func _build_item_visuals() -> void:
    # 헬멧: 눈에 띄는 안전모 (돔 + 둥근 챙 + 가운데 볏). 1개 = 노랑, 2개 = 빨강 + 크게
    helmet_mat = Toon.make(Color(1.0, 0.82, 0.05), {"rim_strength": 1.2, "shade_softness": 0.04})
    helmet_trim_mat = Toon.make(Color(1, 1, 1), {"rim_strength": 0.8, "shade_softness": 0.04})
    helmet_mi = Node3D.new()
    helmet_mi.position = Vector3(0, 0.1, 0)
    helmet_mi.visible = false
    head.add_child(helmet_mi)
    var dome := SphereMesh.new()
    dome.radius = 0.48
    dome.height = 0.46
    dome.is_hemisphere = true
    _part(helmet_mi, dome, Vector3.ZERO, helmet_mat)
    var brim := CylinderMesh.new()
    brim.top_radius = 0.6
    brim.bottom_radius = 0.62
    brim.height = 0.05
    _part(helmet_mi, brim, Vector3(0, 0.01, 0), helmet_mat)
    var crest := BoxMesh.new()
    crest.size = Vector3(0.1, 0.08, 0.78)
    _part(helmet_mi, crest, Vector3(0, 0.44, 0), helmet_trim_mat)
    # 2중 헬멧 표시: 흰 띠 + 위로 솟은 두 번째 돔
    helmet_extra = Node3D.new()
    helmet_extra.visible = false
    helmet_mi.add_child(helmet_extra)
    var band := CylinderMesh.new()
    band.top_radius = 0.47
    band.bottom_radius = 0.5
    band.height = 0.1
    _part(helmet_extra, band, Vector3(0, 0.12, 0), helmet_trim_mat)
    var dome2 := SphereMesh.new()
    dome2.radius = 0.3
    dome2.height = 0.26
    dome2.is_hemisphere = true
    _part(helmet_extra, dome2, Vector3(0, 0.36, 0), helmet_mat)

    # 무거운 신발
    var bm := BoxMesh.new()
    bm.size = Vector3(0.26, 0.18, 0.36)
    var boot_mat := Toon.make(Color(0.45, 0.28, 0.16), {"rim_strength": 0.3})
    for leg in [left_leg, right_leg]:
        var b := _part(leg, bm, Vector3(0, -0.3, -0.05), boot_mat)
        b.visible = false
        boots.append(b)

    # 무적 보호막: 몸을 감싸는 빛나는 구(가장자리가 밝음) + 주위를 도는 고리 2개
    shield_mi = Node3D.new()
    shield_mi.position = Vector3(0, HEIGHT * 0.5, 0)
    shield_mi.visible = false
    add_child(shield_mi)
    shield_mat = ShaderMaterial.new()
    shield_mat.shader = SHIELD_SHADER
    var bubble := SphereMesh.new()
    bubble.radius = 0.95
    bubble.height = 1.9
    var bmi := MeshInstance3D.new()
    bmi.mesh = bubble
    bmi.material_override = shield_mat
    bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    shield_mi.add_child(bmi)
    var ring_mat := StandardMaterial3D.new()
    ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    ring_mat.albedo_color = Color(1.0, 0.92, 0.45)
    ring_mat.emission_enabled = true
    ring_mat.emission = Color(1.0, 0.85, 0.3)
    var ring := TorusMesh.new()
    ring.inner_radius = 0.97
    ring.outer_radius = 1.06
    for i in 2:
        var rmi := MeshInstance3D.new()
        rmi.mesh = ring
        rmi.material_override = ring_mat
        rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        rmi.rotation = Vector3(0.6 if i == 0 else -0.6, 0.0, 0.3 if i == 0 else -0.3)
        shield_mi.add_child(rmi)
        shield_rings.append(rmi)

func _update_item_fx() -> void:
    helmet_mi.visible = helmets > 0
    if helmets >= 2:
        helmet_mat.set_shader_parameter("albedo", Color(0.9, 0.1, 0.08))
        helmet_mi.scale = Vector3.ONE * 1.1
        helmet_extra.visible = true
    else:
        helmet_mat.set_shader_parameter("albedo", Color(1.0, 0.82, 0.05))
        helmet_mi.scale = Vector3.ONE
        helmet_extra.visible = false
    for b in boots:
        b.visible = heavy_timer > 0.0


func _build_arrow() -> void:
    arrow_mat = StandardMaterial3D.new()
    arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    arrow_mat.no_depth_test = true
    arrow_mat.render_priority = 2

    arrow = Node3D.new()
    arrow.position.y = 0.08
    arrow.visible = false
    add_child(arrow)

    var shaft := PlaneMesh.new()
    shaft.size = Vector2(0.32, 1.0)
    arrow_shaft = MeshInstance3D.new()
    arrow_shaft.mesh = shaft
    arrow_shaft.material_override = arrow_mat
    arrow_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    arrow.add_child(arrow_shaft)

    arrow_head = MeshInstance3D.new()
    arrow_head.mesh = Procedural.make_arrow_head(0.9, 0.7)
    arrow_head.material_override = arrow_mat
    arrow_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    arrow.add_child(arrow_head)


func _build_name_tag() -> void:
    name_tag = Label3D.new()
    name_tag.text = display_name
    name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    name_tag.font_size = 40
    name_tag.outline_size = 10
    name_tag.pixel_size = 0.006
    name_tag.position.y = 2.05
    name_tag.visible = not is_human
    add_child(name_tag)


func _build_camera() -> void:
    pitch_pivot = _pivot(self, Vector3(0, 1.3, 0))
    pitch_pivot.name = "PitchPivot"
    pitch_pivot.rotation.x = deg_to_rad(-12.0)

    spring_arm = SpringArm3D.new()
    spring_arm.position = Vector3(0.55, 0, 0)
    spring_arm.spring_length = 4.0
    spring_arm.margin = 0.15
    spring_arm.collision_mask = 1          # 지형/오브젝트만 (벽·캐릭터는 통과)
    var probe := SphereShape3D.new()
    probe.radius = 0.2
    spring_arm.shape = probe
    spring_arm.add_excluded_object(get_rid())
    pitch_pivot.add_child(spring_arm)

    camera = Camera3D.new()
    camera.fov = 70.0
    camera.far = 600.0
    camera.current = true
    spring_arm.add_child(camera)


# ================================================================ 입력 (사람)
func _unhandled_input(event: InputEvent) -> void:
    if not is_human:
        return
    var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

    if touch_mode:
        return      # 터치 기기: 시점·버튼은 TouchControls 가 처리 (터치가 흉내 낸 마우스 입력은 무시)
    if event is InputEventMouseMotion and captured:
        var motion := event as InputEventMouseMotion
        apply_look(motion.relative * mouse_sensitivity)
    elif event is InputEventMouseButton and event.pressed:
        var mb := event as InputEventMouseButton
        if not captured and mb.button_index == MOUSE_BUTTON_LEFT:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            get_viewport().set_input_as_handled()
        elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            spring_arm.spring_length = clampf(spring_arm.spring_length - 0.4, 1.5, 9.0)
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            spring_arm.spring_length = clampf(spring_arm.spring_length + 0.4, 1.5, 9.0)
    elif event.is_action_pressed(&"ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 휴대폰·태블릿인가 (모바일 앱, 안드로이드/iOS 웹, iPad 웹)
## 터치스크린 노트북은 제외 — 마우스 조작을 유지한다
static func touch_device() -> bool:
    if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
        return true
    # iPad Safari 는 macOS 로 보고되지만 Mac 에는 터치스크린이 없다
    return OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available()


## 시점 회전 (라디안 단위: x = 좌우, y = 상하). 마우스·터치 공용
func apply_look(delta_rad: Vector2) -> void:
    if pitch_pivot == null:
        return
    if dead:
        pitch_pivot.rotation.y -= delta_rad.x
    else:
        rotate_y(-delta_rad.x)
    pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x - delta_rad.y,
            deg_to_rad(-70.0), deg_to_rad(50.0))


func _read_human_input() -> void:
    if touch_mode:
        var tv := touch_move
        var td := global_transform.basis * Vector3(tv.x, 0.0, tv.y)
        td.y = 0.0
        intent_move = td.normalized() * minf(tv.length(), 1.0) if td.length() > 0.001 else Vector3.ZERO
        intent_jump = touch_jump
        touch_jump = false
        intent_charge = touch_push
        return
    var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
    var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
    var d := global_transform.basis * Vector3(v.x, 0.0, v.y)
    d.y = 0.0
    intent_move = d.normalized() * minf(v.length(), 1.0) if d.length() > 0.001 else Vector3.ZERO
    intent_jump = Input.is_action_just_pressed(&"jump")
    intent_charge = captured and Input.is_action_pressed(&"push")


# ================================================================ 물리
func _physics_process(delta: float) -> void:
    _t += delta
    _tick_timers(delta)
    if remote:
        # 위치·상태는 게임이 네트워크로 받은 값으로 채운다. 여기선 보이기만.
        _animate(delta)
        if dead:
            return
        _update_arrow()
        _update_invuln_fx()
        _update_item_fx()
        return
    if is_human:
        _read_human_input()

    if not is_on_floor():
        velocity.y -= gravity * (JUMP_GRAVITY_MULT if _jump_arc else 1.0) * delta

    if dead:
        knock *= exp(-5.0 * delta)
        velocity.x = knock.x
        velocity.z = knock.z
        move_and_slide()
        _animate(delta)
        return

    var on_floor := is_on_floor()
    var controllable := can_act() and not is_stunned()

    # 점프 (코요테 타임 + 입력 버퍼)
    _coyote = COYOTE if on_floor else _coyote - delta
    if controllable and intent_jump:
        _jump_buffer = JUMP_BUFFER
    else:
        _jump_buffer -= delta
    intent_jump = false
    if on_floor and velocity.y <= 0.0:
        _jump_arc = false
    if _jump_buffer > 0.0 and _coyote > 0.0 and controllable and lock_timer <= 0.0:
        velocity.y = jump_velocity
        _jump_arc = true
        _jump_buffer = 0.0
        _coyote = 0.0
        if charging:
            _cancel_charge(false)       # 점프하면 차징 취소

    # 봇 회전 (사람은 마우스로 회전)
    if not is_human and controllable and lock_timer <= 0.0:
        var look := intent_face if intent_face.length() > 0.01 else intent_move
        look.y = 0.0
        if look.length() > 0.01:
            var yaw := atan2(-look.x, -look.z)
            var turn := 14.0 if charging else 9.0
            rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * turn, 0.0, 1.0))

    _update_push(delta, controllable and intent_charge)

    # 수평 이동 = 조작 속도 + 넉백
    var desired := Vector3.ZERO
    if controllable:
        desired = intent_move.limit_length(1.0) * move_speed * (charge_move_mult if charging else 1.0)
    var accel := ground_accel if on_floor else air_accel
    if is_stunned():
        accel = 3.0
    control_vel = control_vel.lerp(desired, clampf(accel * delta, 0.0, 1.0))

    var h := control_vel + knock
    if dash_timer > 0.0:
        h = facing() * dash_speed + knock
        control_vel = Vector3.ZERO
    elif lock_timer > 0.0:
        control_vel = Vector3.ZERO          # 밀치기 동작/돌진 직후 제자리 정지
        h = knock
    velocity.x = h.x
    velocity.z = h.z
    move_and_slide()
    _check_wall_slam()
    knock *= exp(-4.5 * delta)
    if knock.length() < 4.0:
        chain_armed = false

    _check_push_hits()

    if global_position.y < -30.0:
        global_position = Vector3(0, 5, 0)
        velocity = Vector3.ZERO

    if is_human:
        RenderingServer.global_shader_parameter_set(&"player_position", global_position)

    _animate(delta)
    _update_arrow()
    _update_invuln_fx()
    _update_item_fx()


func _process(_delta: float) -> void:
    if camera:
        camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.15
        camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.15


func _tick_timers(delta: float) -> void:
    stun_timer = maxf(stun_timer - delta, 0.0)
    invuln_timer = maxf(invuln_timer - delta, 0.0)
    cooldown_timer = maxf(cooldown_timer - delta, 0.0)
    push_anim = maxf(push_anim - delta, 0.0)
    push_window = maxf(push_window - delta, 0.0)
    dash_timer = maxf(dash_timer - delta, 0.0)
    lock_timer = maxf(lock_timer - delta, 0.0)
    bump_cooldown = maxf(bump_cooldown - delta, 0.0)
    shake = maxf(shake - delta * 2.5, 0.0)
    shield_timer = maxf(shield_timer - delta, 0.0)
    heavy_timer = maxf(heavy_timer - delta, 0.0)


# ================================================================ 밀치기
func _update_push(delta: float, pressed: bool) -> void:
    var grounded := is_on_floor() or _coyote > 0.0
    if charging:
        if not can_act() or is_stunned():
            _cancel_charge()
        elif not grounded:
            _cancel_charge(false)       # 공중에 뜨면(점프·낙하·띄워짐) 차징 취소
        else:
            charge_time += delta
            if not pressed:
                _release_push()
    elif pressed and not _charge_was_pressed and cooldown_timer <= 0.0 and dash_timer <= 0.0 and grounded:
        charging = true
        charge_time = 0.0
    _charge_was_pressed = pressed


## penalty: 경직 등으로 끊겼을 때 짧은 쿨타임. 점프로 스스로 취소한 경우는 쿨타임 없음
func _cancel_charge(penalty: bool = true) -> void:
    charging = false
    if penalty:
        cooldown_total = maxf(cooldown_timer, 0.25)
        cooldown_timer = cooldown_total


func _release_push() -> void:
    var tap := charge_time < tap_threshold
    var c := 0.0 if tap else get_charge_ratio()
    charging = false
    push_tap = tap
    push_power = c
    _push_hits.clear()
    push_anim = 0.35

    var dash_time: float
    var lock_after := 0.0
    if tap:
        dash_time = 0.12       # 제자리 밀기
        dash_speed = 0.0
        lock_after = maxf(tap_lock_time - dash_time, 0.0)
        cooldown_total = tap_cooldown * cooldown_mult()
    else:
        dash_time = lerpf(0.12, 0.22, c)
        dash_speed = dash_distance_for(c) / dash_time
        cooldown_total = lerpf(charge_cooldown_min, charge_cooldown_max, c) * cooldown_mult()
        lock_after = lerpf(dash_end_lock_min, dash_end_lock_max, c)
    dash_timer = dash_time
    lock_timer = dash_time + lock_after
    push_window = dash_time + 0.12
    cooldown_timer = cooldown_total


func _check_push_hits() -> void:
    if push_window <= 0.0:
        return
    var f := facing()
    for o: Fighter in _others():
        if o == self or o.dead or _push_hits.has(o):
            continue
        var to := o.global_position - global_position
        to.y = 0.0
        var d := to.length()
        if d > push_reach or d < 0.001:
            continue
        if f.dot(to / d) < 0.35:
            continue
        _push_hits.append(o)
        var dir := (to / d + f).normalized()

        # 맞밀치기: 서로 마주 보고 동시에 밀면 둘 다 크게 튕김 (무적이면 이긴다)
        # (온라인에서 다른 PC가 움직이는 캐릭터와는 판정하지 않음)
        if not o.remote and o.push_window > 0.0 and o.facing().dot(-to / d) > 0.4:
            o._push_hits.append(self)
            o.receive_push(dir * CLASH_FORCE + Vector3.UP * 3.0, 0.5, self)
            receive_push(-dir * CLASH_FORCE + Vector3.UP * 3.0, 0.5, o)
            _popup((global_position + o.global_position) * 0.5, "맞밀치기!", Color(1.0, 0.9, 0.3))
            return

        # 무거운 신발: 밀리지 않고 미는 쪽이 튕김
        if o.heavy_timer > 0.0:
            dash_timer = 0.0
            push_window = 0.0
            knock += -dir * 5.0
            _popup(o.global_position, "꿈쩍 안 함!", Color(0.8, 0.6, 0.4))
            return

        # 밀려나는 거리는 탭이든 차징이든 항상 풀차징과 같다. 차징 정도는 경직 시간에만 반영
        var force := PUSH_FORCE
        var lift := PUSH_LIFT
        var stun := 0.45 if push_tap else lerpf(0.8, 1.8, push_power)
        if _deliver_push(o, dir * force + Vector3.UP * lift, stun):
            dash_timer = 0.0
            knock += -dir * 1.5
            shake = maxf(shake, 0.3)


func _others() -> Array:
    if game and "fighters" in game:
        return game.fighters
    return get_tree().get_nodes_in_group(&"fighters")


## 상대에게 밀치기 전달. 온라인이면 게임이 서버/상대 PC로 보낸다
func _deliver_push(o: Fighter, impulse: Vector3, stun: float) -> bool:
    if game and game.has_method(&"deliver_push"):
        return game.deliver_push(self, o, impulse, stun)
    return o.receive_push(impulse, stun, self)


## 밀치기에 맞음. 무적/무거운 신발이면 무시하고 false
## attacker: 킬 크레딧 대상 (연쇄 충돌이면 최초로 민 사람)
func receive_push(impulse: Vector3, stun: float, attacker: Fighter = null) -> bool:
    if dead or is_invulnerable() or heavy_timer > 0.0:
        return false
    knock = Vector3(impulse.x, 0.0, impulse.z)
    control_vel = Vector3.ZERO
    velocity.y = maxf(velocity.y, impulse.y)
    _jump_arc = false               # 넉백으로 뜬 궤적은 보통 중력
    stun_timer = maxf(stun_timer, stun)
    dash_timer = 0.0
    lock_timer = 0.0
    push_window = 0.0
    wall_slam_armed = true
    chain_armed = true
    chain_hits.clear()
    if attacker and attacker != self:
        last_attacker = attacker
        last_attacker_time = Time.get_ticks_msec() * 0.001
    if charging:
        _cancel_charge()
    shake = maxf(shake, 0.6)
    return true


## 몸끼리 부딪혔을 때 살짝 튕김
func bump(impulse: Vector3) -> void:
    if dead or bump_cooldown > 0.0 or dash_timer > 0.0 or heavy_timer > 0.0:
        return
    knock += impulse
    bump_cooldown = 0.3


## 낙석에 맞음. 반환: 0 = 무시(무적), 1 = 사망, 2 = 헬멧이 막음
func kill() -> int:
    if dead or is_invulnerable():
        return 0
    if helmets > 0:
        lose_helmet()
        _popup(global_position, "헬멧 파괴! (%d/%d)" % [helmets, MAX_HELMETS], Color(1.0, 0.8, 0.3))
        return 2
    die()
    return 1


## 헬멧 1개가 낙석을 막고 부서짐
func lose_helmet() -> void:
    helmets = maxi(helmets - 1, 0)
    invuln_timer = maxf(invuln_timer, 0.6)   # 같은 돌에 연속으로 맞지 않게
    shake = maxf(shake, 0.7)


## 사망 처리 (헬멧·무적 무시). 온라인에서는 서버가 정한 사망을 그대로 반영할 때도 쓴다
func die() -> void:
    if dead:
        return
    dead = true
    charging = false
    dash_timer = 0.0
    stun_timer = 0.0
    collision_layer = 0
    collision_mask = 1
    arrow.visible = false
    skin_mat.set_shader_parameter("albedo", body_color.darkened(0.5).lerp(Color(0.5, 0.5, 0.5), 0.5))
    skin_mat.set_shader_parameter("rim_strength", 0.1)
    name_tag.modulate = Color(0.6, 0.6, 0.6, 0.6)
    shake = 1.0
    helmet_mi.visible = false
    shield_mi.visible = false
    for b in boots:
        b.visible = false
    died.emit(self)


# ---- 파워업 (게임 모듈의 아이템이 호출하는 공용 효과)
## 헬멧 1개 추가. 이미 최대면 false
func add_helmet() -> bool:
    if helmets >= MAX_HELMETS:
        return false
    helmets += 1
    return true


## 차징 가속 1개 추가 (중첩). 이미 최대면 false
func add_charge_stack() -> bool:
    if charge_stacks >= MAX_STACKS:
        return false
    charge_stacks += 1
    return true


## 쿨타임 감소 1개 추가 (중첩). 이미 최대면 false
func add_cooldown_stack() -> bool:
    if cooldown_stacks >= MAX_STACKS:
        return false
    cooldown_stacks += 1
    cooldown_timer = minf(cooldown_timer, cooldown_total * cooldown_mult())
    return true


func give_heavy(seconds: float = BOOTS_TIME) -> void:
    heavy_timer = maxf(heavy_timer, seconds)
    knock = Vector3.ZERO


## 무적 아이템: 보호막 (낙석·밀치기 모두 무시)
func give_invuln(seconds: float) -> void:
    shield_timer = maxf(shield_timer, seconds)


func _check_wall_slam() -> void:
    if not wall_slam_armed:
        return
    if knock.length() < 3.0:
        wall_slam_armed = false
        return
    for i in get_slide_collision_count():
        var col := get_slide_collision(i)
        var other := col.get_collider() as Node
        if other and other.is_in_group(&"arena_wall"):
            var nrm := col.get_normal()
            nrm.y = 0.0
            if nrm.length() < 0.1:
                continue
            nrm = nrm.normalized()
            if knock.dot(nrm) < -2.0:
                wall_slam_armed = false
                stun_timer = stun_timer * WALL_SLAM_STUN_MULT + 0.2
                knock = knock.bounce(nrm) * 0.35
                shake = maxf(shake, 0.8)
                _popup(global_position, "벽꽝!", Color(1.0, 0.55, 0.2))
                return


func _popup(pos: Vector3, text: String, color: Color) -> void:
    if game and game.has_method(&"popup_text"):
        game.popup_text(pos + Vector3(0, 2.4, 0), text, color, not remote)


# ================================================================ 연출
func _update_arrow() -> void:
    arrow.visible = charging
    if not charging:
        return
    var c := get_charge_ratio()
    var tapping := charge_time < tap_threshold
    var length := 0.6 if tapping else dash_distance_for(c)
    var start := 0.45
    arrow_shaft.position.z = -(start + length * 0.5)
    arrow_shaft.scale = Vector3(1.0, 1.0, length)
    arrow_head.position.z = -(start + length)

    var col := Color(1.0, 0.88, 0.25).lerp(Color(1.0, 0.22, 0.1), c)
    col.a = 0.55 + 0.25 * c
    if c >= 0.999:
        col = Color(1.0, 0.95, 0.95).lerp(Color(1.0, 0.2, 0.1), 0.5 + 0.5 * sin(_t * 25.0))
        col.a = 0.9
    arrow_mat.albedo_color = col


func _update_invuln_fx() -> void:
    var shielded := shield_timer > 0.0
    shield_mi.visible = shielded and not dead
    if shielded:
        # 끝나기 1.5초 전부터 빠르게 깜빡여 곧 풀린다는 걸 알림 (원격 캐릭터는 남은 시간을 모름 → 깜빡이지 않음)
        var ending := not remote and shield_timer < 1.5
        var pulse := 0.75 + 0.25 * sin(_t * 6.0)
        if ending and fmod(_t * 8.0, 1.0) < 0.45:
            pulse = 0.15
        shield_mat.set_shader_parameter("strength", pulse)
        shield_mi.scale = Vector3.ONE * (1.0 + 0.04 * sin(_t * 5.0))
        shield_rings[0].rotate_object_local(Vector3.UP, 0.05)
        shield_rings[1].rotate_object_local(Vector3.UP, -0.07)
        var k := 0.5 + 0.5 * sin(_t * 7.0)
        skin_mat.set_shader_parameter("albedo", body_color.lerp(Color(1.0, 0.92, 0.55), 0.15 + 0.2 * k))
        skin_mat.set_shader_parameter("rim_strength", 2.0)
    elif is_invulnerable():
        # 헬멧이 막은 직후 등의 짧은 무적: 살짝 깜빡임만
        var k := 0.5 + 0.5 * sin(_t * 30.0)
        skin_mat.set_shader_parameter("albedo", body_color.lerp(Color(1.0, 0.95, 0.7), 0.3 * k))
        skin_mat.set_shader_parameter("rim_strength", 1.0)
    else:
        skin_mat.set_shader_parameter("albedo", body_color)
        skin_mat.set_shader_parameter("rim_strength", 0.4)

func _animate(delta: float) -> void:
    var k := clampf(delta * 14.0, 0.0, 1.0)

    if dead:
        # 낙석에 깔려 납작해짐
        visual.scale = visual.scale.lerp(Vector3(1.45, 0.16, 1.45), clampf(delta * 20.0, 0.0, 1.0))
        visual.rotation = visual.rotation.lerp(Vector3.ZERO, k)
        return

    var hspeed := Vector2(velocity.x, velocity.z).length()
    var grounded := net_on_floor if remote else is_on_floor()
    var target_amp := 0.0
    if grounded and hspeed > 0.2 and not is_stunned():
        target_amp = clampf(hspeed / move_speed, 0.0, 1.4) * 0.6
        _anim_time += delta * (4.0 + hspeed * 1.3)
    _anim_amp = lerpf(_anim_amp, target_amp, clampf(delta * 10.0, 0.0, 1.0))
    _air_blend = lerpf(_air_blend, 0.0 if grounded else 1.0, clampf(delta * 8.0, 0.0, 1.0))
    var s := sin(_anim_time) * _anim_amp

    var la := -s
    var ra := s
    var arm_spread := _air_blend * 0.7
    var lean := 0.0
    var wobble := 0.0
    var crouch := absf(sin(_anim_time)) * 0.06 * _anim_amp
    var jitter := 0.0

    if is_stunned():
        la = 2.6 + sin(_t * 18.0) * 0.5
        ra = 2.6 - sin(_t * 18.0) * 0.5
        arm_spread = 0.5
        wobble = sin(_t * 22.0) * 0.3
        lean = 0.15
    elif push_anim > 0.0:
        la = 1.55
        ra = 1.55
        arm_spread = 0.0
        lean = -0.35
    elif charging:
        var c := get_charge_ratio()
        la = -0.6 - 0.6 * c
        ra = la
        lean = 0.12 + 0.1 * c
        crouch = -0.1 * c
        if c >= 0.999:
            jitter = sin(_t * 60.0) * 0.025

    left_leg.rotation.x = s + _air_blend * 0.5
    right_leg.rotation.x = -s - _air_blend * 0.2
    left_arm.rotation.x = lerpf(left_arm.rotation.x, la, k)
    right_arm.rotation.x = lerpf(right_arm.rotation.x, ra, k)
    left_arm.rotation.z = lerpf(left_arm.rotation.z, -arm_spread, k)
    right_arm.rotation.z = lerpf(right_arm.rotation.z, arm_spread, k)
    visual.rotation.x = lerpf(visual.rotation.x, lean, k)
    visual.rotation.z = lerpf(visual.rotation.z, wobble, k)
    visual.position = Vector3(jitter, crouch, 0.0)
    head.rotation.z = lerpf(head.rotation.z, sin(_anim_time * 0.5) * 0.08 * _anim_amp + wobble * 0.6, k)
