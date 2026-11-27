extends PartyGame
## [게임 모듈] 무궁화 꽃이 피었습니다
## - 긴 운동장 끝에 커다란 술래(가면 쓴 진행자)가 서 있다. 술래가 뒤돌아 "무궁화 꽃이 피었습니다"를 외치는 동안만 달릴 수 있다
## - 외침이 끝나고 술래가 돌아보면(빨간불) 멈춰야 한다. 돌아본 뒤 GRACE 초가 지나서도 움직이면 탈락
##   (밀려서 움직여도 탈락, 빨간불에 밀치기·차징해도 탈락 → 초록불 끝에 남을 밀어 빨간불까지 미끄러지게 하는 수싸움)
## - 결승선을 넘으면 통과 (먼저 넘을수록 높은 순위). 제한 시간이 끝날 때 못 넘은 사람은 탈락
## - 외침 빠르기는 매번 다름 (고르게 / 앞은 느리고 끝은 빠르게 / 중간에 뜸 들이기)
##
## 온라인 (돌피하기와 같은 구조)
## - 서버: 외침 주기를 정해 알림(["cycle", …] — 서버 시계 기준 시각), 봇, 탈락·통과·승패 판정
## - 클라이언트: 내 캐릭터만 직접 움직이고 상태를 초당 30회 보냄. 서버는 "그 시각의 내 위치"로 판정
##   → 빨간불 시각은 모두 서버 시계로 같으므로, 내 화면에서 제때 멈췄으면 멈춘 것 (지연에 따른 억울한 탈락 없음)
## - 밀치기: 돌피하기와 같이 내 화면에서 맞힌 걸 서버가 최근 위치 기록으로 검증해 상대에게 넉백 전달

const BOT_BRAIN := preload("res://games/mugunghwa/bot_brain.gd")
const HUD_SCRIPT := preload("res://games/mugunghwa/hud.gd")
const WALL_SHADER := preload("res://shaders/arena_wall.gdshader")
const Toon := preload("res://scripts/world/toon.gd")
const Sync := preload("res://scripts/core/fighter_sync.gd")
const Teams := preload("res://scripts/core/teams.gd")
const MaskedHost := preload("res://scripts/world/masked_host.gd")
const CHANT_SND := preload("res://audio/mugunghwa/chant.wav")
const TURN_SND := preload("res://audio/drum/don.wav")

# 운동장 (arena_half 32 — module.gd). 출발선은 +z 쪽, 결승선·술래는 -z 쪽. 길이 50m
const START_Z := 27.0
const FINISH_Z := -23.0
const HOST_Z := -28.0
const BACK_Z := -30.5            ## 술래 뒤 벽
const FRONT_Z := 30.5            ## 출발선 뒤 벽
const WIDTH_PER_PLAYER := 2.5    ## 운동장 폭 = 인원 × 2.5m (최소 10m, 최대 30m)

# 규칙
const TIME_LIMIT := 50.0         ## 경기 제한 시간 (초)
const FIRST_WAIT := 0.0          ## 시작하자마자 첫 외침 (그 전엔 카운트다운이라 못 움직임)
const GRACE := 0.2               ## 돌아본 뒤 멈출 여유 (이 시간 뒤의 위치가 기준)
const MOVE_TOL := 0.2            ## 기준 위치에서 이만큼(m) 넘게 움직이면 탈락
const JUMP_TOL := 0.35           ## 높이 차 (점프)
const GREEN_MIN := 1.3           ## 외침 길이 (초) — 시간이 갈수록 짧은 외침이 잦아짐 (뜸 들이는 스타일은 더 김)
const GREEN_MAX := 3.6
const RED_MIN := 1.6             ## 빨간불 (다시 외치기까지) — 가끔 아주 길게 뜸 들임 (RED_LONG)
const RED_MAX := 3.2
const RED_LONG := Vector2(4.0, 5.5)
const TURN_TIME := 0.25          ## '다'에서 돌아보기 시작 → 빨간불까지 (화면 연출)

