extends CharacterBody3D
## 마네킹 캐릭터 + 3인칭 숄더뷰(TPS) 컨트롤러.
## 마우스 좌우 = 캐릭터 몸 회전, 마우스 상하 = 카메라 피치. 이동은 캐릭터가 바라보는 방향 기준(스트레이프).

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 6.5
@export var ground_accel := 14.0
@export var air_accel := 3.0
@export var mouse_sensitivity := 0.0025
@export var body_color := Color(0.78, 0.58, 0.44)
@export var joint_color := Color(0.30, 0.32, 0.40)

@export_group("Camera")
@export var camera_distance := 3.2
@export var shoulder_offset := 0.55
@export var camera_height := 1.55
@export var min_pitch_deg := -70.0
@export var max_pitch_deg := 55.0

const Toon := preload("res://scripts/toon.gd")
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var pitch_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D

var visual: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D

var spawn_point := Vector3.ZERO
var anim_time := 0.0
var anim_amp := 0.0
var air_blend := 0.0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0


func _ready() -> void:
    spawn_point = global_position
    floor_snap_length = 0.3
    _build_collision()
    _build_mannequin()
    _build_camera()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- 구성
func _build_collision() -> void:
    var col := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.35
    shape.height = 1.8
    col.shape = shape
    col.position.y = 0.9
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
    var skin := Toon.make(body_color, {"rim_strength": 0.4, "shade_softness": 0.05})
    var joint := Toon.make(joint_color, {"rim_strength": 0.5, "shade_softness": 0.05})

    visual = Node3D.new()
    visual.name = "Mannequin"
    add_child(visual)

    # 몸통 / 골반 / 목 / 머리 (원점 = 발바닥, 키 약 1.9m)
    _part(visual, _capsule(0.22, 0.70), Vector3(0, 1.25, 0), skin)
    _part(visual, _sphere(0.17), Vector3(0, 0.95, 0), joint)
    _part(visual, _capsule(0.06, 0.20), Vector3(0, 1.62, 0), joint)
    _part(visual, _sphere(0.16), Vector3(0, 1.78, 0), skin)
    # 바이저 (정면 = -Z 표시)
    var visor := BoxMesh.new()
    visor.size = Vector3(0.22, 0.07, 0.06)
    _part(visual, visor, Vector3(0, 1.80, -0.14), joint)

    # 팔: 어깨 피벗에서 아래로 매달림
    left_arm = _pivot(visual, Vector3(-0.31, 1.50, 0))
    right_arm = _pivot(visual, Vector3(0.31, 1.50, 0))
    for arm in [left_arm, right_arm]:
        _part(arm, _sphere(0.085), Vector3.ZERO, joint)
        _part(arm, _capsule(0.07, 0.62), Vector3(0, -0.32, 0), skin)

    # 다리: 엉덩이 피벗에서 아래로
    left_leg = _pivot(visual, Vector3(-0.12, 0.88, 0))
    right_leg = _pivot(visual, Vector3(0.12, 0.88, 0))
    for leg in [left_leg, right_leg]:
        _part(leg, _capsule(0.095, 0.88), Vector3(0, -0.44, 0), skin)


func _build_camera() -> void:
    pitch_pivot = _pivot(self, Vector3(0, camera_height, 0))
    pitch_pivot.name = "PitchPivot"

    spring_arm = SpringArm3D.new()
    spring_arm.position = Vector3(shoulder_offset, 0, 0)
    spring_arm.spring_length = camera_distance
    spring_arm.margin = 0.15
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


# ---------------------------------------------------------------- 입력
func _unhandled_input(event: InputEvent) -> void:
    var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

    if event is InputEventMouseMotion and captured:
        var motion := event as InputEventMouseMotion
        rotate_y(-motion.relative.x * mouse_sensitivity)
        pitch_pivot.rotation.x = clampf(
            pitch_pivot.rotation.x - motion.relative.y * mouse_sensitivity,
            deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

    elif event is InputEventMouseButton and event.pressed:
        var mb := event as InputEventMouseButton
        if not captured and mb.button_index == MOUSE_BUTTON_LEFT:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            spring_arm.spring_length = clampf(spring_arm.spring_length - 0.4, 1.5, 8.0)
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            spring_arm.spring_length = clampf(spring_arm.spring_length + 0.4, 1.5, 8.0)

    elif event.is_action_pressed(&"ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- 물리
func _physics_process(delta: float) -> void:
    var on_floor := is_on_floor()

    if on_floor:
        coyote_timer = COYOTE_TIME
    else:
        coyote_timer -= delta
        velocity.y -= gravity * delta

    if Input.is_action_just_pressed(&"jump"):
        jump_buffer_timer = JUMP_BUFFER
    else:
        jump_buffer_timer -= delta

    if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
        velocity.y = jump_velocity
        jump_buffer_timer = 0.0
        coyote_timer = 0.0

    var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
    var dir := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
    dir.y = 0.0
    dir = dir.normalized()

    var speed := sprint_speed if Input.is_action_pressed(&"sprint") else walk_speed
    var accel := ground_accel if on_floor else air_accel
    var t := clampf(accel * delta, 0.0, 1.0)
    velocity.x = lerpf(velocity.x, dir.x * speed, t)
    velocity.z = lerpf(velocity.z, dir.z * speed, t)

    move_and_slide()

    # 풀 셰이더가 플레이어 주변 풀을 눕히도록 위치 전달
    RenderingServer.global_shader_parameter_set(&"player_position", global_position)

    if global_position.y < -20.0:
        global_position = spawn_point
        velocity = Vector3.ZERO

    _animate(delta)


# ---------------------------------------------------------------- 절차적 애니메이션
func _animate(delta: float) -> void:
    var hspeed := Vector2(velocity.x, velocity.z).length()
    var grounded := is_on_floor()

    var target_amp := 0.0
    if grounded and hspeed > 0.2:
        target_amp = clampf(hspeed / walk_speed, 0.0, 1.4) * 0.6
        anim_time += delta * (4.0 + hspeed * 1.3)
    anim_amp = lerpf(anim_amp, target_amp, clampf(delta * 10.0, 0.0, 1.0))
    air_blend = lerpf(air_blend, 0.0 if grounded else 1.0, clampf(delta * 8.0, 0.0, 1.0))

    var s := sin(anim_time) * anim_amp
    left_leg.rotation.x = s + air_blend * 0.5
    right_leg.rotation.x = -s - air_blend * 0.2
    left_arm.rotation.x = -s
    right_arm.rotation.x = s
    left_arm.rotation.z = -air_blend * 0.7
    right_arm.rotation.z = air_blend * 0.7

    visual.position.y = absf(sin(anim_time)) * 0.06 * anim_amp
