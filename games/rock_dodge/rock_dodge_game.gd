class_name RockDodgeGame
extends PartyGame
## [게임 모듈] 3D 돌피하기 — 규칙
## - 사각형 아레나(투명 벽) 안에서 플레이어 + 봇 대결, 마지막 생존자 승리
## - 하늘에서 무작위 낙석. 풍향/풍속이 계속 바뀌고 낙석은 바람을 받아 사선으로 떨어진다
## - 시간이 갈수록 낙석 빈도·크기·속도·바람이 강해진다
##
## 온라인 (PartyGame.net_role)
## - 서버: 낙석·아이템·바람 생성, 봇, 낙석 사망·아이템 획득·승패 판정, 밀치기 검증 → 결과를 방송
## - 클라이언트: 내 캐릭터만 직접 움직이고(즉시 반응) 상태를 초당 30회 서버로 보냄.
##   다른 캐릭터는 서버가 초당 20회 보내는 상태를 약 0.1초 늦춰 부드럽게 보간해서 그린다
## - 낙석은 "생성 시각(서버 시계)"과 궤적이 같으므로 모든 PC에서 같은 순간 같은 위치에 떨어진다.
##   서버는 내가 보낸 "그 시각의 내 위치"로 맞았는지 판정 → 내 화면에서 피했으면 피한 것
## - 밀치기: 내 화면에서 맞힌 걸 서버에 알리고, 서버가 최근 위치 기록으로 검증해 상대에게 넉백 전달
## - 회전 기둥: 경과 시간으로 각도가 정해짐 → 각자 자기 캐릭터를 자기 PC에서 판정

const BOT_BRAIN := preload("res://games/rock_dodge/bot_brain.gd")
const WALL_SHADER := preload("res://shaders/arena_wall.gdshader")
const HUD_SCRIPT := preload("res://games/rock_dodge/hud.gd")
const Toon := preload("res://scripts/world/toon.gd")
const Procedural := preload("res://scripts/world/procedural.gd")
const Sync := preload("res://scripts/core/fighter_sync.gd")

const SNAPSHOT_HZ := 20.0       # 서버 → 클라이언트 상태 전송 빈도
const SEND_HZ := 30.0           # 클라이언트 → 서버 내 상태 전송 빈도
const LOAD_WAIT_MAX := 10.0     # 서버: 모두 로딩될 때까지 최대 대기
const HISTORY_SEC := 1.0        # 서버: 판정 검증용 위치 기록 길이
const PUSH_REWIND_MAX := 0.6    # 서버: 이보다 오래된 시점의 밀치기는 인정하지 않음

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

# 온라인
var play_start_t := -1.0             # 경기(PLAYING) 시작 시각 (서버 시계)
var _slot_of_peer := {}              # 서버: peer_id -> slot
var _loaded := {}                    # 서버: 로딩 끝난 peer
var _wait_time := 0.0
var _snap_timer := 0.0
var _send_timer := 0.0
var _next_rock_id := 1
var _next_item_id := 1
var _rocks_by_id := {}
var _items_by_id := {}


func difficulty() -> float:
    return clampf(elapsed / difficulty_ramp_time, 0.0, 1.0)


## 탈락 압박: 전원 생존 0 → 2명 남음 1
func elimination_pressure() -> float:
    var total := fighters.size()
    if total <= 2:
        return 0.0          # 처음부터 1:1 이면 탈락 압박 없음 (시작부터 최고 빈도가 되지 않게)
    var alive := alive_fighters().size()
    return clampf(float(total - alive) / float(total - 2), 0.0, 1.0)


