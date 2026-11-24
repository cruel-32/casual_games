class_name RockDodgeGame
extends PartyGame
## [게임 모듈] 3D 돌피하기 — 규칙
## - 사각형 아레나(투명 벽) 안에서 플레이어 + 봇 대결, 마지막 생존자 승리
## - 하늘에서 무작위 낙석. 풍향/풍속이 계속 바뀌고 낙석은 바람을 받아 사선으로 떨어진다
## - 시간이 갈수록 낙석 빈도·크기·속도·바람이 강해진다

const BOT_BRAIN := preload("res://games/rock_dodge/bot_brain.gd")
const WALL_SHADER := preload("res://shaders/arena_wall.gdshader")
const HUD_SCRIPT := preload("res://games/rock_dodge/hud.gd")
const Toon := preload("res://scripts/world/toon.gd")
const Procedural := preload("res://scripts/world/procedural.gd")

@export var bot_count := 5
@export var rock_height := 32.0
@export var difficulty_ramp_time := 90.0   # 이 시간(초)에 걸쳐 최고 난이도 도달
@export var max_wind_start := 3.0
@export var max_wind_end := 8.0
@export var target_player_ratio := 0.0     # 캐릭터 근처를 노리는 낙석 비율 (0 = 아레나 전체 균등 랜덤)
@export var last_two_rate_mult := 3.5       # 2명 남았을 때 낙석 빈도 배수 (전원 생존 시 1배)

@export_group("Items")
@export var item_interval_min := 2.0
@export var item_interval_max := 3.5
@export var max_items := 5
@export var item_lifetime := 15.0
## 등장 가중치: 헬멧, 깃털, 무거운 신발, 무적5, 무적10
@export var item_weights: Array[float] = [30.0, 25.0, 20.0, 17.0, 8.0]

const KILL_CREDIT_TIME := 3.0      # 민 뒤 이 시간 안에 낙석에 맞으면 민 사람 득점

const BOT_COLORS: Array[Color] = [
    Color(0.85, 0.22, 0.22), Color(0.22, 0.42, 0.90), Color(0.95, 0.68, 0.08),
    Color(0.25, 0.65, 0.22), Color(0.55, 0.28, 0.85), Color(0.95, 0.45, 0.10),
    Color(0.10, 0.65, 0.70), Color(0.88, 0.30, 0.60),
]

var rocks: Array = []
var elapsed := 0.0
var winner: Fighter = null
var human_death_time := -1.0
var last_intensify_time := -10.0     # 탈락자 발생 → "낙석 증가!" 알림용
var items: Array = []
var kill_feed: Array = []            # [{text, color, time}]
var _item_timer := 2.0

var wind := Vector2.ZERO
var _wind_target := Vector2.ZERO
var _wind_timer := 0.0
var _spawn_timer := 0.15
var _rock_meshes: Array[ArrayMesh] = []
var _rock_mats: Array[ShaderMaterial] = []
var _wind_fx: CPUParticles3D
var sweeper: Sweeper
## ※ 게임 동기화(4단계) 전까지: 온라인 방의 다른 참가자 자리는 그 닉네임을 단 봇이 대신 움직인다


func difficulty() -> float:
    return clampf(elapsed / difficulty_ramp_time, 0.0, 1.0)


## 탈락 압박: 전원 생존 0 → 2명 남음 1
func elimination_pressure() -> float:
    var total := fighters.size()
    if total <= 2:
        return 1.0
    var alive := alive_fighters().size()
    return clampf(float(total - alive) / float(total - 2), 0.0, 1.0)


func _ready() -> void:
    for i in 4:
        _rock_meshes.append(Procedural.make_rock_mesh(200 + i))
    _rock_mats.append(Toon.make(Color(0.42, 0.40, 0.42), {"shade_softness": 0.04, "rim_strength": 0.5}))
    _rock_mats.append(Toon.make(Color(0.50, 0.45, 0.40), {"shade_softness": 0.04, "rim_strength": 0.5}))

    _build_walls()
    _build_wind_fx()
    sweeper = Sweeper.new()
    sweeper.game = self
    sweeper.arena_length_hint = arena_half
    add_child(sweeper)
    sweeper.global_position = Vector3(0, terrain.get_height(0, 0), 0)
    _spawn_fighters()
    _pick_new_wind()
    wind = _wind_target

    var layer := CanvasLayer.new()
    add_child(layer)
    var hud: Control = HUD_SCRIPT.new()
    hud.game = self
    layer.add_child(hud)
    add_common_ui(layer)     # 터치 컨트롤·세로 화면 안내 (PartyGame)


