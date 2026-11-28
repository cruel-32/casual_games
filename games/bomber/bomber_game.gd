extends PartyGame
## [게임 모듈] 연쇄폭탄마 (블록 탑 위에서 폭탄 던지기)
## - 정사각형 격자의 칸마다 2m 정육면체 블록이 4층 평평하게 쌓여 있고, 모두 꼭대기에서 시작한다. 아래는 용암
## - 부서지지 않는 블록(테두리와 짝수·짝수 칸)도 높이가 같아 위에 설 수 있다. 가장자리 밖으로 떨어져도 탈락
## - 밀치기 키(좌클릭·E·터치 '던지기')를 누르고 있으면 떨어질 자리가 보이고, 누른 시간만큼 멀리 포물선으로 던진다
##   폭탄은 떨어지고 LAND_FUSE 초 뒤 십자로 터진다 (범위 = 불꽃 수). 다른 폭탄에 닿으면 연쇄 폭발
## - 터진 칸은 블록이 깎인다 (가운데 2층, 나머지 1층). 높이 0 이 되면 구멍 → 용암
## - 폭탄 불길에 맞거나 용암에 떨어지면 바로 탈락 (내 폭탄·아군 폭탄 포함). 마지막까지 남은 사람(팀) 승리
## - 탈락하면 유령이 되어 경기장 바깥 테두리를 돌며 안쪽으로 폭탄을 던진다 (쿨타임)
## - Space 는 점프 (블록 3층까지 한 번에). 날아가는 폭탄에 맞으면 살짝 밀려남
##
## 온라인 (돌피하기·무궁화와 같은 구조)
## - 서버: 폭탄 생성(던진 자리·떨어질 칸·시각)·폭발·연쇄·블록 깎기·아이템·탈락·승패를 정해 알림. 봇·봇 유령도 서버가
## - 클라이언트: 내 캐릭터만 직접 움직여 상태를 보냄. 판정은 "그 시각의 내 위치"가 불길 칸·높이 안인지, 용암 높이 아래인지

const Board := preload("res://games/bomber/board.gd")
const BOT_BRAIN := preload("res://games/bomber/bot_brain.gd")
const HUD_SCRIPT := preload("res://games/bomber/hud.gd")
const Toon := preload("res://scripts/world/toon.gd")
const Sync := preload("res://scripts/core/fighter_sync.gd")
const Teams := preload("res://scripts/core/teams.gd")
const NAME_FONT := preload("res://fonts/Jua-Regular.ttf")

# 규칙
const TIME_LIMIT := 150.0
const LAND_FUSE := 1.6            ## 떨어진 뒤 터지기까지 (초)
const FLAME_TIME := 0.4           ## 불길이 남아 있는 시간
const THROW_MIN := 2.0            ## 던지는 거리 (m): 살짝 누름 ~ 끝까지 누름
const THROW_MAX := 18.0
const FLIGHT_BASE := 0.18         ## 날아가는 시간 = 기본 + 거리 비례 (빠르게)
const FLIGHT_PER_M := 0.014
const HIT_BELOW := 1.6            ## 불길 판정 높이: 폭발 층 꼭대기 기준 아래 / 위 (m)
const HIT_ABOVE := 3.2
const LAVA_OUT := 0.4             ## 발이 용암(바닥) 위 이 높이보다 낮으면 탈락 — 경기장 밖으로 떨어져도
const BODY_SCALE := 1.3           ## 캐릭터 크기 (블록 2m 에 맞춰 키움)
const BASE_SPEED := 9.6           ## 이동 속도 (속도 아이템 1개마다 +SPEED_STEP)
const SPEED_STEP := 1.2
const CHARGE_TIME := 0.7          ## 끝까지 멀리 던지려면 누르는 시간
const BOMB_HIT_R := 1.2           ## 날아가는 폭탄이 캐릭터에 맞는 거리 → 살짝 밀려남
const BOMB_HIT_PUSH := 7.0
const START_BOMBS := 1
const START_POWER := 2
const MAX_BOMBS := 6
const MAX_POWER := 7
const MAX_SPEED := 3
const ITEM_CHANCE := 0.14         ## 블록이 깎인 칸에서 아이템이 나올 확률
const GHOST_SPEED := 7.0
const GHOST_COOLDOWN := 5.0
const GHOST_POWER := 2
const GHOST_DELAY := 1.0
const JUMP_VELOCITY := 16.0      ## 점프 높이 약 6.5m: 블록 3층(6m)까지 한 번에 올라감
const FLOOR_LIFT := 0.45          ## 용암 판을 땅보다 이만큼 높게 (짧은 풀이 뚫고 보이지 않게)
const CAM_CENTER_PULL := 0.55

const SNAPSHOT_HZ := 20.0
const SEND_HZ := 30.0
const GHOST_HZ := 10.0
const HISTORY_SEC := 1.0

## 터치 버튼 이름 (scripts/ui/touch_controls.gd 가 읽음)
var touch_jump_label := "점프"
var touch_push_label := "던지기"
var touch_when_dead := true

@export var bot_count := 5

var board: Board
var teams := 0
var floor_y := 0.0                ## 용암 판 높이 (블록 0층 바닥)
var play_start_t := -1.0
var elapsed := 0.0
var bombs := {}                   ## id -> {id, owner, cell, from: Vector3, t_land, t, power, ghost, node}
var flames: Array = []            ## [{cells: {칸: 주인}, y: 폭발 층 꼭대기 월드 높이, t0, t1}]
var items := {}                   ## 칸 -> 아이템 종류
var stats := {}                   ## slot -> [폭탄 수, 불꽃, 속도]
var out_info := {}                ## slot -> [탈락 시각(경기 시작부터), 범인 slot (-1 = 추락)]
var ghosts := {}                  ## slot -> {s, cool, node}
var feed: Array = []
var winner_text := ""
var human_result := ""

var _next_bomb_id := 1
var _rng := RandomNumberGenerator.new()
var _ended := false
var _slot_of_peer := {}
var _loaded := {}
var _wait_time := 0.0
var _snap_timer := 0.0
var _send_timer := 0.0
var _ghost_timer := 0.0
var _ghost_send_timer := 0.0
var _ghost_charge_was := false

# 화면
var _cam_anchor: Node3D
var _ghost_cam: Node3D
var _col_bodies := {}             ## 칸 -> StaticBody3D (블록 기둥 충돌)
var _block_mm: Array = []         ## [층][색 0/1] -> MultiMeshInstance3D
var _item_nodes := {}
var _aim: Node3D                  ## 내가 던질 때 떨어질 자리 표시
var _mat_bomb: Material
var _mat_fuse: Material
var _mat_spark: StandardMaterial3D
var _mat_flame: StandardMaterial3D
var _mat_flame_core: StandardMaterial3D
var _mat_debris: Material
var _flame_mesh: BoxMesh
var _flame_core_mesh: SphereMesh


