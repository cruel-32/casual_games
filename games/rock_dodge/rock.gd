class_name FallingRock
extends Node3D
## 낙석: 생성 순간의 바람을 반영한 '등속 직선' 궤적으로 떨어진다(사선 낙하).
## 궤적이 직선이므로 착지 지점을 정확히 예측해 바닥에 표시할 수 있다.

const WARN_SHADER := preload("res://games/rock_dodge/warning.gdshader")
const Toon := preload("res://scripts/world/toon.gd")

var game: Node
var radius := 1.0
var danger_radius := 1.35        # 캐릭터 중심이 이 원 안에 있으면 맞는다 (표시 원 크기)
var target_point := Vector3.ZERO # 착지 지점(지면)
var vel := Vector3.ZERO
var total_time := 2.0
var age := 0.0
var landed := false
var _whistled := false     # 떨어지는 휘파람 소리를 냈는지
var net_id := 0                  # 온라인: 서버가 붙인 번호
var t0 := 0.0                    # 온라인: 생성 시각(서버 시계) — 시각만 알면 위치를 계산할 수 있다
var blocked := false             # 헬멧에 막혀 부서짐

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


## 서버 시계 t 일 때 돌의 중심 위치
func position_at(t: float) -> Vector3:
    return _start + vel * clampf(t - t0, 0.0, total_time)


## 서버 시계 t 에 pos 에 서 있던 캐릭터가 이 돌에 맞았는가 (온라인 사람 플레이어 판정용)
func hits_at(t: float, pos: Vector3) -> bool:
    if blocked or t < t0 or t > t0 + total_time:
        return false
    return _hits_capsule(position_at(t), pos)


func _hits_capsule(p: Vector3, feet: Vector3) -> bool:
    var a := feet + Vector3(0, Fighter.RADIUS, 0)
    var b := feet + Vector3(0, Fighter.HEIGHT - Fighter.RADIUS, 0)
    var closest := Geometry3D.get_closest_point_to_segment(p, a, b)
    return p.distance_to(closest) < radius * 0.9 + Fighter.RADIUS


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
    if not _whistled and total_time - age <= 1.1:
        _whistled = true
        Sfx.play_at("rock_fall", target_point + Vector3.UP * 4.0, self, 0.0, 1.1 - clampf(radius - 1.0, 0.0, 1.5) * 0.15)
    var t := minf(age, total_time)
    var b := _rock.global_transform.basis.rotated(_spin_axis, _spin_speed * delta)
    _rock.global_transform = Transform3D(b, _start + vel * t)
    _marker_mat.set_shader_parameter("progress", clampf(age / total_time, 0.0, 1.0))

    _check_hits()
    if age >= total_time:
        _land()


## 이 PC가 직접 움직이는 캐릭터만 판정 (온라인 클라이언트는 판정하지 않음 — 서버가 결과를 보냄)
func _check_hits() -> void:
    if game == null or blocked:
        return
    if game.is_client():
        return
    var p := _rock.global_position
    for f: Fighter in game.fighters:
        if f.dead or f.remote:
            continue
        if _hits_capsule(p, f.global_position):
            var res := f.kill()
            if game.has_method(&"on_rock_hit"):
                game.on_rock_hit(self, f, res)
            if res == 2:
                shatter()       # 헬멧에 막혀 부서짐
                return


func _land() -> void:
    landed = true
    _marker.visible = false
    Sfx.play_at("rock_land", target_point, self, clampf(radius - 1.0, 0.0, 2.0) * 2.0, 1.15 - clampf(radius - 0.8, 0.0, 1.6) * 0.2)
    _spawn_dust()
    if game and game.has_method(&"on_rock_landed"):
        game.on_rock_landed(self)


func shatter() -> void:
    if blocked:
        return
    blocked = true
    landed = true
    _land_t = 1.0
    _marker.visible = false
    _rock.visible = false
    _spawn_dust(_rock.global_position)
    Sfx.play_at("rock_break", _rock.global_position, self)


static var _dust_mesh: SphereMesh


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
    if _dust_mesh == null:          # 먼지 메쉬·재질은 한 번만 만들어 모든 바위가 같이 쓴다
        _dust_mesh = SphereMesh.new()
        _dust_mesh.radius = 0.14
        _dust_mesh.height = 0.28
        _dust_mesh.radial_segments = 8
        _dust_mesh.rings = 4
        _dust_mesh.material = Toon.make(Color(0.78, 0.70, 0.55), {"rim_strength": 0.0, "shade_softness": 0.3})
    p.mesh = _dust_mesh
    p.top_level = true
    add_child(p)
    p.global_position = (target_point + Vector3(0, 0.2, 0)) if at == Vector3.INF else at
    p.emitting = true