## 외침 10음절과 높낮이 (반음, C5 기준 — chant.wav)
const SYLLABLES := ["무", "궁", "화", "꽃", "이", "피", "었", "습", "니", "다"]
const CHANT_PITCH := [7, 7, 4, 7, 7, 9, 7, 4, 2, 0]
## 외침 스타일: [첫 소리 전 침묵, 음절 10개의 길이 비율] + 최소 외침 길이
##   침묵(첫 칸)은 술래가 이미 뒤돌았지만 아직 말을 안 하는 때 — 초록불이라 움직여도 됨
const STYLES := [
    {"w": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], "min": 0.0, "name": "고르게"},
    {"w": [0, 1.6, 1.6, 1.6, 1.6, 1.6, 0.45, 0.45, 0.45, 0.45, 0.6], "min": 2.0, "name": "끝을 몰아치기"},
    {"w": [0, 0.7, 0.7, 2.6, 0.7, 0.7, 0.6, 0.6, 0.6, 0.6, 0.7], "min": 2.4, "name": "'화'에서 뜸"},
    {"w": [0, 0.55, 0.55, 0.55, 0.55, 0.55, 1.4, 1.4, 1.4, 1.4, 1.2], "min": 2.0, "name": "끝을 늘이기"},
    {"w": [0, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 3.2, 0.6], "min": 2.8, "name": "'니'에서 뜸"},
    {"w": [2.2, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.6], "min": 2.8, "name": "한참 침묵 뒤 빠르게"},
    {"w": [0, 0.6, 0.6, 0.6, 2.0, 0.6, 0.6, 0.6, 0.6, 2.0, 0.6], "min": 3.0, "name": "두 번 뜸"},
    {"w": [0, 2.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6], "min": 2.4, "name": "무~ 길게"},
    {"w": [0.8, 1.2, 1.2, 1.2, 0.5, 0.5, 0.5, 0.5, 0.5, 2.4, 0.5], "min": 3.0, "name": "침묵·느리게·빠르게·뜸"},
]

const SNAPSHOT_HZ := 20.0
const SEND_HZ := 30.0
const LOAD_WAIT_MAX := 10.0
const HISTORY_SEC := 1.0
const PUSH_REWIND_MAX := 0.6

@export var bot_count := 7
var no_out := false               ## 개발용 (사진 찍기): 탈락 판정 끄기

var teams := 0
var half_w := 11.0                ## 운동장 반폭 (x) — 인원 × WIDTH_PER_PLAYER / 2
var play_start_t := -1.0          ## 경기 시작 (서버 시계)
var elapsed := 0.0
## 외침 주기: {idx, t (초록불 시작, 서버 시계), green (외침 길이), red (빨간불 길이), style}
var cycle := {}
var finished := {}                ## slot -> [순서(1~), 걸린 시간]
var out_info := {}                ## slot -> [이유, 탈락 시각, 그때 z]
var feed: Array = []              ## [{text, color, time}]
var winner_text := ""
var human_result := ""            ## 내 결과 문구 (HUD)

# 서버·오프라인
var _ref := {}                    ## slot -> 이번 빨간불 기준 위치 (Vector3) — 판정 중
var _next_cycle_idx := 0
var _rng := RandomNumberGenerator.new()
var _ended := false
var _slot_of_peer := {}
var _loaded := {}
var _wait_time := 0.0
var _snap_timer := 0.0
var _send_timer := 0.0

# 화면
var _host: Node3D
var _guards: Array = []
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _sfx_pool: Array[AudioStreamPlayer] = []
var _chant_played := -1           ## 이번 주기에서 마지막으로 소리 낸 음절
var _chant_cycle := -1
var _turn_played := -1
var _host_seen_out := {}


func _ready() -> void:
    Sfx.bgm("")                   # 조용히 — 술래의 외침만 들리게
    _rng.randomize()
    if is_server():
        countdown_time = 3.0
    var entries := _entries()
    half_w = clampf(entries.size() * WIDTH_PER_PLAYER * 0.5, 5.0, 15.0)
    _build_field()
    _spawn_fighters(entries)
    if is_server():
        return
    _build_host()
    _build_audio()
    if is_client():
        Net.game_message.connect(on_server_message)
        Net.disconnected.connect(_on_net_disconnected)
        send_to_server(["loaded"])
    var layer := CanvasLayer.new()
    add_child(layer)
    var hud: Control = HUD_SCRIPT.new()
    hud.game = self
    layer.add_child(hud)
    add_common_ui(layer)


# ================================================================ 경기장
func _build_field() -> void:
    var h: float = terrain.get_height(0, 0)
    # 투명 벽 4개 (캐릭터만 막음) — 돌피하기 벽과 같은 셰이더
    var mat := ShaderMaterial.new()
    mat.shader = WALL_SHADER
    var len_z := FRONT_Z - BACK_Z
    var mid_z := (FRONT_Z + BACK_Z) * 0.5
    _wall(Vector3(-half_w, h, mid_z), Vector3(1.0, 16.0, len_z + 1.0), Vector3(0.02, 6.0, len_z), mat)
    _wall(Vector3(half_w, h, mid_z), Vector3(1.0, 16.0, len_z + 1.0), Vector3(0.02, 6.0, len_z), mat)
    _wall(Vector3(0, h, FRONT_Z), Vector3(half_w * 2.0 + 1.0, 16.0, 1.0), Vector3(half_w * 2.0, 6.0, 0.02), mat)
    _wall(Vector3(0, h, BACK_Z), Vector3(half_w * 2.0 + 1.0, 16.0, 1.0), Vector3(half_w * 2.0, 6.0, 0.02), mat)
    if is_server():
        return
    # 출발선(흰색)·결승선(빨강) 띠와 글자
    _stripe(START_Z, Color(0.98, 0.97, 0.92), h)
    _stripe(FINISH_Z, Color(0.92, 0.22, 0.26), h)
    for i in 2:
        var l := Label3D.new()
        l.text = "출발" if i == 0 else "결승선"
        l.font_size = 160
        l.outline_size = 24
        l.pixel_size = 0.01
        l.modulate = Color(0.98, 0.97, 0.92) if i == 0 else Color(1.0, 0.35, 0.35)
        l.rotation = Vector3(-PI * 0.5, 0, 0)
        add_child(l)
        l.global_position = Vector3(0, h + 0.03, (START_Z + 1.6) if i == 0 else (FINISH_Z - 1.4))