func _ready() -> void:
    Sfx.bgm("match")
    _rng.randomize()
    if is_server():
        countdown_time = 3.0
    if not is_online_match() and OS.get_environment("SPW_BOTS") != "":
        bot_count = int(OS.get_environment("SPW_BOTS"))      # 개발용: 혼자 연습 봇 수
    var entries := _entries()
    board = Board.new()
    board.generate(entries.size())
    floor_y = terrain.get_height(0, 0) + FLOOR_LIFT
    _build_board()
    _spawn_fighters(entries)
    if is_server():
        return
    if is_client():
        Net.game_message.connect(on_server_message)
        Net.disconnected.connect(_on_net_disconnected)
        send_loaded_when_settled()
    var layer := CanvasLayer.new()
    add_child(layer)
    var hud: Control = HUD_SCRIPT.new()
    hud.game = self
    layer.add_child(hud)
    add_common_ui(layer)


func top_y(c: Vector2i) -> float:
    return floor_y + board.top(c)


# ================================================================ 경기장
func _build_board() -> void:
    var W := board.w
    var H := board.h
    var T := Board.TILE
    var pillar_h := Board.LAYERS * Board.BLOCK
    # 용암 판 (떨어지면 여기 닿고 탈락)
    var lava_body := StaticBody3D.new()
    lava_body.collision_layer = 1
    lava_body.collision_mask = 0
    add_child(lava_body)
    var lcol := CollisionShape3D.new()
    var lshape := BoxShape3D.new()
    lshape.size = Vector3(W * T, 1.0, H * T)
    lcol.shape = lshape
    lava_body.add_child(lcol)
    lava_body.global_position = Vector3(0, floor_y - 0.5, 0)
    # 부서지지 않는 블록: 몸통 하나에 상자 여러 개 (블록 기둥과 같은 8번 층 — 위에 설 수 있음)
    var pillars := StaticBody3D.new()
    pillars.collision_layer = 8
    pillars.collision_mask = 0
    add_child(pillars)
    var pshape := BoxShape3D.new()
    pshape.size = Vector3(T, pillar_h, T)
    var pillar_cells: Array[Vector2i] = []
    for y in H:
        for x in W:
            var c := Vector2i(x, y)
            if board.pillar(c):
                pillar_cells.append(c)
                var col := CollisionShape3D.new()
                col.shape = pshape
                col.position = board.center(c) + Vector3(0, floor_y + pillar_h * 0.5, 0)
                pillars.add_child(col)
            else:
                _make_column(c)
    if is_server():
        return
    _make_materials()
    # 용암
    var lava := MeshInstance3D.new()
    var lp := PlaneMesh.new()
    lp.size = Vector2(W * T, H * T)
    lava.mesh = lp
    var lm := StandardMaterial3D.new()
    lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    lm.albedo_color = Color(1.0, 0.36, 0.08)
    lava.material_override = lm
    lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(lava)
    lava.global_position = Vector3(0, floor_y + 0.01, 0)
    var side := MeshInstance3D.new()
    var sb := BoxMesh.new()
    sb.size = Vector3(W * T + 0.2, FLOOR_LIFT + 0.3, H * T + 0.2)
    side.mesh = sb
    side.material_override = Toon.make(Color(0.3, 0.24, 0.2), {"rim_strength": 0.0})
    add_child(side)
    side.global_position = Vector3(0, floor_y - (FLOOR_LIFT + 0.3) * 0.5 - 0.01, 0)
    # 블록 모양: 2m 정육면체, 모서리 테두리 선 (shaders/block.gdshader)
    var bmesh := BoxMesh.new()
    bmesh.size = Vector3(T, Board.BLOCK, T)
    # 부서지지 않는 블록: 회색 돌 (층마다 하나씩 쌓아 그림)
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = bmesh
    mm.instance_count = pillar_cells.size() * Board.LAYERS
    var k := 0
    for c in pillar_cells:
        for layer in Board.LAYERS:
            mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, board.center(c) + Vector3(0, floor_y + (layer + 0.5) * Board.BLOCK, 0)))
            k += 1
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = _block_mat(Color(0.44, 0.47, 0.55), Color(0.16, 0.17, 0.22))
    add_child(mmi)
    # 부서지는 블록 (층·체크무늬 색마다 한 묶음)
    for layer in Board.LAYERS:
        var row: Array = []
        for kk in 2:
            var inst := MultiMeshInstance3D.new()
            var m := MultiMesh.new()
            m.transform_format = MultiMesh.TRANSFORM_3D
            m.mesh = bmesh
            inst.multimesh = m
            inst.material_override = _block_mat(_layer_color(layer, kk), Color(0.22, 0.1, 0.04))
            add_child(inst)
            row.append(inst)
        _block_mm.append(row)
    _rebuild_blocks()
    # 유령 길 (테두리 바깥 띠)
    var g := board.ghost_half()
    var ring_mat := Toon.make(Color(0.55, 0.5, 0.75), {"rim_strength": 0.0})
    for i in 4:
        var band := MeshInstance3D.new()
        var bm := BoxMesh.new()
        var horiz := i < 2
        bm.size = Vector3(g.x * 2.0 + 1.0, FLOOR_LIFT + 0.2, 1.0) if horiz else Vector3(1.0, FLOOR_LIFT + 0.2, g.y * 2.0 + 1.0)
        band.mesh = bm
        band.material_override = ring_mat
        band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(band)
        var sgn := -1.0 if i % 2 == 0 else 1.0
        var by := floor_y - FLOOR_LIFT + (FLOOR_LIFT + 0.2) * 0.5 - 0.1
        band.global_position = Vector3(0, by, sgn * g.y) if horiz else Vector3(sgn * g.x, by, 0)
    # 던질 자리 표시
    _aim = Node3D.new()
    add_child(_aim)
    var ring := MeshInstance3D.new()
    var tm := TorusMesh.new()
    tm.inner_radius = 0.7
    tm.outer_radius = 0.9
    ring.mesh = tm
    var am := StandardMaterial3D.new()
    am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    am.albedo_color = Color(1.0, 0.95, 0.3)
    am.no_depth_test = true
    ring.material_override = am
    _aim.add_child(ring)
    _aim.visible = false


## 층마다 색 (아래는 진한 흙, 위로 갈수록 밝은 주황). k = 체크무늬 (이웃 칸끼리 색이 살짝 다름)
static func _layer_color(layer: int, k: int) -> Color:
    var a := Color(0.55, 0.28, 0.14)
    var b := Color(0.98, 0.62, 0.22)
    var c := a.lerp(b, float(layer) / float(Board.LAYERS - 1))
    return c.darkened(0.14) if k == 1 else c


const BLOCK_SHADER := preload("res://shaders/block.gdshader")


static func _block_mat(col: Color, edge: Color) -> ShaderMaterial:
    var m := ShaderMaterial.new()
    m.shader = BLOCK_SHADER
    m.set_shader_parameter("albedo", col)
    m.set_shader_parameter("edge_color", edge)
    m.set_shader_parameter("half_size", Board.BLOCK * 0.5)
    return m


func _make_column(c: Vector2i) -> void:
    var body := StaticBody3D.new()
    body.collision_layer = 8          # 카메라 팔(1번 층만 봄)에 걸리지 않게 따로
    body.collision_mask = 0
    add_child(body)
    var p := board.center(c)
    body.global_position = Vector3(p.x, floor_y, p.z)
    var col := CollisionShape3D.new()
    col.shape = BoxShape3D.new()
    body.add_child(col)
    _col_bodies[board.idx(c)] = body
    _update_column(c)