func _ready() -> void:
    if is_server():
        countdown_time = 3.0
    for i in 4:
        _rock_meshes.append(Procedural.make_rock_mesh(200 + i))
    _rock_mats.append(Toon.make(Color(0.42, 0.40, 0.42), {"shade_softness": 0.04, "rim_strength": 0.5}))
    _rock_mats.append(Toon.make(Color(0.50, 0.45, 0.40), {"shade_softness": 0.04, "rim_strength": 0.5}))

    _build_walls()
    if not is_server():
        _build_wind_fx()
    sweeper = Sweeper.new()
    sweeper.game = self
    sweeper.arena_length_hint = arena_half
    add_child(sweeper)
    sweeper.global_position = Vector3(0, terrain.get_height(0, 0), 0)
    _spawn_fighters()
    if not is_client():
        _pick_new_wind()
        wind = _wind_target
    if is_server():
        return                  # 서버: 화면 없음

    if is_client():
        Net.game_message.connect(on_server_message)
        Net.disconnected.connect(_on_net_disconnected)
        send_to_server(["loaded"])

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
    # 참가자 목록 (모든 PC에서 같은 순서 = 같은 slot 번호·시작 위치)
    var entries: Array = []          # [{peer, name}]  peer 0 = 봇(또는 오프라인의 나)
    if is_online_match():
        for m in online_match.members:
            entries.append({"peer": int(m.id), "name": String(m.nick)})
        var total_slots: int = int(online_match.max) if online_match.bot_fill else online_match.members.size()
        for b in range(maxi(total_slots - entries.size(), 0)):
            entries.append({"peer": 0, "name": "Bot %d" % (b + 1)})
    else:
        entries.append({"peer": 0, "name": "나"})
        for b in bot_count:
            entries.append({"peer": 0, "name": "Bot %d" % (b + 1)})
    var my_id := int(online_match.get("my_id", 0))

    var total := entries.size()
    for i in total:
        var e: Dictionary = entries[i]
        var f := Fighter.new()
        f.game = self
        f.slot = i
        f.peer_id = e.peer
        f.display_name = e.name
        match net_role:
            NetRole.OFFLINE:
                f.is_human = (i == 0)
            NetRole.CLIENT:
                f.is_human = (e.peer == my_id)
                f.remote = not f.is_human                # 봇 포함 남은 서버가 보낸 대로
            NetRole.SERVER:
                f.remote = e.peer != 0                   # 사람은 각자 PC에서 움직임
                if e.peer != 0:
                    _slot_of_peer[e.peer] = i
        f.body_color = Color(0.95, 0.95, 0.92) if f.is_human else BOT_COLORS[i % BOT_COLORS.size()]
        var a := PI * 0.5 + i * TAU / total
        var p := Vector3(cos(a), 0, sin(a)) * minf(8.0, arena_half - 2.0)
        f.position = Vector3(p.x, terrain.get_height(p.x, p.z) + 0.2, p.z)
        f.rotation.y = atan2(p.x, p.z)     # 중앙을 바라봄
        if not f.is_human and not f.remote:
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
    match net_role:
        NetRole.SERVER:
            _server_tick(delta)
            return
        NetRole.CLIENT:
            _client_tick(delta)
            return
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
        if is_server():
            broadcast(["end", winner.slot if winner else -1, elapsed])
            print("[server] 경기 종료 #%d 우승 %s" % [room_id(), winner.display_name if winner else "-"])


func _on_fighter_died(f: Fighter) -> void:
    if f == human:
        human_death_time = elapsed
    var now := Time.get_ticks_msec() * 0.001
    var a := f.last_attacker
    var credited := a != null and a != f and now - f.last_attacker_time <= KILL_CREDIT_TIME
    if is_server():
        broadcast(["died", f.slot, a.slot if credited else -1, f.global_position])
    if credited:
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
            if a.remote and b.remote:
                continue          # 서버: 두 사람끼리는 각자 PC에서 처리
            var to := b.global_position - a.global_position
            to.y = 0.0
            var dist := to.length()
            if dist < Fighter.RADIUS * 2.0 + 0.12 and dist > 0.001:
                var n := to / dist
                # 당구 연쇄: 밀려 날아가던 캐릭터가 부딪히면 상대도 날아감
                if _try_chain(a, b, n) or _try_chain(b, a, -n):
                    continue
                if not a.remote:
                    a.bump(-n * Fighter.BUMP_FORCE)
                if not b.remote:
                    b.bump(n * Fighter.BUMP_FORCE)


## mover가 날아가며 target에 부딪힘 (n: mover → target 방향)
func _try_chain(mover: Fighter, target: Fighter, n: Vector3) -> bool:
    if mover.remote or not mover.chain_armed or mover.chain_hits.has(target):
        return false
    var spd := mover.knock.length()
    if spd < Fighter.CHAIN_MIN_SPEED or mover.knock.dot(n) < spd * 0.3:
        return false
    mover.chain_hits.append(target)
    var credit: Fighter = mover.last_attacker if mover.last_attacker else mover
    var dir := (n + mover.knock.normalized()).normalized()
    if _apply_push(target, dir * spd * 1.0 + Vector3.UP * 2.5, 0.7, credit):
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
    var kind := _roll_item_kind()
    it.setup(self, kind, Vector3(x, terrain.get_height(x, z), z), item_lifetime)
    if is_server():
        it.net_id = _next_item_id
        _next_item_id += 1
        _items_by_id[it.net_id] = it
        broadcast(["item", it.net_id, kind, x, z, net_now()])
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
    if is_server():
        _items_by_id.erase(it.net_id)
        broadcast(["pick", it.net_id, f.slot, it.kind])
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
    if is_server():
        broadcast(["wind", _wind_target.x, _wind_target.y])