func _wall(pos: Vector3, shape_size: Vector3, mesh_size: Vector3, mat: Material) -> void:
    var body := StaticBody3D.new()
    body.collision_layer = 4
    body.collision_mask = 0
    body.add_to_group(&"arena_wall")
    add_child(body)
    body.global_position = pos
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = shape_size
    col.shape = shape
    col.position.y = 6.0
    body.add_child(col)
    if is_server():
        return
    var mi := MeshInstance3D.new()
    var m := BoxMesh.new()
    m.size = mesh_size
    mi.mesh = m
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.position.y = 2.0
    body.add_child(mi)


func _stripe(z: float, color: Color, h: float) -> void:
    var mi := MeshInstance3D.new()
    var m := BoxMesh.new()
    m.size = Vector3(half_w * 2.0, 0.04, 0.7)
    mi.mesh = m
    mi.material_override = Toon.make(color, {"rim_strength": 0.0})
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)
    mi.global_position = Vector3(0, h + 0.02, z)


## 술래(커다란 진행자) + 신호등 + 양옆 감시 진행자
func _build_host() -> void:
    var h: float = terrain.get_height(0, HOST_Z)
    var podium_mat := Toon.make(Color(0.16, 0.15, 0.2), {"rim_strength": 0.3})
    var podium := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = 2.0
    cyl.bottom_radius = 2.3
    cyl.height = 1.4
    podium.mesh = cyl
    podium.material_override = podium_mat
    add_child(podium)
    podium.global_position = Vector3(0, h + 0.7, HOST_Z)
    _host = MaskedHost.new()
    _host.variant = 1
    _host.scale = Vector3.ONE * 4.2              # 출발선(약 50m)에서도 잘 보이게
    _host.rotation.y = PI                # 처음엔 플레이어 쪽(+z)을 봄
    add_child(_host)
    _host.global_position = Vector3(0, h + 1.4, HOST_Z)
    # 신호등 (술래 옆 기둥 위 큰 공): 초록 = 달려요, 빨강 = 멈춰요
    var pole := MeshInstance3D.new()
    var pm := CylinderMesh.new()
    pm.top_radius = 0.12
    pm.bottom_radius = 0.14
    pm.height = 8.0
    pole.mesh = pm
    pole.material_override = podium_mat
    add_child(pole)
    pole.global_position = Vector3(6.0, h + 4.0, HOST_Z + 0.5)
    var lamp := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 1.2
    sm.height = 2.4
    lamp.mesh = sm
    _lamp_mat = StandardMaterial3D.new()
    _lamp_mat.emission_enabled = true
    _lamp_mat.emission_energy_multiplier = 1.2
    lamp.material_override = _lamp_mat
    lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(lamp)
    lamp.global_position = Vector3(6.0, h + 8.6, HOST_Z + 0.5)
    _lamp_light = OmniLight3D.new()
    _lamp_light.omni_range = 9.0
    _lamp_light.light_energy = 2.0
    add_child(_lamp_light)
    _lamp_light.global_position = lamp.global_position + Vector3(0, 0, 1.0)
    _set_lamp(false)
    # 감시 진행자: 운동장 양옆, 탈락자를 가리킴
    for i in 4:
        var side := -1.0 if i % 2 == 0 else 1.0
        var z := lerpf(START_Z - 8.0, FINISH_Z + 8.0, float(i / 2))
        var g: Node3D = MaskedHost.new()
        g.variant = 2 + i % 2
        g.scale = Vector3.ONE * 1.3
        g.rotation.y = side * PI * 0.5           # 운동장 가운데를 봄 (얼굴 = -Z)
        add_child(g)
        g.global_position = Vector3(side * (half_w + 1.6), terrain.get_height(side * (half_w + 1.6), z), z)
        _guards.append(g)


func _set_lamp(green: bool) -> void:
    if _lamp_mat == null:
        return
    var c := Color(0.25, 0.95, 0.4) if green else Color(1.0, 0.2, 0.2)
    _lamp_mat.albedo_color = c
    _lamp_mat.emission = c
    _lamp_light.light_color = c


func _build_audio() -> void:
    for i in 6:
        var p := AudioStreamPlayer.new()
        p.bus = "Sfx"
        add_child(p)
        _sfx_pool.append(p)