func _update_column(c: Vector2i) -> void:
    var body: StaticBody3D = _col_bodies.get(board.idx(c))
    if body == null:
        return
    var col: CollisionShape3D = body.get_child(0)
    var hm := board.top(c)
    col.disabled = hm <= 0.0
    (col.shape as BoxShape3D).size = Vector3(Board.TILE, maxf(hm, 0.1), Board.TILE)
    col.position.y = hm * 0.5


func _rebuild_blocks() -> void:
    if _block_mm.is_empty():
        return
    var lists: Array = []
    for layer in Board.LAYERS:
        lists.append([[], []])
    for y in board.h:
        for x in board.w:
            var c := Vector2i(x, y)
            var hh := board.height(c)
            if board.pillar(c):
                continue
            var p := board.center(c)
            for layer in hh:
                lists[layer][(x + y) % 2].append(Vector3(p.x, floor_y + (layer + 0.5) * Board.BLOCK, p.z))
    for layer in Board.LAYERS:
        for k in 2:
            var m: MultiMesh = (_block_mm[layer][k] as MultiMeshInstance3D).multimesh
            var arr: Array = lists[layer][k]
            m.instance_count = arr.size()
            for i in arr.size():
                m.set_instance_transform(i, Transform3D(Basis.IDENTITY, arr[i]))


func _make_materials() -> void:
    _mat_bomb = Toon.make(Color(0.13, 0.13, 0.18), {"rim_strength": 0.6})
    _mat_fuse = Toon.make(Color(0.55, 0.42, 0.3), {"rim_strength": 0.0})
    _mat_spark = StandardMaterial3D.new()
    _mat_spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _mat_spark.albedo_color = Color(1.0, 0.85, 0.3)
    _mat_flame = StandardMaterial3D.new()
    _mat_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _mat_flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _mat_flame.albedo_color = Color(1.0, 0.45, 0.1, 0.85)
    _mat_flame.cull_mode = BaseMaterial3D.CULL_DISABLED
    _mat_flame_core = StandardMaterial3D.new()
    _mat_flame_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _mat_flame_core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _mat_flame_core.albedo_color = Color(1.0, 0.92, 0.5, 0.95)
    _mat_debris = Toon.make(Color(0.7, 0.55, 0.35), {"rim_strength": 0.0})
    _flame_mesh = BoxMesh.new()
    _flame_mesh.size = Vector3(1.7, 1.6, 1.7)
    _flame_core_mesh = SphereMesh.new()
    _flame_core_mesh.radius = 0.75
    _flame_core_mesh.height = 1.5


## 칸이 깎임 (모든 기기)
func _lower(i: int, n: int) -> void:
    var c := board.cell(i)
    var before := board.height(c)
    if before <= 0:
        return
    board.hgt[i] = maxi(before - n, 0)
    _update_column(c)
    if is_server():
        return
    # 블록 조각이 튄다
    var p := board.center(c) + Vector3(0, floor_y + before * Board.BLOCK - 0.5, 0)
    for k in 5:
        var d := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.5, 0.4, 0.5)
        d.mesh = bm
        d.material_override = _block_mm[clampi(before - 1, 0, Board.LAYERS - 1)][0].material_override
        add_child(d)
        d.global_position = p + Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6))
        var to := d.global_position + Vector3(randf_range(-2.0, 2.0), randf_range(0.8, 2.2), randf_range(-2.0, 2.0))
        var tw := create_tween()
        tw.set_parallel(true)
        tw.tween_property(d, "global_position", to, 0.35).set_ease(Tween.EASE_OUT)
        tw.tween_property(d, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.7)
        tw.chain().tween_property(d, "global_position:y", floor_y - 1.0, 0.45).set_ease(Tween.EASE_IN)
        tw.chain().tween_callback(d.queue_free)


# ================================================================ 참가자
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
    var spots := mixed_spots(entries.map(func(e): return int(e.get("team", -1))))
    for i in entries.size():
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
        f.throw_mode = true
        f.jump_velocity = JUMP_VELOCITY
        f.move_speed = BASE_SPEED
        f.ground_accel = 40.0
        f.air_accel = 14.0
        f.charge_max_time = CHARGE_TIME
        f.body_scale = BODY_SCALE
        var c: Vector2i = board.spawns[int(spots[i])]
        var p := board.center(c)
        f.position = Vector3(p.x, top_y(c) + 0.2, p.z)
        f.rotation.y = atan2(p.x, p.z)          # 가운데를 바라봄 (얼굴 = -Z)
        stats[i] = [START_BOMBS, START_POWER, 0]
        if not f.is_human and not f.remote:
            var brain := BOT_BRAIN.new()
            brain.game = self
            f.add_child(brain)
        add_child(f)
        f.collision_mask = 1 | 4 | 8      # 사람끼리는 통과 (좁은 1칸 길에서 막히지 않게) + 블록 기둥
        fighters.append(f)
        if f.is_human:
            human = f
            _setup_camera(f)


func _setup_camera(f: Fighter) -> void:
    if f.pitch_pivot == null:
        return
    _cam_anchor = Node3D.new()
    add_child(_cam_anchor)
    _cam_anchor.global_position = _anchor_goal(f)
    f.set_spectate(null)                          # 카메라 받침대를 몸에서 떼어 냄 (cam_follow 를 따라감)
    f.cam_follow = _cam_anchor
    f.cam_min_len = 3.0
    f.cam_max_len = 48.0
    f.spring_arm.spring_length = clampf(maxf(board.h * Board.TILE, board.w * Board.TILE * 0.62) * 0.92, 18.0, 30.0)
    f.pitch_pivot.rotation = Vector3(deg_to_rad(-64.0), 0.0, 0.0)     # 화면 위쪽 = 경기장 -z 쪽
    f.spring_arm.position.x = 0.0


func _anchor_goal(f: Fighter) -> Vector3:
    var c := Vector3(0, floor_y + Board.LAYERS * Board.BLOCK, 0)
    return f.global_position.lerp(c, CAM_CENTER_PULL) - Vector3(0, 1.3, 0)


func stat(slot: int, k: int) -> int:
    return int(stats[slot][k]) if stats.has(slot) else 0


func active_bombs_of(slot: int, ghost: bool = false) -> int:
    var n := 0
    for id in bombs:
        var b: Dictionary = bombs[id]
        if int(b.owner) == slot and bool(b.ghost) == ghost:
            n += 1
    return n


# ================================================================ 던지기
## 던지기 비율(0~1) → 거리
static func throw_dist(r: float) -> float:
    return lerpf(THROW_MIN, THROW_MAX, clampf(r, 0.0, 1.0))


## 지금 손을 떼면 떨어질 칸 (조준 표시·봇용)
func aim_cell(f: Fighter, r: float) -> Vector2i:
    return board.throw_target(f.global_position, f.facing(), throw_dist(r))