# ================================================================ 구성
func _build_walls() -> void:
    var mat := ShaderMaterial.new()
    mat.shader = WALL_SHADER
    var length := arena_half * 2.0 + 0.5
    for i in 4:
        var along_x := i < 2
        var side := -1.0 if i % 2 == 0 else 1.0

        var body := StaticBody3D.new()
        body.name = "ArenaWall%d" % i
        body.collision_layer = 4      # 캐릭터만 막는 레이어 (카메라·지형과 무관)
        body.add_to_group(&"arena_wall")
        body.collision_mask = 0
        add_child(body)

        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        var mesh := BoxMesh.new()
        if along_x:
            body.position = Vector3(0, 0, side * arena_half)
            shape.size = Vector3(length, 16.0, 1.0)
            mesh.size = Vector3(length, 6.0, 0.02)
            col.position = Vector3(0, 6.0, side * 0.5)
        else:
            body.position = Vector3(side * arena_half, 0, 0)
            shape.size = Vector3(1.0, 16.0, length)
            mesh.size = Vector3(0.02, 6.0, length)
            col.position = Vector3(side * 0.5, 6.0, 0)
        col.shape = shape
        body.add_child(col)

        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = mat
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mi.position.y = 2.0       # 시각적 벽: y -1 ~ 5
        body.add_child(mi)


func _build_wind_fx() -> void:
    _wind_fx = CPUParticles3D.new()
    _wind_fx.amount = 90
    _wind_fx.lifetime = 1.6
    _wind_fx.preprocess = 1.6
    _wind_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    _wind_fx.emission_box_extents = Vector3(arena_half + 10.0, 2.5, arena_half + 10.0)
    _wind_fx.gravity = Vector3.ZERO
    _wind_fx.spread = 4.0
    _wind_fx.particle_flag_align_y = true
    _wind_fx.local_coords = false
    var grad := Gradient.new()
    grad.set_color(0, Color(1, 1, 1, 0))
    grad.set_color(1, Color(1, 1, 1, 0))
    grad.add_point(0.25, Color(1, 1, 1, 1))
    grad.add_point(0.75, Color(1, 1, 1, 1))
    _wind_fx.color_ramp = grad

    var m := BoxMesh.new()
    m.size = Vector3(0.025, 1.4, 0.025)
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.vertex_color_use_as_albedo = true
    mat.albedo_color = Color(1, 1, 1, 0.35)
    m.material = mat
    _wind_fx.mesh = m
    _wind_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_wind_fx)
    _wind_fx.global_position = Vector3(0, terrain.get_height(0, 0) + 3.0, 0)


func _spawn_fighters() -> void:
    # 이름 목록: 0번 = 나, 이후 = 다른 참가자 → 봇
    var names: Array[String] = ["나"]
    online_match = Net.match_config
    if is_online_match():
        var my_id := int(online_match.get("my_id", 0))
        for m in online_match.members:
            if int(m.id) == my_id:
                names[0] = String(m.nick)
            else:
                names.append(String(m.nick))
        var total_slots: int = int(online_match.max) if online_match.bot_fill else online_match.members.size()
        bot_count = maxi(total_slots - 1, 0)
    var total := bot_count + 1
    var bot_no := 0
    for i in total:
        var f := Fighter.new()
        f.game = self
        f.is_human = (i == 0)
        if f.is_human:
            f.display_name = names[0]
            f.body_color = Color(0.95, 0.95, 0.92)
        else:
            if i < names.size():
                f.display_name = names[i]
            else:
                bot_no += 1
                f.display_name = "Bot %d" % bot_no
            f.body_color = BOT_COLORS[(i - 1) % BOT_COLORS.size()]
        var a := PI * 0.5 + i * TAU / total
        var p := Vector3(cos(a), 0, sin(a)) * minf(8.0, arena_half - 2.0)
        f.position = Vector3(p.x, terrain.get_height(p.x, p.z) + 0.2, p.z)
        f.rotation.y = atan2(p.x, p.z)     # 중앙을 바라봄
        if not f.is_human:
            var brain := BOT_BRAIN.new()
            brain.game = self
            f.add_child(brain)
        add_child(f)
        f.died.connect(_on_fighter_died)
        fighters.append(f)
        if f.is_human:
            human = f


# ================================================================ 진행
func _physics_process(delta: float) -> void:
    state_time += delta
    _update_wind(delta)
    match state:
        State.COUNTDOWN:
            if state_time >= countdown_time:
                state = State.PLAYING
                state_time = 0.0
        State.PLAYING:
            elapsed += delta
            _update_spawning(delta)
            _update_items(delta)
            _update_bumps()
            _check_end()
        State.ENDED:
            pass
    rocks = rocks.filter(func(r): return is_instance_valid(r))