func _snd(stream: AudioStream, db: float = 0.0, pitch: float = 1.0) -> void:
    if _sfx_pool.is_empty():
        return
    var p: AudioStreamPlayer = _sfx_pool.pop_front()
    _sfx_pool.append(p)
    p.stream = stream
    p.volume_db = db
    p.pitch_scale = pitch
    p.play()


# ================================================================ 참가자
## 참가자 목록 (모든 PC에서 같은 순서 = 같은 slot·자리) [{peer, name, team}]
func _entries() -> Array:
    var entries: Array = []
    teams = int(online_match.get("teams", 0)) if is_online_match() else 0
    if is_online_match() and teams >= 2:
        var size := int(online_match.get("team_size", 0))
        var bot_n := 0
        for t in teams:
            var n := 0
            for m in online_match.members:
                if int(m.get("team", 0)) == t:
                    entries.append({"peer": int(m.id), "name": String(m.nick), "team": t})
                    n += 1
            while n < size:
                bot_n += 1
                entries.append({"peer": 0, "name": "Bot %d" % bot_n, "team": t})
                n += 1
    elif is_online_match():
        for m in online_match.members:
            entries.append({"peer": int(m.id), "name": String(m.nick)})
        var total_slots: int = int(online_match.max) if online_match.bot_fill else online_match.members.size()
        for b in range(maxi(total_slots - entries.size(), 0)):
            entries.append({"peer": 0, "name": "Bot %d" % (b + 1)})
    else:
        entries.append({"peer": 0, "name": "나"})
        for b in bot_count:
            entries.append({"peer": 0, "name": "Bot %d" % (b + 1)})
    return entries


func _spawn_fighters(entries: Array) -> void:
    var my_id := int(online_match.get("my_id", 0))
    var total := entries.size()
    var per_row := mini(total, 8)
    for i in total:
        var e: Dictionary = entries[i]
        var f := Fighter.new()
        f.game = self
        f.slot = i
        f.peer_id = e.peer
        f.display_name = e.name
        f.team = int(e.get("team", -1))
        match net_role:
            NetRole.OFFLINE:
                f.is_human = (i == 0)
            NetRole.CLIENT:
                f.is_human = (e.peer == my_id)
                f.remote = not f.is_human
            NetRole.SERVER:
                f.remote = e.peer != 0
                if e.peer != 0:
                    _slot_of_peer[e.peer] = i
        if f.team >= 0:
            f.body_color = Teams.color(f.team)
        else:
            f.body_color = Color(0.95, 0.95, 0.92) if f.is_human else Fighter.SLOT_COLORS[i % Fighter.SLOT_COLORS.size()]
        f.look = i
        # 출발선 뒤에 한두 줄로 (모든 PC에서 같은 자리)
        var row := i / per_row
        var col := i % per_row
        var x := lerpf(-half_w + 1.0, half_w - 1.0, (col + 0.5 + 0.5 * row) / float(per_row)) if per_row > 1 else 0.0
        var z := START_Z + 0.8 + row * 1.6
        f.position = Vector3(x, terrain.get_height(x, z) + 0.2, z)
        f.rotation.y = 0.0                    # 결승선(-z)을 바라봄
        if not f.is_human and not f.remote:
            var brain := BOT_BRAIN.new()
            brain.game = self
            f.add_child(brain)
        add_child(f)
        fighters.append(f)
        if f.is_human:
            human = f


func is_finished(f: Fighter) -> bool:
    return finished.has(f.slot)


## 아직 달리는 사람 (탈락도 통과도 안 함)
func runners() -> Array[Fighter]:
    var out: Array[Fighter] = []
    for f in fighters:
        if not f.dead and not finished.has(f.slot):
            out.append(f)
    return out


## 출발선에서 얼마나 왔나 (0~1)
func progress(f: Fighter) -> float:
    if finished.has(f.slot):
        return 1.0
    var z: float = float(out_info[f.slot][2]) if out_info.has(f.slot) else f.global_position.z
    return clampf((START_Z - z) / (START_Z - FINISH_Z), 0.0, 1.0)


# ================================================================ 외침 주기
## 지금 단계: ["wait" | "green" | "turn" | "red" | "over", 외침 진행(0~1), 말한 음절 수]
##   wait = 시작 전·첫 외침 전 (술래가 보지만 판정 없음), turn = '다'를 외치며 돌아보는 중 (아직 움직여도 됨)
func phase_at(t: float) -> Array:
    if play_start_t < 0.0 or t < play_start_t:
        return ["wait", 0.0, 0]
    if t - play_start_t >= TIME_LIMIT:
        return ["over", 1.0, 10]
    if cycle.is_empty() or t < float(cycle.t):
        return ["wait", 0.0, 0]
    var g := float(cycle.green)
    var dt := t - float(cycle.t)
    if dt < g:
        var marks := syllable_times(cycle)
        var said := 0
        for k in marks.size():
            if dt >= float(marks[k]):
                said = k + 1
        var turn_at: float = float(marks[9])
        if dt >= turn_at:
            return ["turn", dt / g, said]
        return ["green", dt / g, said]
    return ["red", 1.0, 10]


