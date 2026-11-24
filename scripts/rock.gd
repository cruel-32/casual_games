class_name FallingRock
extends Node3D
## 낙석: 생성 순간의 바람을 반영한 '등속 직선' 궤적으로 떨어진다(사선 낙하).
## 궤적이 직선이므로 착지 지점을 정확히 예측해 바닥에 표시할 수 있다.

const WARN_SHADER := preload("res://shaders/warning.gdshader")
const Toon := preload("res://scripts/toon.gd")

var game: Node
var radius := 1.0
var danger_radius := 1.35        # 캐릭터 중심이 이 원 안에 있으면 맞는다 (표시 원 크기)
var target_point := Vector3.ZERO # 착지 지점(지면)
var vel := Vector3.ZERO
var total_time := 2.0
var age := 0.0
var landed := false

var _start := Vector3.ZERO
var _land_t := 0.0
var _spin_axis := Vector3.UP
var _spin_speed := 3.0
var _mesh: Mesh
var _mat: Material
var _ground_normal := Vector3.UP
var _rock: MeshInstance3D
var _marker: MeshInstance3D
var _marker_mat: ShaderMaterial


func setup(game_ref: Node, mesh: Mesh, mat: Material, r: float, target: Vector3,
        ground_normal: Vector3, wind: Vector2, fall_speed: float, height: float) -> void:
    game = game_ref
    _mesh = mesh
    _mat = mat
    radius = r
    danger_radius = r + Fighter.RADIUS
    target_point = target
    _ground_normal = ground_normal
    total_time = height / fall_speed
    vel = Vector3(wind.x, -fall_speed, wind.y)
    var impact_center := target + Vector3(0, r * 0.55, 0)
    _start = impact_center - vel * total_time
    _spin_axis = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
    _spin_speed = randf_range(2.0, 5.0)


func time_to_impact() -> float:
    return maxf(total_time - age, 0.0)


func _ready() -> void:
    global_position = target_point

    _rock = MeshInstance3D.new()
    _rock.mesh = _mesh
    _rock.material_override = _mat
    _rock.top_level = true
    _rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 그림자가 예측 표시와 헷갈리지 않게
    add_child(_rock)
    _rock.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), _start)

    _marker_mat = ShaderMaterial.new()
    _marker_mat.shader = WARN_SHADER
    var plane := PlaneMesh.new()
    plane.size = Vector2(danger_radius * 2.0, danger_radius * 2.0)
    _marker = MeshInstance3D.new()
    _marker.mesh = plane
    _marker.material_override = _marker_mat
    _marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_marker)
    # 지면 기울기에 맞춤
    var up := _ground_normal.normalized()
    _marker.transform = Transform3D(Basis(Quaternion(Vector3.UP, up)), up * 0.06)


func _physics_process(delta: float) -> void:
    if landed:
        _land_t += delta
        if _land_t > 0.7:
            _rock.global_position.y -= delta * 1.2
            _rock.scale = _rock.scale.lerp(Vector3.ZERO, clampf(delta * 2.0, 0.0, 1.0))
        if _land_t > 1.6:
            queue_free()
        return

    age += delta
    var t := minf(age, total_time)
    var b := _rock.global_transform.basis.rotated(_spin_axis, _spin_speed * delta)
    _rock.global_transform = Transform3D(b, _start + vel * t)
    _marker_mat.set_shader_parameter("progress", clampf(age / total_time, 0.0, 1.0))

    _check_hits()
    if age >= total_time:
        _land()


func _check_hits() -> void:
    var p := _rock.global_position
    for node in get_tree().get_nodes_in_group(&"fighters"):
        var f := node as Fighter
        if f.dead:
            continue
        var a := f.global_position + Vector3(0, Fighter.RADIUS, 0)
        var b := f.global_position + Vector3(0, Fighter.HEIGHT - Fighter.RADIUS, 0)
        var closest := Geometry3D.get_closest_point_to_segment(p, a, b)
        if p.distance_to(closest) < radius * 0.9 + Fighter.RADIUS:
            if f.kill() == 2:
                _shatter()       # 헬멧에 막혀 부서짐
                return


func _land() -> void:
    landed = true
    _marker.visible = false
    _spawn_dust()
    if game and game.has_method(&"on_rock_landed"):
        game.on_rock_landed(self)


func _shatter() -> void:
    landed = true
    _land_t = 1.0
    _marker.visible = false
    _rock.visible = false
    _spawn_dust(_rock.global_position)


func _spawn_dust(at: Vector3 = Vector3.INF) -> void:
    var p := CPUParticles3D.new()
    p.one_shot = true
    p.explosiveness = 0.95
    p.amount = 22
    p.lifetime = 0.8
    p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
    p.emission_sphere_radius = radius * 0.8
    p.direction = Vector3.UP
    p.spread = 75.0
    p.initial_velocity_min = 2.0
    p.initial_velocity_max = 5.0 + radius * 2.0
    p.gravity = Vector3(0, -9.0, 0)
    p.scale_amount_min = 0.6
    p.scale_amount_max = 1.4 + radius * 0.5
    var curve := Curve.new()
    curve.add_point(Vector2(0, 1))
    curve.add_point(Vector2(1, 0))
    p.scale_amount_curve = curve
    var m := SphereMesh.new()
    m.radius = 0.14
    m.height = 0.28
    m.radial_segments = 8
    m.rings = 4
    m.material = Toon.make(Color(0.78, 0.70, 0.55), {"rim_strength": 0.0, "shade_softness": 0.3})
    p.mesh = m
    p.top_level = true
    add_child(p)
    p.global_position = (target_point + Vector3(0, 0.2, 0)) if at == Vector3.INF else at
    p.emitting = true