func _check_end() -> void:
    var min_alive := 1 if fighters.size() > 1 else 0
    var alive := alive_fighters()
    if alive.size() <= min_alive:
        state = State.ENDED
        state_time = 0.0
        winner = alive[0] if alive.size() == 1 else null


func _on_fighter_died(f: Fighter) -> void:
    if f == human:
        human_death_time = elapsed
    var now := Time.get_ticks_msec() * 0.001
    var a := f.last_attacker
    if a and a != f and now - f.last_attacker_time <= KILL_CREDIT_TIME:
        a.kills += 1
        var col := Color(1.0, 0.9, 0.35) if a == human else (Color(1.0, 0.5, 0.45) if f == human else Color.WHITE)
        _feed("%s → %s 낙석행!" % [a.display_name, f.display_name], col)
        popup_text(a.global_position + Vector3(0, 2.6, 0), "+1 킬", Color(1.0, 0.9, 0.35))
    else:
        _feed("%s 낙석" % f.display_name, Color(1.0, 0.5, 0.45) if f == human else Color(0.85, 0.85, 0.85))
    if state == State.PLAYING:
        last_intensify_time = elapsed


func on_rock_landed(rock: FallingRock) -> void:
    if human and not human.dead:
        var d := human.global_position.distance_to(rock.target_point)
        if d < 8.0:
            human.shake = maxf(human.shake, lerpf(0.5, 0.05, d / 8.0) * rock.radius)


func _update_bumps() -> void:
    var alive := alive_fighters()
    for i in alive.size():
        for j in range(i + 1, alive.size()):
            var a := alive[i]
            var b := alive[j]
            var to := b.global_position - a.global_position
            to.y = 0.0
            var dist := to.length()
            if dist < Fighter.RADIUS * 2.0 + 0.12 and dist > 0.001:
                var n := to / dist
                # 당구 연쇄: 밀려 날아가던 캐릭터가 부딪히면 상대도 날아감
                if _try_chain(a, b, n) or _try_chain(b, a, -n):
                    continue
                a.bump(-n * Fighter.BUMP_FORCE)
                b.bump(n * Fighter.BUMP_FORCE)


## mover가 날아가며 target에 부딪힘 (n: mover → target 방향)
func _try_chain(mover: Fighter, target: Fighter, n: Vector3) -> bool:
    if not mover.chain_armed or mover.chain_hits.has(target):
        return false
    var spd := mover.knock.length()
    if spd < Fighter.CHAIN_MIN_SPEED or mover.knock.dot(n) < spd * 0.3:
        return false
    mover.chain_hits.append(target)
    var credit: Fighter = mover.last_attacker if mover.last_attacker else mover
    var dir := (n + mover.knock.normalized()).normalized()
    if target.receive_push(dir * spd * 1.0 + Vector3.UP * 2.5, 0.7, credit):
        target.chain_hits.append(mover)
        popup_text((mover.global_position + target.global_position) * 0.5 + Vector3(0, 2.4, 0), "연쇄!", Color(0.6, 0.9, 1.0))
    mover.knock *= 0.4
    return true


# ================================================================ 아이템 / 연출
func _update_items(delta: float) -> void:
    items = items.filter(func(it): return is_instance_valid(it))
    _item_timer -= delta
    if _item_timer > 0.0 or items.size() >= max_items:
        return
    # 인원이 줄수록 아이템이 드물게 (2명 남으면 간격 2배)
    _item_timer = randf_range(item_interval_min, item_interval_max) * (1.0 + elimination_pressure())
    var lim := arena_half - 2.0
    var x := randf_range(-lim, lim)
    var z := randf_range(-lim, lim)
    var it := ItemPickup.new()
    it.setup(self, _roll_item_kind(), Vector3(x, terrain.get_height(x, z), z), item_lifetime)
    add_child(it)
    items.append(it)


func _roll_item_kind() -> int:
    var weights := item_weights.duplicate()
    if alive_fighters().size() <= 2:        # 1:1 막판엔 무적 아이템 없음
        weights[ItemPickup.Kind.SHIELD5] = 0.0
        weights[ItemPickup.Kind.SHIELD10] = 0.0
    var total := 0.0
    for w in weights:
        total += w
    var r := randf() * total
    for i in weights.size():
        r -= weights[i]
        if r <= 0.0:
            return i
    return 0