## 음절 시작 시각 (초록불 시작부터). 마지막 '다' 뒤 TURN_TIME 이 지나면 빨간불. 첫 칸은 첫 소리 전 침묵
static func syllable_times(c: Dictionary) -> Array:
    var w: Array = STYLES[int(c.style) % STYLES.size()].w
    var total := 0.0
    for x in w:
        total += float(x)
    var span := maxf(float(c.green) - TURN_TIME, 0.5)
    var out := []
    var acc := float(w[0])
    for k in range(1, w.size()):
        out.append(acc / total * span)
        acc += float(w[k])
    return out


func red_start() -> float:
    return float(cycle.t) + float(cycle.green) if not cycle.is_empty() else INF


func red_end() -> float:
    return red_start() + float(cycle.red) if not cycle.is_empty() else INF


## 서버·오프라인: 다음 외침 정하기 — 스타일마다 최소 길이가 있어 뜸이 너무 짧아지지 않게
func _new_cycle(t: float) -> void:
    var late := clampf(elapsed / TIME_LIMIT, 0.0, 1.0)
    var style := _rng.randi() % STYLES.size()
    if _next_cycle_idx == 0:
        style = 0                                                  # 첫 외침은 고르게 (규칙 익히기)
    var green := _rng.randf_range(GREEN_MIN, lerpf(GREEN_MAX, 2.6, late))
    if style == 0 and _rng.randf() < 0.2 + late * 0.2:
        green = _rng.randf_range(GREEN_MIN, GREEN_MIN + 0.5)     # 가끔 아주 빠른 외침
    green = maxf(green, float(STYLES[style].min) + _rng.randf_range(0.0, 0.8))
    var red := _rng.randf_range(RED_MIN, RED_MAX)
    if _rng.randf() < 0.18:
        red = _rng.randf_range(RED_LONG.x, RED_LONG.y)           # 다시 외치기까지 한참 뜸 들이기
    cycle = {"idx": _next_cycle_idx, "t": t, "green": green, "red": red, "style": style}
    _next_cycle_idx += 1
    _ref.clear()
    if is_server():
        broadcast(["cycle", cycle.idx, cycle.t, cycle.green, cycle.red, cycle.style])


# ================================================================ 판정 (서버·오프라인)
## 위치 하나로 판정: 통과·빨간불 움직임. t = 그 위치의 시각(서버 시계), flags = 차징·밀치기 중인지
func _judge_sample(f: Fighter, t: float, pos: Vector3, busy: bool) -> void:
    if f.dead or finished.has(f.slot) or _ended or play_start_t < 0.0 or t < play_start_t:
        return
    if pos.z <= FINISH_Z:
        _finish(f, t)
        return
    if cycle.is_empty() or play_start_t < 0.0 or t - play_start_t >= TIME_LIMIT or no_out:
        return
    var rs := red_start()
    if t < rs + GRACE or t >= red_end():
        return
    if not _ref.has(f.slot):
        _ref[f.slot] = pos
        return
    var ref: Vector3 = _ref[f.slot]
    var moved := Vector2(pos.x - ref.x, pos.z - ref.z).length()
    if moved > MOVE_TOL or absf(pos.y - ref.y) > JUMP_TOL or busy:
        _knock_out(f, "움직임" if not busy else "밀치기", pos)


func _finish(f: Fighter, t: float) -> void:
    var order := finished.size() + 1
    finished[f.slot] = [order, maxf(t - play_start_t, 0.0)]
    if is_server():
        broadcast(["fin", f.slot, order, finished[f.slot][1]])
    _on_finished(f)


func _knock_out(f: Fighter, reason: String, pos: Vector3) -> void:
    out_info[f.slot] = [reason, elapsed, pos.z]
    if is_server():
        broadcast(["out", f.slot, reason, pos])
    f.die()
    _on_out(f, reason)


func _on_finished(f: Fighter) -> void:
    var order := int(finished[f.slot][0])
    _feed("%s 통과! (%d등)" % [f.display_name, order], Color(0.55, 1.0, 0.6) if f != human else Color(1.0, 0.9, 0.35))
    if f == human:
        human_result = "통과! %d등" % order
    if not is_server():
        popup_text(f.global_position + Vector3(0, 2.4, 0), "통과!", Color(0.55, 1.0, 0.6))


func _on_out(f: Fighter, reason: String) -> void:
    var text := "%s 탈락 (%s)" % [f.display_name, reason]
    _feed(text, Color(1.0, 0.5, 0.45) if f == human else Color(0.9, 0.9, 0.9))
    if f == human:
        human_result = "탈락 — " + ({"움직임": "빨간불에 움직였어요", "밀치기": "빨간불에 밀치기를 했어요", "시간 초과": "시간 안에 못 들어왔어요"} as Dictionary).get(reason, reason)
    if not is_server():
        popup_text(f.global_position + Vector3(0, 2.4, 0), "탈락!", Color(1.0, 0.35, 0.3))