## Fighter 가 밀치기 키를 뗐다 (던지기 모드)
func on_throw(f: Fighter, r: float) -> void:
    if f.dead or not is_playing() or f.remote:
        return
    if active_bombs_of(f.slot) >= stat(f.slot, 0):
        if f == human:
            popup_text(f.global_position + Vector3(0, 2.4, 0), "폭탄 없음", Color(0.9, 0.9, 0.9))
        return
    var c := aim_cell(f, r)
    var from := f.global_position + Vector3(0, 1.4, 0)
    if is_client():
        send_to_server(["throw", board.idx(c), from])
        return
    _create_bomb(f.slot, board.idx(c), stat(f.slot, 1), false, from)


## 서버·오프라인: 폭탄 만들기 (from 에서 포물선으로 날아가 칸 i 에 떨어짐)
func _create_bomb(owner: int, i: int, power: int, ghost: bool, from: Vector3) -> void:
    var id := _next_bomb_id
    _next_bomb_id += 1
    var now := net_now()
    var to := board.center(board.cell(i))
    var dist := Vector2(to.x - from.x, to.z - from.z).length()
    var t_land := now + FLIGHT_BASE + dist * FLIGHT_PER_M
    var t := t_land + LAND_FUSE
    _add_bomb(id, owner, i, from, t_land, t, power, ghost)
    if is_server():
        broadcast(["bomb", id, owner, i, from, t_land, t, power, ghost])


func _add_bomb(id: int, owner: int, i: int, from: Vector3, t_land: float, t: float, power: int, ghost: bool) -> void:
    var b := {"id": id, "owner": owner, "cell": i, "from": from, "t_land": t_land, "t": t, "power": power,
            "ghost": ghost, "node": null, "landed": false, "hit": {}}
    bombs[id] = b
    if is_server():
        return
    var vis := Node3D.new()
    add_child(vis)
    var ball := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.6
    sm.height = 1.2
    ball.mesh = sm
    ball.material_override = _mat_bomb
    ball.position.y = 0.6
    vis.add_child(ball)
    var fuse := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 0.07
    cm.bottom_radius = 0.09
    cm.height = 0.35
    fuse.mesh = cm
    fuse.material_override = _mat_fuse
    fuse.position = Vector3(0, 1.32, 0)
    fuse.rotation.z = 0.3
    vis.add_child(fuse)
    var spark := MeshInstance3D.new()
    var sp := SphereMesh.new()
    sp.radius = 0.13
    sp.height = 0.26
    spark.mesh = sp
    spark.material_override = _mat_spark
    spark.position = Vector3(-0.07, 1.52, 0)
    spark.name = "Spark"
    vis.add_child(spark)
    var ring := MeshInstance3D.new()
    var tm := TorusMesh.new()
    tm.inner_radius = 0.53
    tm.outer_radius = 0.66
    ring.mesh = tm
    var oc: Color = fighters[owner].body_color if owner >= 0 and owner < fighters.size() else Color.WHITE
    ring.material_override = Toon.make(oc, {"rim_strength": 0.0})
    ring.position.y = 0.6
    vis.add_child(ring)
    b.node = vis
    vis.global_position = from
    Sfx.play_at("ghost_throw" if ghost else "bomb_place", from, self, -4.0)


## 폭탄의 지금 위치 (날아가는 중이면 포물선, 떨어졌으면 칸 꼭대기)
func bomb_pos(b: Dictionary, t: float) -> Vector3:
    var c := board.cell(int(b.cell))
    var p := board.center(c)
    var end := Vector3(p.x, top_y(c), p.z)
    if board.height(c) <= 0:
        end.y = floor_y - 0.6
    if t >= float(b.t_land):
        return end
    var from: Vector3 = b.from
    var dur := FLIGHT_BASE + Vector2(end.x - from.x, end.z - from.z).length() * FLIGHT_PER_M
    var k := clampf(1.0 - (float(b.t_land) - t) / maxf(dur, 0.05), 0.0, 1.0)
    var apex := maxf(from.y, end.y) + 2.5 + Vector2(end.x - from.x, end.z - from.z).length() * 0.12
    var y := lerpf(from.y, end.y, k) + (apex - maxf(from.y, end.y)) * 4.0 * k * (1.0 - k)
    return Vector3(lerpf(from.x, end.x, k), y, lerpf(from.z, end.z, k))


## 떨어진 칸 번호 목록 (봇: 위험 계산용) — 날아가는 중이어도 떨어질 칸
func bomb_cell(b: Dictionary) -> int:
    return int(b.cell)


## 시간이 된 폭탄 터뜨리기, 떨어진 칸이 구멍이면 용암에 빠져 사라짐, 불길 속에 떨어진 폭탄은 바로 (서버·오프라인)
func _update_bombs(now: float) -> void:
    var due: Array = []
    var sunk: Array = []
    for id in bombs:
        var b: Dictionary = bombs[id]
        if now < float(b.t_land):
            _flight_hits(b, now)
            continue
        var c := board.cell(int(b.cell))
        if board.height(c) <= 0:
            sunk.append(int(id))
        elif float(b.t) <= now or _in_flame(int(b.cell), now, top_y(c)) > -2:
            due.append(int(id))
    for id in sunk:
        _sink_bomb(id)
        if is_server():
            broadcast(["sink", id])
    if not due.is_empty():
        _explode(due, now)


## 날아가는 폭탄이 캐릭터에 맞으면 날아가던 쪽으로 살짝 밀림 (폭탄은 그대로 날아감, 한 사람에 한 번)
func _flight_hits(b: Dictionary, now: float) -> void:
    var p := bomb_pos(b, now)
    var from: Vector3 = b.from
    var to := board.center(board.cell(int(b.cell)))
    var dir := Vector3(to.x - from.x, 0, to.z - from.z)
    dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
    var hit: Dictionary = b.get("hit", {})
    for f in fighters:
        if f.dead or hit.has(f.slot):
            continue
        if f.slot == int(b.owner) and now < float(b.t_land) - 0.1 and from.distance_to(p) < 2.0:
            continue          # 막 던진 내 폭탄은 나를 안 맞힘
        var body := f.global_position + Vector3(0, Fighter.HEIGHT * BODY_SCALE * 0.5, 0)
        if body.distance_to(p) > BOMB_HIT_R:
            continue
        hit[f.slot] = true
        var impulse := dir * BOMB_HIT_PUSH + Vector3(0, 3.5, 0)
        var attacker: Fighter = fighters[int(b.owner)] if int(b.owner) >= 0 and int(b.owner) < fighters.size() else null
        if f.remote:
            send_to_peer(f.peer_id, ["knock", impulse, 0.25, int(b.owner)])
        else:
            f.receive_push(impulse, 0.25, attacker)
        if is_server():
            broadcast(["pop", "퍽!", f.global_position + Vector3(0, 2.6, 0), Color(1.0, 0.85, 0.4)])
        else:
            popup_text(f.global_position + Vector3(0, 2.6, 0), "퍽!", Color(1.0, 0.85, 0.4))
    b.hit = hit


func _sink_bomb(id: int) -> void:
    var b: Dictionary = bombs.get(id, {})
    if b.is_empty():
        return
    bombs.erase(id)
    if is_instance_valid(b.node):
        var n: Node3D = b.node
        var tw := create_tween()
        tw.tween_property(n, "global_position:y", floor_y - 1.5, 0.4)
        tw.tween_callback(n.queue_free)