func _update_wind(delta: float) -> void:
    if not is_client():                 # 클라이언트는 서버가 정한 바람을 받는다
        _wind_timer -= delta
        if _wind_timer <= 0.0:
            _pick_new_wind()
    wind = wind.lerp(_wind_target, clampf(delta * 0.8, 0.0, 1.0))
    if _wind_fx == null:
        return
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

    var mesh_i := randi() % _rock_meshes.size()
    var mat_i := randi() % _rock_mats.size()
    var speed := lerpf(14.0, 20.0, d)
    var rock := _make_rock(mesh_i, mat_i, r, target, wind, speed, net_now())
    if is_server():
        rock.net_id = _next_rock_id
        _next_rock_id += 1
        _rocks_by_id[rock.net_id] = rock
        broadcast(["rock", rock.net_id, rock.t0, mesh_i, mat_i, r, target.x, target.y, wind.x, wind.y, speed])


func _make_rock(mesh_i: int, mat_i: int, r: float, target: Vector2, w: Vector2, speed: float, t0: float) -> FallingRock:
    var ground := Vector3(target.x, terrain.get_height(target.x, target.y), target.y)
    var rock := FallingRock.new()
    rock.setup(self, _rock_meshes[mesh_i], _rock_mats[mat_i], r, ground,
            terrain.get_normal(target.x, target.y), w, speed, rock_height)
    rock.t0 = t0
    add_child(rock)
    rocks.append(rock)
    return rock


## 낙석이 이 PC가 판정한 캐릭터를 맞힘 (res: 1 사망, 2 헬멧이 막음)
func on_rock_hit(rock: FallingRock, f: Fighter, res: int) -> void:
    if is_server() and res == 2:
        broadcast(["helmet", rock.net_id, f.slot, f.helmets])


# ================================================================ 밀치기 전달 (온라인 경로)
## Fighter 가 밀치기를 맞혔을 때 호출. 예측 성공 여부를 돌려준다 (미는 쪽 반동 연출용)
func deliver_push(attacker: Fighter, target: Fighter, impulse: Vector3, stun: float) -> bool:
    if is_client():
        # 내 화면에서 맞힘 → 서버에 알림. 서버가 검증 후 상대에게 넉백을 전달한다
        if target.dead or target.is_invulnerable() or target.heavy_timer > 0.0:
            return false
        var ap := attacker.global_position
        var tp := target.global_position
        send_to_server(["push", target.slot, impulse, stun, ap, tp, _render_time(target)])
        _debug("push 보냄 → %s 거리 %.2f" % [target.display_name, ap.distance_to(tp)])
        return true
    return _apply_push(target, impulse, stun, attacker)


## 서버/오프라인: 밀치기 결과 적용. 대상이 다른 PC가 움직이는 사람이면 그 PC로 넉백을 보낸다
func _apply_push(target: Fighter, impulse: Vector3, stun: float, attacker: Fighter) -> bool:
    if not target.remote:
        return target.receive_push(impulse, stun, attacker)
    if target.dead or target.is_invulnerable() or target.heavy_timer > 0.0:
        return false
    if attacker and attacker != target:
        target.last_attacker = attacker
        target.last_attacker_time = Time.get_ticks_msec() * 0.001
    send_to_peer(target.peer_id, ["knock", impulse, stun, attacker.slot if attacker else -1])
    return true