func _feed(text: String, color: Color) -> void:
    feed.append({"text": text, "color": color, "time": Time.get_ticks_msec() / 1000.0})
    if feed.size() > 5:
        feed.pop_front()


func _check_end() -> void:
    if _ended or play_start_t < 0.0:
        return
    var t := net_now()
    if t - play_start_t >= TIME_LIMIT:
        for f in runners():
            _knock_out(f, "시간 초과", f.global_position)
    if not runners().is_empty():
        return
    _ended = true
    state = State.ENDED
    state_time = 0.0
    var places := _placements()
    winner_text = _winner_text(places)
    if is_server():
        broadcast(["end", winner_text, elapsed])
        print("[server] 경기 종료 #%d %s" % [room_id(), winner_text])
        report_result(places)


func _winner_text(places: Array) -> String:
    if finished.is_empty():
        return "아무도 못 들어왔어요"
    var first: Dictionary = places[0]
    if teams >= 2:
        return "%s 승리!" % String(first.team)
    return "%s 1등!" % String(first.members[0].name)


## 순위: 통과한 순서 → 못 넘은 사람은 결승선에 가까이 간 순 (탈락한 자리 기준)
func _placements() -> Array:
    if teams >= 2:
        return _team_placements()
    var order := fighters.duplicate()
    order.sort_custom(func(a: Fighter, b: Fighter): return _score(a) > _score(b))
    var out := []
    var rank := 0
    var prev := INF
    for i in order.size():
        var f: Fighter = order[i]
        var s := _score(f)
        if i == 0 or absf(s - prev) > 0.002:
            rank = i + 1
        prev = s
        out.append({"rank": rank, "members": [participant(f)], "team": ""})
    return out


## 순위 점수: 통과 = 100 - 순서, 못 넘음 = 진행 정도 (0~1)
func _score(f: Fighter) -> float:
    if finished.has(f.slot):
        return 100.0 - float(finished[f.slot][0])
    return progress(f)


## 팀 순위: 통과한 팀원 수 → 가장 먼저 들어온 팀원 → 가장 멀리 간 팀원
func _team_placements() -> Array:
    var key := {}
    var members := {}
    for f in fighters:
        if not key.has(f.team):
            key[f.team] = [0, 0.0, 0.0]
            members[f.team] = []
        members[f.team].append(participant(f))
        var k: Array = key[f.team]
        if finished.has(f.slot):
            k[0] += 1
            k[1] = maxf(float(k[1]), 100.0 - float(finished[f.slot][0]))
        k[2] = maxf(float(k[2]), progress(f))
    var order: Array = key.keys()
    order.sort_custom(func(a, b): return _team_key(key[a]) > _team_key(key[b]))
    var out := []
    var rank := 0
    var prev := INF
    for i in order.size():
        var tm: int = order[i]
        var s := _team_key(key[tm])
        if i == 0 or absf(s - prev) > 0.002:
            rank = i + 1
        prev = s
        out.append({"rank": rank, "members": members[tm], "team": Teams.team_name(tm)})
    return out


static func _team_key(k: Array) -> float:
    return float(k[0]) * 1000.0 + float(k[1]) + float(k[2])


# ================================================================ 진행
func _physics_process(delta: float) -> void:
    match net_role:
        NetRole.SERVER:
            _server_tick(delta)
            return
        NetRole.CLIENT:
            _client_tick(delta)
            _keep_finished_behind_line()
            return
    # 오프라인
    state_time += delta
    var now := net_now()
    match state:
        State.COUNTDOWN:
            if state_time >= countdown_time:
                state = State.PLAYING
                state_time = 0.0
                play_start_t = now
                _new_cycle(now + FIRST_WAIT)
        State.PLAYING:
            elapsed = now - play_start_t
            _advance_cycle(now)
            for f in fighters:
                _judge_sample(f, now, f.global_position, _busy(f))
            _check_end()
    _keep_finished_behind_line()


func _advance_cycle(now: float) -> void:
    if not cycle.is_empty() and now >= red_end():
        _new_cycle(red_end())


func _busy(f: Fighter) -> bool:
    return f.charging or f.push_anim > 0.0 or f.dash_timer > 0.0


## 통과한 사람은 결승선 뒤에 머문다 (다시 들어와 남을 방해하지 못하게)
func _keep_finished_behind_line() -> void:
    for f in fighters:
        if f.remote or f.dead or not finished.has(f.slot):
            continue
        if f.global_position.z > FINISH_Z - 0.6:
            f.global_position.z = FINISH_Z - 0.6
            f.knock = Vector3.ZERO