## 연쇄 폭발 처리 → 알림
func _explode(ids: Array, now: float) -> void:
    var queue: Array = ids.duplicate()
    var done := {}
    var groups: Array = []            # [{cells: {칸: 주인}, y}]
    var lower := {}                   # 칸 -> 깎을 층 수 (가장 큰 값)
    var burned := {}
    while not queue.is_empty():
        var id: int = queue.pop_front()
        if done.has(id) or not bombs.has(id):
            continue
        done[id] = true
        var b: Dictionary = bombs[id]
        var c := board.cell(int(b.cell))
        var level := maxi(board.height(c), 0)
        var y := floor_y + level * Board.BLOCK
        var owner := int(b.owner)
        var fire := {}
        for n: Vector2i in board.blast(c, int(b.power)):
            var i := board.idx(n)
            fire[i] = owner
            lower[i] = maxi(int(lower.get(i, 0)), board.lowered_by(c, n, level))
            if items.has(i) and absf(top_y(n) - y) <= 1.5:
                burned[i] = true
            for oid in bombs:
                var ob: Dictionary = bombs[oid]
                if done.has(int(oid)) or int(ob.cell) != i or now < float(ob.t_land):
                    continue
                if absi(board.height(n) - level) <= 1:
                    queue.append(int(oid))
        groups.append({"cells": fire, "y": y})
    # 새 아이템 (깎인 칸에서, 깎인 뒤에도 서 있을 수 있으면)
    var new_items := PackedInt32Array()
    for i in lower:
        var n := int(lower[i])
        if n <= 0:
            continue
        if board.height(board.cell(int(i))) - n > 0 and not items.has(int(i)) and _rng.randf() < ITEM_CHANCE:
            var r := _rng.randf()
            new_items.append(int(i))
            new_items.append(Board.ITEM_FIRE if r < 0.38 else (Board.ITEM_BOMB if r < 0.72 else Board.ITEM_SPEED))
    var low := PackedInt32Array()
    for i in lower:
        if int(lower[i]) > 0:
            low.append(int(i))
            low.append(int(lower[i]))
    var ids_arr := PackedInt32Array(done.keys())
    var burned_arr := PackedInt32Array(burned.keys())
    _apply_boom(ids_arr, groups, low, burned_arr, new_items, now)
    if is_server():
        var gdata: Array = []
        for gr in groups:
            var cells := PackedInt32Array()
            var owners := PackedInt32Array()
            for i in gr.cells:
                cells.append(int(i))
                owners.append(int(gr.cells[i]))
            gdata.append([cells, owners, float(gr.y)])
        broadcast(["boom", now, ids_arr, gdata, low, burned_arr, new_items])


## 폭발 결과 반영 (모든 기기). low = [칸, 층 수, ...], new_items = [칸, 종류, ...]
func _apply_boom(ids: PackedInt32Array, groups: Array, low: PackedInt32Array, burned: PackedInt32Array,
        new_items: PackedInt32Array, t: float) -> void:
    for id in ids:
        var b: Dictionary = bombs.get(int(id), {})
        if b.is_empty():
            continue
        if is_instance_valid(b.node):
            (b.node as Node3D).queue_free()
        bombs.erase(int(id))
    for i in burned:
        _remove_item(int(i), true)
    for gr in groups:
        flames.append({"cells": gr.cells, "y": float(gr.y), "t0": t, "t1": t + FLAME_TIME})
    for k in range(0, low.size() - 1, 2):
        _lower(low[k], low[k + 1])
        if board.height(board.cell(low[k])) <= 0 and items.has(low[k]):
            _remove_item(low[k], true)
    for k in range(0, new_items.size() - 1, 2):
        _add_item(new_items[k], new_items[k + 1])
    _rebuild_blocks()
    if is_server():
        return
    var center := Vector3.ZERO
    var n := 0
    for gr in groups:
        _show_flames(gr.cells, float(gr.y))
        for i in gr.cells:
            var p := board.center(board.cell(int(i)))
            center += Vector3(p.x, float(gr.y), p.z)
            n += 1
    center /= maxf(n, 1.0)
    Sfx.play_at("boom", center, self, minf(ids.size() - 1, 4) * 1.0)
    if human and human.camera:
        var d := human.global_position.distance_to(center) if not human.dead else 10.0
        human.shake = maxf(human.shake, clampf(1.0 - d / 20.0, 0.0, 1.0) * (0.5 + 0.15 * ids.size()))


func _show_flames(fire: Dictionary, y: float) -> void:
    for i in fire:
        var c := board.cell(int(i))
        var p := board.center(c) + Vector3(0, y, 0)
        var m := MeshInstance3D.new()
        m.mesh = _flame_mesh
        m.material_override = _mat_flame
        m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(m)
        m.global_position = p + Vector3(0, 0.8, 0)
        m.scale = Vector3(0.3, 0.2, 0.3)
        var core := MeshInstance3D.new()
        core.mesh = _flame_core_mesh
        core.material_override = _mat_flame_core
        core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(core)
        core.global_position = p + Vector3(0, 0.8, 0)
        core.scale = Vector3.ONE * 0.2
        var tw := create_tween()
        tw.set_parallel(true)
        tw.tween_property(m, "scale", Vector3(1.0, 1.5, 1.0), 0.1).set_ease(Tween.EASE_OUT)
        tw.tween_property(core, "scale", Vector3.ONE, 0.1).set_ease(Tween.EASE_OUT)
        tw.chain().tween_interval(FLAME_TIME - 0.25)
        tw.chain().tween_property(m, "scale", Vector3(0.2, 2.2, 0.2), 0.2).set_ease(Tween.EASE_IN)
        tw.parallel().tween_property(core, "scale", Vector3.ZERO, 0.2)
        tw.chain().tween_callback(m.queue_free)
        tw.chain().tween_callback(core.queue_free)


## 그 시각·그 높이에 그 칸에 불길이 있으면 주인 slot, 없으면 -2
func _in_flame(i: int, t: float, y: float) -> int:
    for fl in flames:
        if t >= float(fl.t0) and t < float(fl.t1) and fl.cells.has(i):
            var fy := float(fl.y)
            if y >= fy - HIT_BELOW and y <= fy + HIT_ABOVE:
                return int(fl.cells[i])
    return -2


func _prune_flames(now: float) -> void:
    while not flames.is_empty() and float(flames[0].t1) < now - HISTORY_SEC - 0.5:
        flames.pop_front()


# ================================================================ 아이템
func _add_item(i: int, kind: int) -> void:
    items[i] = kind
    if is_server():
        return
    var root := Node3D.new()
    add_child(root)
    root.global_position = board.center(board.cell(i)) + Vector3(0, top_y(board.cell(i)) + 0.7, 0)
    var colr := [Color(1.0, 0.45, 0.15), Color(0.25, 0.25, 0.32), Color(0.3, 0.7, 1.0)][kind] as Color
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.9, 0.9, 0.9)
    mi.mesh = bm
    mi.material_override = Toon.make(colr, {"rim_strength": 0.5})
    root.add_child(mi)
    var l := Label3D.new()
    l.text = ["불꽃", "폭탄", "속도"][kind]
    l.font = NAME_FONT
    l.font_size = 64
    l.outline_size = 14
    l.pixel_size = 0.006
    l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    l.no_depth_test = true
    l.modulate = Color(1, 1, 0.9)
    l.position.y = 0.9
    root.add_child(l)
    root.scale = Vector3.ONE * 0.1
    var tw := create_tween()
    tw.tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _item_nodes[i] = root