# ================================================================ 서버
func _server_tick(delta: float) -> void:
    var now := net_now()
    _update_wind(delta)
    match state:
        State.COUNTDOWN:
            if play_start_t < 0.0:
                _wait_time += delta
                if _all_loaded() or _wait_time > LOAD_WAIT_MAX:
                    play_start_t = now + countdown_time
                    broadcast(["start", play_start_t, _wind_target.x, _wind_target.y])
            elif now >= play_start_t:
                state = State.PLAYING
                state_time = 0.0
        State.PLAYING:
            elapsed = now - play_start_t
            state_time += delta
            _update_spawning(delta)
            _update_items(delta)
            _update_bumps()
            _server_judge_humans()
            _check_end()
        State.ENDED:
            state_time += delta
    rocks = rocks.filter(func(r): return is_instance_valid(r))

    # 봇 위치 기록 (밀치기 검증용)
    for f in fighters:
        if not f.remote:
            _record_history(f, now, f.global_position)

    _snap_timer -= delta
    if _snap_timer <= 0.0:
        _snap_timer += 1.0 / SNAPSHOT_HZ
        var data := PackedFloat32Array()
        for f in fighters:
            # 사람: 마지막으로 받은 상태의 시각 / 봇: 지금
            var t: float = f.net_history[-1][0] if f.remote and not f.net_history.is_empty() else now
            Sync.append(data, f, t - now)
        broadcast(["snap", now, data], false)


func _all_loaded() -> bool:
    for m in online_match.members:
        var pid := int(m.id)
        if not _loaded.has(pid) and Net._peer_alive(pid):
            return false
    return true


func _record_history(f: Fighter, t: float, pos: Vector3) -> void:
    f.net_history.append([t, pos])
    while f.net_history.size() > 2 and float(f.net_history[0][0]) < t - HISTORY_SEC:
        f.net_history.pop_front()


## 사람 플레이어: 받은 상태들(그 시각의 위치)로 낙석 판정
func _server_judge_humans() -> void:
    for f in fighters:
        if not f.remote:
            continue
        if f.dead:
            f.net_pending.clear()
            continue
        for e in f.net_pending:
            if f.dead:
                break
            if int(e[4]) & Sync.F_INVULN or f.invuln_timer > 0.0:
                continue
            for r in rocks:
                if not is_instance_valid(r):
                    continue
                var rock := r as FallingRock
                if rock.hits_at(float(e[0]), e[1]):
                    var res := f.kill()
                    on_rock_hit(rock, f, res)
                    if res == 2:
                        rock.shatter()
                    break
        f.net_pending.clear()


func on_client_message(pid: int, msg: Array) -> void:
    if msg.is_empty():
        return
    var f: Fighter = fighters[_slot_of_peer[pid]] if _slot_of_peer.has(pid) else null
    match String(msg[0]):
        "loaded":
            _loaded[pid] = true
        "st":
            if f and not f.dead and msg.size() >= 3:
                _server_receive_state(f, float(msg[1]), msg[2])
        "push":
            if f and msg.size() >= 7:
                _server_receive_push(f, int(msg[1]), msg[2], float(msg[3]), msg[4], msg[5], float(msg[6]))
        "pop":
            if msg.size() >= 4:
                broadcast(["pop", String(msg[1]), msg[2], msg[3]], true, pid)


func _server_receive_state(f: Fighter, t: float, data: PackedFloat32Array) -> void:
    if data.size() < Sync.STRIDE:
        return
    var now := net_now()
    t = clampf(t, now - HISTORY_SEC, now + 0.05)
    var e := Sync.entry_at(data, 0, t)
    var pos: Vector3 = e[1]
    # 이동 속도 검사 (돌진·넉백을 감안한 넉넉한 상한) — 넘으면 무시
    if not f.net_history.is_empty():
        var last: Array = f.net_history[-1]
        var dt := maxf(t - float(last[0]), 0.016)
        if pos.distance_to(last[1]) > 40.0 * dt + 1.0:
            f.net_rejects += 1
            if f.net_rejects < 20:       # 계속 어긋나면(끊김 후 재개 등) 결국 받아들인다
                return
    f.net_rejects = 0
    f.global_position = pos
    f.rotation.y = e[2]
    f.velocity = e[3]
    Sync.apply_flags(f, int(e[4]), float(e[5]))
    _record_history(f, t, pos)
    f.net_pending.append([t, pos, e[2], e[3], e[4]])