func on_item_picked(it: ItemPickup, f: Fighter) -> void:
    var text := "%s!" % ItemPickup.kind_name(it.kind)
    if it.kind == ItemPickup.Kind.HELMET:
        text = "헬멧 (%d/%d)" % [f.helmets, Fighter.MAX_HELMETS]
    popup_text(f.global_position + Vector3(0, 2.4, 0), text, ItemPickup.COLORS[it.kind].lightened(0.2))


func nearest_item(pos: Vector3, max_dist: float, f: Fighter) -> Node3D:
    var best: Node3D = null
    var best_d := max_dist
    for it in items:
        if not is_instance_valid(it):
            continue
        if it.kind == ItemPickup.Kind.HELMET and f.helmets >= Fighter.MAX_HELMETS:
            continue
        var d: float = pos.distance_to(it.global_position)
        if d < best_d:
            best_d = d
            best = it
    return best


func _feed(text: String, color: Color) -> void:
    kill_feed.append({"text": text, "color": color, "time": elapsed})
    if kill_feed.size() > 5:
        kill_feed.pop_front()


# ================================================================ 바람
func _pick_new_wind() -> void:
    var maxw := lerpf(max_wind_start, max_wind_end, difficulty())
    var ang := randf() * TAU
    var strength := randf_range(maxw * 0.25, maxw)
    if randf() < 0.15:
        strength = 0.3
    _wind_target = Vector2(cos(ang), sin(ang)) * strength
    _wind_timer = randf_range(5.0, 9.0)


func _update_wind(delta: float) -> void:
    _wind_timer -= delta
    if _wind_timer <= 0.0:
        _pick_new_wind()
    wind = wind.lerp(_wind_target, clampf(delta * 0.8, 0.0, 1.0))
    var spd := wind.length()

    if grass_material:
        var dir := wind / spd if spd > 0.05 else Vector2(1, 0)
        grass_material.set_shader_parameter("wind_direction", dir)
        grass_material.set_shader_parameter("wind_strength", 0.12 + spd * 0.07)

    if spd > 0.3:
        _wind_fx.direction = Vector3(wind.x, 0, wind.y) / spd
        _wind_fx.initial_velocity_min = spd * 2.2
        _wind_fx.initial_velocity_max = spd * 3.0
        _wind_fx.color = Color(1, 1, 1, clampf(spd / 6.0, 0.1, 1.0))
        _wind_fx.emitting = true
    else:
        _wind_fx.emitting = false


# ================================================================ 낙석
func _update_spawning(delta: float) -> void:
    _spawn_timer -= delta
    if _spawn_timer > 0.0:
        return
    var d := difficulty()
    # 최고 난이도 이후엔 서든데스: 30초마다 낙석 빈도가 계속 늘어남
    var overtime := maxf(elapsed - difficulty_ramp_time, 0.0) / 30.0
    # 인원이 줄수록 빈도 증가 (곡선: 초반 탈락은 완만, 막판일수록 급격)
    var p := elimination_pressure()
    var rate_mult := 1.0 + pow(p, 1.5) * (last_two_rate_mult - 1.0)
    _spawn_timer = maxf(lerpf(0.18, 0.09, d) * randf_range(0.7, 1.3) / ((1.0 + overtime) * rate_mult), 0.04)
    var count := 1
    if randf() < lerpf(0.15, 0.35, d) + overtime * 0.2 + p * 0.35:
        count = randi_range(2, 3 + int(p * 1.5))
    for i in count:
        _spawn_rock()


func _spawn_rock() -> void:
    var d := difficulty()
    var r := randf_range(0.5, lerpf(1.2, 1.9, d))
    var target := Vector2(randf_range(-arena_half, arena_half), randf_range(-arena_half, arena_half))
    var alive := alive_fighters()
    if randf() < target_player_ratio and alive.size() > 0:
        var f: Fighter = alive.pick_random()
        target = Vector2(f.global_position.x, f.global_position.z) + Vector2(randf_range(-2, 2), randf_range(-2, 2))
    var lim := arena_half - 0.3
    target = Vector2(clampf(target.x, -lim, lim), clampf(target.y, -lim, lim))

    var ground := Vector3(target.x, terrain.get_height(target.x, target.y), target.y)
    var rock := FallingRock.new()
    rock.setup(self, _rock_meshes.pick_random(), _rock_mats.pick_random(), r, ground,
            terrain.get_normal(target.x, target.y), wind, lerpf(14.0, 20.0, d), rock_height)
    add_child(rock)
    rocks.append(rock)