func _remove_item(i: int, burned: bool) -> void:
    items.erase(i)
    var n: Node3D = _item_nodes.get(i)
    _item_nodes.erase(i)
    if n == null:
        return
    if burned:
        n.queue_free()
        return
    var tw := create_tween()
    tw.tween_property(n, "scale", Vector3.ONE * 1.5, 0.08)
    tw.tween_property(n, "scale", Vector3.ZERO, 0.12)
    tw.tween_callback(n.queue_free)


func _pick_item(f: Fighter, i: int) -> void:
    var kind := int(items[i])
    _remove_item(i, false)
    _apply_item(f, kind)
    if is_server():
        broadcast(["item", i, f.slot, kind])


func _apply_item(f: Fighter, kind: int) -> void:
    var s: Array = stats[f.slot]
    match kind:
        Board.ITEM_FIRE:
            s[1] = mini(int(s[1]) + 1, MAX_POWER)
        Board.ITEM_BOMB:
            s[0] = mini(int(s[0]) + 1, MAX_BOMBS)
        Board.ITEM_SPEED:
            s[2] = mini(int(s[2]) + 1, MAX_SPEED)
            f.move_speed = BASE_SPEED + SPEED_STEP * int(s[2])
    if not is_server():
        var txt: String = ["불꽃 +1", "폭탄 +1", "속도 +1"][kind]
        popup_text(f.global_position + Vector3(0, 2.4, 0), txt, Color(1.0, 0.9, 0.4))
        if f == human:
            Sfx.play("pickup")
        else:
            Sfx.play_at("pickup", f.global_position, self, -6.0)


# ================================================================ 판정 (서버·오프라인)
## 위치 하나로 판정: 용암·불길·아이템
func _judge_sample(f: Fighter, t: float, pos: Vector3) -> void:
    if f.dead or _ended or play_start_t < 0.0 or t < play_start_t:
        return
    if pos.y < floor_y + LAVA_OUT:
        _knock_out(f, -1, pos)
        return
    var c := board.cell_at(pos)
    var i := board.idx(c)
    var who := _in_flame(i, t, pos.y)
    if who > -2:
        _knock_out(f, who, pos)
        return
    if items.has(i) and absf(pos.y - top_y(c)) < 2.2:
        _pick_item(f, i)


func _knock_out(f: Fighter, killer: int, pos: Vector3) -> void:
    out_info[f.slot] = [maxf(net_now() - play_start_t, 0.0), killer]
    if is_server():
        broadcast(["out", f.slot, killer, pos])
    _on_out(f, killer)


func _on_out(f: Fighter, killer: int) -> void:
    if not f.remote and not f.dead and killer >= 0:
        f.velocity.y = 8.0
        f.knock = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized() * 3.0
    f.die()
    var kname := ""
    if killer == -1:
        kname = "떨어짐"
    elif killer == f.slot:
        kname = "자폭"
    elif killer >= 0 and killer < fighters.size():
        kname = fighters[killer].display_name + "의 폭탄"
    _feed("%s 탈락 (%s)" % [f.display_name, kname], Color(1.0, 0.5, 0.45) if f == human else Color(0.9, 0.9, 0.9))
    if f == human:
        human_result = "탈락 — " + kname + " · 유령이 되어 밖에서 폭탄을 던질 수 있어요"
    if not is_server():
        popup_text(f.global_position + Vector3(0, 2.4, 0), "펑!" if killer >= 0 else "앗 뜨거!", Color(1.0, 0.55, 0.25))
        get_tree().create_timer(0.7).timeout.connect(func():
            if is_instance_valid(f) and f.visual:
                f.visual.visible = false
                if f.name_tag:
                    f.name_tag.visible = false)
    get_tree().create_timer(GHOST_DELAY).timeout.connect(func():
        if is_inside_tree() and not _ended:
            _make_ghost(f))


func _feed(text: String, color: Color) -> void:
    feed.append({"text": text, "color": color, "time": Time.get_ticks_msec() / 1000.0})
    if feed.size() > 5:
        feed.pop_front()

func _check_end() -> void:
    if _ended or play_start_t < 0.0:
        return
    var t := net_now()
    var alive := alive_fighters()
    var over := t - play_start_t >= TIME_LIMIT
    if not over:
        if teams >= 2:
            var tset := {}
            for f in alive:
                tset[f.team] = true
            if tset.size() > 1:
                return
        elif alive.size() > 1:
            return
    _ended = true
    state = State.ENDED
    state_time = 0.0
    var places := _placements()
    winner_text = _winner_text(alive, over)
    if is_server():
        broadcast(["end", winner_text, elapsed])
        print("[server] 경기 종료 #%d %s" % [room_id(), winner_text])
        report_result(places)

func _winner_text(alive: Array[Fighter], over: bool) -> String:
    if alive.is_empty():
        return "무승부! 모두 날아갔어요"
    if teams >= 2:
        var tset := {}
        for f in alive:
            tset[f.team] = true
        if tset.size() == 1:
            return "%s 승리!" % Teams.team_name(alive[0].team)
        return "시간 종료 — 무승부"
    if alive.size() == 1:
        return "%s 승리!" % alive[0].display_name
    return "시간 종료 — %d명 공동 1등" % alive.size() if over else "무승부"


## 순위: 살아남은 사람 > 늦게 탈락한 사람

func _score(f: Fighter) -> float:
    if not f.dead:
        return 1.0e6
    return float(out_info[f.slot][0]) if out_info.has(f.slot) else 0.0

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
        if i == 0 or absf(s - prev) > 0.01:
            rank = i + 1
        prev = s
        out.append({"rank": rank, "members": [participant(f)], "team": ""})
    return out


## 팀 순위: 살아남은 팀원 수 → 마지막 팀원이 탈락한 시각

func _team_placements() -> Array:
    var key := {}
    var members := {}
    for f in fighters:
        if not key.has(f.team):
            key[f.team] = [0, 0.0]
            members[f.team] = []
        members[f.team].append(participant(f))
        var k: Array = key[f.team]
        if not f.dead:
            k[0] += 1
        elif out_info.has(f.slot):
            k[1] = maxf(float(k[1]), float(out_info[f.slot][0]))
    var order: Array = key.keys()
    order.sort_custom(func(a, b): return _team_key(key[a]) > _team_key(key[b]))
    var out := []
    var rank := 0
    var prev := INF
    for i in order.size():
        var tm: int = order[i]
        var s := _team_key(key[tm])
        if i == 0 or absf(s - prev) > 0.01:
            rank = i + 1
        prev = s
        out.append({"rank": rank, "members": members[tm], "team": Teams.team_name(tm)})
    return out

static func _team_key(k: Array) -> float:
    return float(k[0]) * 10000.0 + float(k[1])