func _server_receive_push(a: Fighter, target_slot: int, impulse: Vector3, stun: float,
        apos: Vector3, tpos: Vector3, tt: float) -> void:
    if a.dead or target_slot < 0 or target_slot >= fighters.size() or not is_playing():
        return
    var t := fighters[target_slot]
    if t == a or t.dead:
        return
    var now := net_now()
    # 1) 미는 사람이 실제로 그 근처에 있었나
    if apos.distance_to(a.global_position) > 3.0:
        _debug("push 거부: 미는 사람 위치 불일치 %.2f" % apos.distance_to(a.global_position))
        return
    # 2) 미는 사람 화면에서 본 상대 위치가 그 시각 서버 기록과 맞나 (지연 보정 — 되감기)
    if tt < now - PUSH_REWIND_MAX or not _near_history(t, tt, tpos, 1.5):
        _debug("push 거부: 상대 위치 기록 불일치 (%.0fms 전)" % ((now - tt) * 1000.0))
        return
    if apos.distance_to(tpos) > a.push_reach + 1.0:
        _debug("push 거부: 거리 %.2f" % apos.distance_to(tpos))
        return
    _debug("push 승인 %s → %s (%.0fms 전 위치 기준)" % [a.display_name, t.display_name, (now - tt) * 1000.0])
    # 3) 세기 상한 (풀차징 밀치기 수준)
    var h := Vector3(impulse.x, 0.0, impulse.z).limit_length(18.0)
    var imp := Vector3(h.x, clampf(impulse.y, 0.0, 6.0), h.z)
    _apply_push(t, imp, clampf(stun, 0.0, 1.9), a)


func _near_history(f: Fighter, t: float, pos: Vector3, tol: float) -> bool:
    if f.net_history.is_empty():
        return f.global_position.distance_to(pos) <= tol * 2.0
    for h in f.net_history:
        if absf(float(h[0]) - t) <= 0.2 and (h[1] as Vector3).distance_to(pos) <= tol:
            return true
    return false


## 서버: 경기 중 플레이어가 나가거나 방으로 돌아감 → 기권 처리
func on_player_left(pid: int) -> void:
    if not _slot_of_peer.has(pid):
        return
    var f := fighters[_slot_of_peer[pid]]
    if not f.dead and state != State.ENDED:
        f.last_attacker = null
        f.die()
        popup_text(f.global_position + Vector3(0, 2.4, 0), "나감", Color(0.8, 0.8, 0.8))


# ================================================================ 클라이언트
func _client_tick(delta: float) -> void:
    var now := net_now()
    _update_wind(delta)
    match state:
        State.COUNTDOWN:
            if play_start_t > 0.0:
                state_time = clampf(countdown_time - (play_start_t - now), 0.0, countdown_time)
                if now >= play_start_t:
                    state = State.PLAYING
                    state_time = 0.0
            else:
                state_time = 0.0          # 다른 플레이어 로딩 대기
        State.PLAYING:
            elapsed = maxf(now - play_start_t, 0.0)
            state_time += delta
            _client_bumps()
        State.ENDED:
            state_time += delta
    rocks = rocks.filter(func(r): return is_instance_valid(r))
    items = items.filter(func(it): return is_instance_valid(it))

    # 다른 캐릭터: 서버 상태를 조금 늦춰 보간
    for f in fighters:
        if f.remote and not f.dead:
            Sync.apply_interpolated(f, _render_time(f))

    # 내 상태 보내기
    _send_timer -= delta
    if _send_timer <= 0.0 and human and not human.dead:
        _send_timer += 1.0 / SEND_HZ
        _send_timer = maxf(_send_timer, 0.0)
        var data := PackedFloat32Array()
        Sync.append(data, human, 0.0)
        send_to_server(["st", now, data], false)


## 원격 캐릭터를 그릴 시점 = 지금 - (도착 지연 + 여유)
func _render_time(f: Fighter) -> float:
    return net_now() - clampf(f.net_lag + 0.05, 0.08, 0.4)


## 내 캐릭터와 남의 몸 충돌: 나만 튕긴다 (상대는 상대 PC/서버가 처리). 연쇄는 서버에 알림
func _client_bumps() -> void:
    if human == null or human.dead:
        return
    for o in fighters:
        if o == human or o.dead:
            continue
        var to := o.global_position - human.global_position
        to.y = 0.0
        var dist := to.length()
        if dist >= Fighter.RADIUS * 2.0 + 0.12 or dist <= 0.001:
            continue
        var n := to / dist
        if human.chain_armed and not human.chain_hits.has(o):
            var spd := human.knock.length()
            if spd >= Fighter.CHAIN_MIN_SPEED and human.knock.dot(n) >= spd * 0.3:
                human.chain_hits.append(o)
                var dir := (n + human.knock.normalized()).normalized()
                deliver_push(human, o, dir * spd + Vector3.UP * 2.5, 0.7)
                human.knock *= 0.4
                popup_text((human.global_position + o.global_position) * 0.5 + Vector3(0, 2.4, 0), "연쇄!", Color(0.6, 0.9, 1.0), true)
                continue
        human.bump(-n * Fighter.BUMP_FORCE)