func _process(_delta: float) -> void:
    if is_server() or _host == null:
        return
    var t := net_now()
    var ph := phase_at(t)
    var kind: String = ph[0]
    # 술래: 외치는 동안 뒤돌아(-z) 있다가 '다'에서 홱 돌아봄
    var facing_players := kind == "wait" or kind == "turn" or kind == "red" or kind == "over"
    _host.face(PI if facing_players else 0.0, 14.0 if facing_players else 6.0)
    _set_lamp(kind == "green")
    # 외침 소리: 음절마다 한 음
    if not cycle.is_empty() and state == State.PLAYING:
        var idx := int(cycle.idx)
        if idx != _chant_cycle:
            _chant_cycle = idx
            _chant_played = 0
        var said := int(ph[2]) if kind == "green" or kind == "turn" else (10 if kind == "red" else 0)
        while _chant_played < said and _chant_played < 10:
            _snd(CHANT_SND, -2.0 if _chant_played < 9 else 1.0, pow(2.0, float(CHANT_PITCH[_chant_played]) / 12.0))
            _chant_played += 1
        if kind == "turn" and _turn_played != idx:
            _turn_played = idx
            _snd(TURN_SND, -3.0, 0.7)            # 돌아보는 '쿵'
    # 탈락하면 감시 진행자가 가리킴
    for f in fighters:
        if f.dead and not _host_seen_out.has(f.slot):
            _host_seen_out[f.slot] = true
            var best: Node3D = null
            for g: Node3D in _guards:
                if best == null or g.global_position.distance_to(f.global_position) < best.global_position.distance_to(f.global_position):
                    best = g
            for g: Node3D in _guards:
                g.look_at_point(f.global_position)
                g.gesture("point" if g == best else "nod")
    if state == State.ENDED:
        for g: Node3D in _guards:
            if randf() < 0.01:
                g.gesture("clap")


# ================================================================ 밀치기 (돌피하기와 같은 방식)
func deliver_push(attacker: Fighter, target: Fighter, impulse: Vector3, stun: float) -> bool:
    if finished.has(target.slot) or finished.has(attacker.slot):
        return false
    if is_client():
        if target.dead or target.is_invulnerable():
            return false
        send_to_server(["push", target.slot, impulse, stun, attacker.global_position, target.global_position, _render_time(target)])
        return true
    return _apply_push(target, impulse, stun, attacker)


func _apply_push(target: Fighter, impulse: Vector3, stun: float, attacker: Fighter) -> bool:
    if not target.remote:
        return target.receive_push(impulse, stun, attacker)
    if target.dead or target.is_invulnerable():
        return false
    if attacker and attacker != target:
        target.last_attacker = attacker
        target.last_attacker_time = Time.get_ticks_msec() * 0.001
    send_to_peer(target.peer_id, ["knock", impulse, stun, attacker.slot if attacker else -1])
    return true


# ================================================================ 서버
func _server_tick(delta: float) -> void:
    var now := net_now()
    match state:
        State.COUNTDOWN:
            if play_start_t < 0.0:
                _wait_time += delta
                if _all_loaded() or _wait_time > LOAD_WAIT_MAX:
                    play_start_t = now + countdown_time
                    broadcast(["start", play_start_t])
                    _new_cycle(play_start_t + FIRST_WAIT)
            elif now >= play_start_t:
                state = State.PLAYING
                state_time = 0.0
                for f in fighters:
                    f.net_pending.clear()
        State.PLAYING:
            elapsed = now - play_start_t
            state_time += delta
            _advance_cycle(now)
            for f in fighters:
                if f.remote:
                    for e in f.net_pending:
                        _judge_sample(f, float(e[0]), e[1], int(e[4]) & (Sync.F_CHARGING | Sync.F_PUSH_ANIM) != 0)
                    f.net_pending.clear()
                else:
                    _judge_sample(f, now, f.global_position, _busy(f))
            _check_end()
        State.ENDED:
            state_time += delta
    _keep_finished_behind_line()
    for f in fighters:
        if not f.remote:
            _record_history(f, now, f.global_position)
    _snap_timer -= delta
    if _snap_timer <= 0.0:
        _snap_timer += 1.0 / SNAPSHOT_HZ
        var data := PackedFloat32Array()
        for f in fighters:
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