# ================================================================ 유령
func _make_ghost(f: Fighter) -> void:
    if ghosts.has(f.slot):
        return
    var s := board.ghost_project(f.global_position)
    var g := {"s": s, "cool": net_now() + 1.5, "node": null, "target_s": s}
    ghosts[f.slot] = g
    if is_server():
        return
    var root := Node3D.new()
    add_child(root)
    var col := f.body_color
    var body_mat := StandardMaterial3D.new()
    body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    body_mat.albedo_color = Color(col.lerp(Color.WHITE, 0.45), 0.7)
    var head := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.55
    sm.height = 1.1
    head.mesh = sm
    head.material_override = body_mat
    head.position.y = 0.6
    root.add_child(head)
    var tail := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 0.55
    cm.bottom_radius = 0.05
    cm.height = 0.9
    tail.mesh = cm
    tail.material_override = body_mat
    tail.position.y = 0.05
    root.add_child(tail)
    for sx in [-0.2, 0.2]:
        var eye := MeshInstance3D.new()
        var em := SphereMesh.new()
        em.radius = 0.09
        em.height = 0.18
        eye.mesh = em
        eye.material_override = Toon.make(Color(0.1, 0.1, 0.15), {"rim_strength": 0.0})
        eye.position = Vector3(sx, 0.72, -0.48)
        root.add_child(eye)
    var l := Label3D.new()
    l.text = f.display_name
    l.font = NAME_FONT
    l.font_size = 48
    l.outline_size = 10
    l.pixel_size = 0.006
    l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    l.no_depth_test = true
    l.modulate = Color(col.lerp(Color.WHITE, 0.5), 0.85)
    l.position.y = 1.5
    root.add_child(l)
    root.global_position = board.ghost_pos(s) + Vector3(0, floor_y + Board.LAYERS * Board.BLOCK + 1.2, 0)
    g.node = root
    if f == human:
        f.set_spectate(null)
        f.cam_follow = root
        if _cam_anchor:
            f.cam_follow = _cam_anchor
            _ghost_cam = root

func ghost_cooldown_left(slot: int) -> float:
    if not ghosts.has(slot):
        return 0.0
    return maxf(float(ghosts[slot].cool) - net_now(), 0.0)


## 사람 유령 조작 (이 기기의 내 유령)


## 사람 유령 조작 (이 기기의 내 유령): 이동으로 테두리를 돌고, 던지기 키를 누르면 던짐
func _drive_my_ghost(delta: float) -> void:
    if human == null or not ghosts.has(human.slot) or not is_playing():
        return
    var g: Dictionary = ghosts[human.slot]
    var tan := board.ghost_tangent(float(g.s))
    var mv := human.intent_move
    g.s = fposmod(float(g.s) + mv.dot(tan) * GHOST_SPEED * delta, board.ghost_len())
    var pressed := human.intent_charge or human.intent_jump
    if pressed and not _ghost_charge_was and ghost_cooldown_left(human.slot) <= 0.0:
        if is_client():
            send_to_server(["gthrow", float(g.s)])
            g.cool = net_now() + 0.4
        else:
            _ghost_throw(human.slot, float(g.s))
    _ghost_charge_was = pressed
    human.intent_jump = false


## 서버·오프라인: 유령 던지기
func _ghost_throw(slot: int, s: float) -> void:
    if not ghosts.has(slot) or not is_playing():
        return
    var g: Dictionary = ghosts[slot]
    if net_now() < float(g.cool) or active_bombs_of(slot, true) > 0:
        return
    var c := board.ghost_target(s)
    if c.x < 0:
        return
    g.cool = net_now() + GHOST_COOLDOWN
    if is_server():
        broadcast(["gcool", slot, float(g.cool)])
    _create_bomb(slot, board.idx(c), GHOST_POWER, true, board.ghost_pos(s) + Vector3(0, floor_y + 1.6, 0))


func _drive_bot_ghosts(delta: float) -> void:
    for slot in ghosts:
        var f: Fighter = fighters[slot]
        if f.peer_id != 0 or f == human:
            continue
        var g: Dictionary = ghosts[slot]
        var best: Fighter = null
        var bd := INF
        var gp := board.ghost_pos(float(g.s))
        for o in fighters:
            if o.dead or (f.team >= 0 and o.team == f.team):
                continue
            var d := o.global_position.distance_to(gp)
            if d < bd:
                bd = d
                best = o
        if best == null:
            continue
        var ts := board.ghost_project(best.global_position)
        var L := board.ghost_len()
        var diff := fposmod(ts - float(g.s) + L * 0.5, L) - L * 0.5
        g.s = fposmod(float(g.s) + clampf(diff, -1.0, 1.0) * GHOST_SPEED * 0.6 * delta, L)
        if absf(diff) < 1.2 and ghost_cooldown_left(slot) <= 0.0 and _rng.randf() < delta * 1.2:
            _ghost_throw(slot, float(g.s))

func _update_ghost_nodes(delta: float) -> void:
    var t := Time.get_ticks_msec() * 0.001
    for slot in ghosts:
        var g: Dictionary = ghosts[slot]
        var n: Node3D = g.node
        if n == null:
            continue
        var goal := board.ghost_pos(float(g.s)) + Vector3(0, floor_y + Board.LAYERS * Board.BLOCK + 1.2 + sin(t * 2.5 + slot) * 0.15, 0)
        if n.global_position.distance_to(goal) > 6.0:
            n.global_position = goal
        else:
            n.global_position = n.global_position.lerp(goal, 1.0 - exp(-12.0 * delta))
        var inward := board.ghost_tangent(float(g.s)).cross(Vector3.UP)
        n.rotation.y = atan2(-inward.x, -inward.z)


# ================================================================ 진행
func _physics_process(delta: float) -> void:
    match net_role:
        NetRole.SERVER:
            _server_tick(delta)
            return
        NetRole.CLIENT:
            _client_tick(delta)
            _drive_my_ghost(delta)
            _update_ghost_nodes(delta)
            return
    state_time += delta
    var now := net_now()
    match state:
        State.COUNTDOWN:
            if state_time >= countdown_time:
                state = State.PLAYING
                state_time = 0.0
                play_start_t = now
        State.PLAYING:
            elapsed = now - play_start_t
            _update_bombs(now)
            for f in fighters:
                _judge_sample(f, now, f.global_position)
            _drive_my_ghost(delta)
            _drive_bot_ghosts(delta)
            _prune_flames(now)
            _check_end()
    _update_ghost_nodes(delta)