func on_server_message(msg: Array) -> void:
    if msg.is_empty():
        return
    var now := net_now()
    match String(msg[0]):
        "start":
            play_start_t = float(msg[1])
            _wind_target = Vector2(float(msg[2]), float(msg[3]))
            wind = _wind_target
        "snap":
            var base_t := float(msg[1])
            var data: PackedFloat32Array = msg[2]
            for i in Sync.count(data):
                var slot := Sync.slot_at(data, i)
                if slot < 0 or slot >= fighters.size():
                    continue
                var f := fighters[slot]
                if not f.remote:
                    continue
                var e := Sync.entry_at(data, i, base_t)
                f.net_lag = lerpf(f.net_lag, now - float(e[0]), 0.1)
                Sync.push_entry(f, e)
        "wind":
            _wind_target = Vector2(float(msg[1]), float(msg[2]))
        "rock":
            var r := _make_rock(int(msg[3]), int(msg[4]), float(msg[5]), Vector2(float(msg[6]), float(msg[7])),
                    Vector2(float(msg[8]), float(msg[9])), float(msg[10]), float(msg[2]))
            r.net_id = int(msg[1])
            r.age = maxf(now - r.t0, 0.0)          # 늦게 받았으면 그만큼 진행된 위치부터
            _rocks_by_id[r.net_id] = r
        "helmet":
            var rock = _rocks_by_id.get(int(msg[1]))
            if is_instance_valid(rock):
                rock.shatter()
            var f := _fighter_at(int(msg[2]))
            if f:
                f.lose_helmet()
                f.helmets = int(msg[3])
        "died":
            var f := _fighter_at(int(msg[1]))
            if f and not f.dead:
                if f.remote and msg.size() >= 4:
                    f.global_position = msg[3]          # 서버가 판정한 그 자리에서 쓰러짐
                var killer := _fighter_at(int(msg[2]))
                f.last_attacker = killer
                f.last_attacker_time = Time.get_ticks_msec() * 0.001 if killer else -100.0
                f.die()
        "item":
            var it := ItemPickup.new()
            it.setup(self, int(msg[2]), Vector3(float(msg[3]), terrain.get_height(float(msg[3]), float(msg[4])), float(msg[4])),
                    item_lifetime, maxf(now - float(msg[5]), 0.0))
            it.net_id = int(msg[1])
            add_child(it)
            items.append(it)
            _items_by_id[it.net_id] = it
        "pick":
            var it = _items_by_id.get(int(msg[1]))
            _items_by_id.erase(int(msg[1]))
            if is_instance_valid(it):
                it.queue_free()
            var f := _fighter_at(int(msg[2]))
            if f:
                ItemPickup.apply_to(f, int(msg[3]))
        "knock":
            if human and not human.dead:
                human.receive_push(msg[1], float(msg[2]), _fighter_at(int(msg[3])))
        "pop":
            popup_text(msg[2], String(msg[1]), msg[3])
        "end":
            state = State.ENDED
            state_time = 0.0
            winner = _fighter_at(int(msg[1]))
            elapsed = float(msg[2])


func _fighter_at(slot: int) -> Fighter:
    return fighters[slot] if slot >= 0 and slot < fighters.size() else null


func _on_net_disconnected() -> void:
    _feed("서버와 연결이 끊어졌습니다", Color(1.0, 0.5, 0.45))
    get_tree().create_timer(2.0).timeout.connect(func():
        if is_inside_tree():
            leave_to_menu())


func _exit_tree() -> void:
    if Net.game_message.is_connected(on_server_message):
        Net.game_message.disconnect(on_server_message)
    if Net.disconnected.is_connected(_on_net_disconnected):
        Net.disconnected.disconnect(_on_net_disconnected)


static var _debug_on := OS.get_environment("SPW_DEBUG") != ""
func _debug(text: String) -> void:
    if _debug_on:
        print("[server:debug] ", text)