func on_client_message(pid: int, msg: Array) -> void:
    if msg.is_empty():
        return
    var f: Fighter = fighters[_slot_of_peer[pid]] if _slot_of_peer.has(pid) else null
    match String(msg[0]):
        "loaded":
            _loaded[pid] = true
        "st":
        # 이전 라운드 화면이 아직 보내는 상태는 버린다: 이 경기에 "loaded" 를 보낸 뒤의 것, 그리고 경기 시작 시각 이후의 것만
        #   (다음 라운드가 같은 게임이면 결과 화면에서 보내던 위치 — 예: 결승선 너머 — 가 새 경기로 들어오던 버그)
            if f and not f.dead and msg.size() >= 3 and _loaded.has(pid) and play_start_t > 0.0 and float(msg[1]) >= play_start_t:
                _server_receive_state(f, float(msg[1]), msg[2])
        "push":
            if f and msg.size() >= 7 and _loaded.has(pid) and is_playing():
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
    if not f.net_history.is_empty():
        var last: Array = f.net_history[-1]
        var dt := maxf(t - float(last[0]), 0.016)
        if pos.distance_to(last[1]) > 40.0 * dt + 1.0:
            f.net_rejects += 1
            if f.net_rejects < 20:
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
    if t == a or t.dead or finished.has(t.slot) or finished.has(a.slot):
        return
    var now := net_now()
    if apos.distance_to(a.global_position) > 3.0:
        return
    if tt < now - PUSH_REWIND_MAX or not _near_history(t, tt, tpos, 1.5):
        return
    if apos.distance_to(tpos) > a.push_reach + 1.2:
        return
    var h := Vector3(impulse.x, 0.0, impulse.z).limit_length(Fighter.PUSH_FORCE * a.glove_force_mult() + 1.0)
    _apply_push(t, Vector3(h.x, clampf(impulse.y, 0.0, 6.0), h.z), clampf(stun, 0.0, Fighter.STUN_MAX), a)


func _near_history(f: Fighter, t: float, pos: Vector3, tol: float) -> bool:
    if f.net_history.is_empty():
        return f.global_position.distance_to(pos) <= tol * 2.0
    for h in f.net_history:
        if absf(float(h[0]) - t) <= 0.2 and (h[1] as Vector3).distance_to(pos) <= tol:
            return true
    return false


## 서버: 경기 중 나감 → 팀전이면 봇이 이어받고, 아니면 탈락
func on_player_left(pid: int) -> void:
    if not _slot_of_peer.has(pid):
        return
    var f := fighters[_slot_of_peer[pid]]
    if teams >= 2:
        _slot_of_peer.erase(pid)
        f.peer_id = 0
        f.remote = false
        f.display_name = "Bot (%s)" % f.display_name
        f.net_history.clear()
        if not f.dead:
            var brain := BOT_BRAIN.new()
            brain.game = self
            f.add_child(brain)
        broadcast(["takeover", f.slot, f.display_name])
        return
    if not f.dead and not finished.has(f.slot) and state != State.ENDED:
        _knock_out(f, "나감", f.global_position)


# ================================================================ 클라이언트
func _client_tick(delta: float) -> void:
    var now := net_now()
    match state:
        State.COUNTDOWN:
            if play_start_t > 0.0:
                state_time = clampf(countdown_time - (play_start_t - now), 0.0, countdown_time)
                if now >= play_start_t:
                    state = State.PLAYING
                    state_time = 0.0
            else:
                state_time = 0.0
        State.PLAYING:
            elapsed = maxf(now - play_start_t, 0.0)
            state_time += delta
        State.ENDED:
            state_time += delta
    for f in fighters:
        if f.remote and not f.dead:
            Sync.apply_interpolated(f, _render_time(f))
    _send_timer -= delta
    if _send_timer <= 0.0 and human and not human.dead:
        _send_timer += 1.0 / SEND_HZ
        _send_timer = maxf(_send_timer, 0.0)
        var data := PackedFloat32Array()
        Sync.append(data, human, 0.0)
        send_to_server(["st", now, data], false)


func _render_time(f: Fighter) -> float:
    return net_now() - clampf(f.net_lag + 0.05, 0.08, 0.4)


func on_server_message(msg: Array) -> void:
    if msg.is_empty():
        return
    var now := net_now()
    match String(msg[0]):
        "start":
            play_start_t = float(msg[1])
        "cycle":
            cycle = {"idx": int(msg[1]), "t": float(msg[2]), "green": float(msg[3]), "red": float(msg[4]), "style": int(msg[5])}
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
        "fin":
            var f := _fighter_at(int(msg[1]))
            if f and not finished.has(f.slot):
                finished[f.slot] = [int(msg[2]), float(msg[3])]
                _on_finished(f)
        "out":
            var f := _fighter_at(int(msg[1]))
            if f and not f.dead:
                if f.remote and msg.size() >= 4:
                    f.global_position = msg[3]
                out_info[f.slot] = [String(msg[2]), elapsed, (msg[3] as Vector3).z if msg.size() >= 4 else f.global_position.z]
                f.die()
                _on_out(f, String(msg[2]))
        "knock":
            if human and not human.dead:
                human.receive_push(msg[1], float(msg[2]), _fighter_at(int(msg[3])))
        "pop":
            popup_text(msg[2], String(msg[1]), msg[3])
        "end":
            state = State.ENDED
            state_time = 0.0
            winner_text = String(msg[1])
            elapsed = float(msg[2])
            _ended = true
        "takeover":
            var tf := _fighter_at(int(msg[1]))
            if tf:
                tf.display_name = String(msg[2])
                if tf.name_tag:
                    tf.name_tag.text = tf.display_name


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