func _process(delta: float) -> void:
    if is_server():
        return
    if _cam_anchor and human:
        if not human.dead:
            _cam_anchor.global_position = _anchor_goal(human)
        elif is_instance_valid(_ghost_cam):
            _cam_anchor.global_position = _ghost_cam.global_position.lerp(Vector3(0, floor_y + Board.LAYERS * Board.BLOCK, 0), 0.7) - Vector3(0, 1.3, 0)
    var t := net_now()
    for id in bombs:
        var b: Dictionary = bombs[id]
        var vis: Node3D = b.node
        if not is_instance_valid(vis):
            continue
        var p := bomb_pos(b, t)
        vis.global_position = vis.global_position.lerp(p, 1.0 - exp(-30.0 * delta)) if t >= float(b.t_land) else p
        if t < float(b.t_land):
            vis.rotation.x += delta * 8.0
            continue
        vis.rotation.x = lerpf(vis.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
        if not b.landed:
            b.landed = true
            Sfx.play_at("kick", p, self, -6.0)
        var left := float(b.t) - t
        var rate := lerpf(16.0, 4.0, clampf(left / LAND_FUSE, 0.0, 1.0))
        vis.scale = Vector3.ONE * (1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.001 * rate) + clampf(0.6 - left, 0.0, 0.6) * 0.35)
        var spark: Node3D = vis.get_node_or_null("Spark")
        if spark:
            spark.scale = Vector3.ONE * randf_range(0.7, 1.4)
    for i in _item_nodes:
        var n: Node3D = _item_nodes[i]
        if is_instance_valid(n):
            n.rotation.y += delta * 1.6
            var ty := top_y(board.cell(int(i))) + 0.7 + sin(Time.get_ticks_msec() * 0.003 + int(i)) * 0.12
            n.global_position.y = lerpf(n.global_position.y, ty, 1.0 - exp(-12.0 * delta))
    # 던질 자리 표시 (내가 누르고 있는 동안)
    if _aim:
        var show := human != null and not human.dead and human.charging and is_playing()
        _aim.visible = show
        if show:
            var r := clampf(human.charge_time / human.charge_full_time(), 0.0, 1.0)
            var c := aim_cell(human, r)
            var p := board.center(c)
            var y := top_y(c) + 0.08 if board.height(c) > 0 else floor_y + 0.08
            _aim.global_position = Vector3(p.x, y, p.z)
            _aim.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.012))


## 밀치기는 이 게임에 없음 (밀치기 키 = 던지기)
func deliver_push(_attacker: Fighter, _target: Fighter, _impulse: Vector3, _stun: float) -> bool:
    return false


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
            elif now >= play_start_t:
                state = State.PLAYING
                state_time = 0.0
                for f in fighters:
                    f.net_pending.clear()
        State.PLAYING:
            elapsed = now - play_start_t
            state_time += delta
            _update_bombs(now)
            for f in fighters:
                if f.remote:
                    for e in f.net_pending:
                        _judge_sample(f, float(e[0]), e[1])
                    f.net_pending.clear()
                else:
                    _judge_sample(f, now, f.global_position)
            _drive_bot_ghosts(delta)
            _prune_flames(now)
            _check_end()
        State.ENDED:
            state_time += delta
    for f in fighters:
        if not f.remote:
            _record_history(f, now, f.global_position)
    if play_start_t < 0.0:
        return
    _snap_timer -= delta
    if _snap_timer <= 0.0:
        _snap_timer += 1.0 / SNAPSHOT_HZ
        var data := PackedFloat32Array()
        for f in fighters:
            var t: float = f.net_history[-1][0] if f.remote and not f.net_history.is_empty() else now
            Sync.append(data, f, t - now)
        broadcast(["snap", now, data], false)
    _ghost_timer -= delta
    if _ghost_timer <= 0.0 and not ghosts.is_empty():
        _ghost_timer += 1.0 / GHOST_HZ
        var gd := PackedFloat32Array()
        for slot in ghosts:
            gd.append(float(slot))
            gd.append(float(ghosts[slot].s))
        broadcast(["ghs", gd], false)


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
    var ok := f != null and _loaded.has(pid) and is_playing()
    match String(msg[0]):
        "loaded":
            _loaded[pid] = true
        "st":
            # 이전 라운드 화면이 보내던 상태는 버린다 (loaded 이후 + 경기 시작 이후 것만)
            if f and not f.dead and msg.size() >= 3 and _loaded.has(pid) and play_start_t > 0.0 and float(msg[1]) >= play_start_t:
                _server_receive_state(f, float(msg[1]), msg[2])
        "throw":
            if ok and not f.dead and msg.size() >= 3 and active_bombs_of(f.slot) < stat(f.slot, 0):
                var i := int(msg[1])
                var from: Vector3 = msg[2]
                var c := board.cell(i)
                if board.in_bounds(c) and not board.pillar(c) and from.distance_to(f.global_position + Vector3(0, 1.4, 0)) < 3.5 \
                        and Vector2(board.center(c).x - from.x, board.center(c).z - from.z).length() <= THROW_MAX + 2.0:
                    _create_bomb(f.slot, i, stat(f.slot, 1), false, from)
        "gh":
            if f and f.dead and ghosts.has(f.slot) and msg.size() >= 2:
                ghosts[f.slot].s = fposmod(float(msg[1]), board.ghost_len())
        "gthrow":
            if ok and f.dead and ghosts.has(f.slot) and msg.size() >= 2:
                var s := fposmod(float(msg[1]), board.ghost_len())
                ghosts[f.slot].s = s
                _ghost_throw(f.slot, s)
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
    if not f.dead and state != State.ENDED:
        _knock_out(f, -1, f.global_position)


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
    _ghost_send_timer -= delta
    if human and human.dead and ghosts.has(human.slot) and _ghost_send_timer <= 0.0:
        _ghost_send_timer = 1.0 / 15.0
        send_to_server(["gh", float(ghosts[human.slot].s)], false)

func _render_time(f: Fighter) -> float:
    return net_now() - clampf(f.net_lag + 0.05, 0.08, 0.4)


func on_server_message(msg: Array) -> void:
    if msg.is_empty():
        return
    var now := net_now()
    match String(msg[0]):
        "start":
            play_start_t = float(msg[1])
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
        "bomb":
            if not bombs.has(int(msg[1])):
                _add_bomb(int(msg[1]), int(msg[2]), int(msg[3]), msg[4], float(msg[5]), float(msg[6]), int(msg[7]), bool(msg[8]))
        "sink":
            _sink_bomb(int(msg[1]))
        "boom":
            var groups: Array = []
            for gd in msg[3]:
                var fire := {}
                var cells: PackedInt32Array = gd[0]
                var owners: PackedInt32Array = gd[1]
                for k in cells.size():
                    fire[cells[k]] = owners[k]
                groups.append({"cells": fire, "y": float(gd[2])})
            _apply_boom(msg[2], groups, msg[4], msg[5], msg[6], float(msg[1]))
        "item":
            var f := _fighter_at(int(msg[2]))
            if items.has(int(msg[1])):
                _remove_item(int(msg[1]), false)
            if f:
                _apply_item(f, int(msg[3]))
        "out":
            var f := _fighter_at(int(msg[1]))
            if f and not f.dead:
                if f.remote and msg.size() >= 4:
                    f.global_position = msg[3]
                out_info[f.slot] = [elapsed, int(msg[2])]
                _on_out(f, int(msg[2]))
        "ghs":
            var gd: PackedFloat32Array = msg[1]
            for k in range(0, gd.size() - 1, 2):
                var slot := int(gd[k])
                if ghosts.has(slot) and not (human and slot == human.slot):
                    ghosts[slot].s = gd[k + 1]
        "gcool":
            if ghosts.has(int(msg[1])):
                ghosts[int(msg[1])].cool = float(msg[2])
        "pop":
            popup_text(msg[2], String(msg[1]), msg[3])
        "knock":
            if human and not human.dead:
                human.receive_push(msg[1], float(msg[2]), _fighter_at(int(msg[3])))
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

