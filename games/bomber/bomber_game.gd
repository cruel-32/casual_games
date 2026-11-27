extends PartyGame
## [게임 모듈] 연쇄폭탄마 (격자 미로 폭탄 놓기)
## - 바닥 한 층의 격자(칸 2m) 위에서 한다. 기둥은 안 부서지고, 상자는 폭발에 부서지며 아이템이 나올 수 있다
## - 점프 키(Space·터치 점프 버튼) = 내 칸에 폭탄 놓기. 폭탄은 FUSE 초 뒤 십자로 터진다 (범위 = 불꽃 수)
##   불길은 기둥·상자·다른 폭탄·아이템에서 멈춘다. 불길이 다른 폭탄에 닿으면 그 폭탄도 바로 터진다 (연쇄)
## - 불길에 닿으면 탈락 (내 폭탄·아군 폭탄 포함). 마지막까지 남은 사람(팀전은 팀)이 승리
## - 밀치기 키(E·좌클릭) = 바로 앞 폭탄을 차서 미끄러뜨리기 (+ 다른 게임처럼 사람 밀치기)
## - 탈락하면 유령이 되어 경기장 바깥 테두리를 돌며, 폭탄 키로 안쪽에 폭탄을 던질 수 있다 (쿨타임)
## - 경기장은 좁아지지 않는다. 제한 시간이 끝나면 남은 사람끼리 무승부
##
## 온라인 (돌피하기·무궁화와 같은 구조)
## - 서버: 폭탄 설치·폭발 시각·연쇄·상자 파괴·아이템·탈락·승패를 정해 알림. 봇과 봇 유령도 서버가 움직임
## - 클라이언트: 내 캐릭터만 직접 움직여 상태를 보냄. 서버는 "그 시각의 내 위치"가 불길 칸인지로 판정
## - 맵: 시작할 때 방 정보의 씨앗값(seed)으로 모든 기기가 같은 격자를 만든다 → 이후엔 바뀐 것만 주고받음

const Board := preload("res://games/bomber/board.gd")
const BOT_BRAIN := preload("res://games/bomber/bot_brain.gd")
const HUD_SCRIPT := preload("res://games/bomber/hud.gd")
const WALL_SHADER := preload("res://shaders/arena_wall.gdshader")
const Toon := preload("res://scripts/world/toon.gd")
const Sync := preload("res://scripts/core/fighter_sync.gd")
const Teams := preload("res://scripts/core/teams.gd")
const NAME_FONT := preload("res://fonts/Jua-Regular.ttf")

# 규칙
const TIME_LIMIT := 150.0
const FUSE := 2.6                 ## 폭탄이 터지기까지 (초)
const FLAME_TIME := 0.55          ## 불길이 남아 있는 시간
const SLIDE_SPEED := 9.0          ## 찬 폭탄이 미끄러지는 속도 (m/s)
const BASE_SPEED := 4.6           ## 이동 속도 (신발 1개마다 +SPEED_STEP)
const SPEED_STEP := 0.6
const START_BOMBS := 1
const START_POWER := 2
const MAX_BOMBS := 8
const MAX_POWER := 8
const MAX_SPEED := 4
const KICK_REACH := 2.5
const GHOST_SPEED := 7.0
const GHOST_COOLDOWN := 5.0
const GHOST_POWER := 2
const GHOST_DELAY := 1.0          ## 탈락 후 유령이 되기까지
const BOMB_BOX := 1.8             ## 폭탄 충돌 상자 한 변
const FLOOR_LIFT := 0.45         ## 경기장 바닥을 땅보다 이만큼 높게 (짧게 깎인 풀이 바닥을 뚫고 보이지 않게)
const CAM_CENTER_PULL := 0.55     ## 카메라가 따라가는 점: 내 캐릭터 → 경기장 가운데 쪽으로 이만큼

const SNAPSHOT_HZ := 20.0
const SEND_HZ := 30.0
const GHOST_HZ := 10.0
const HISTORY_SEC := 1.0
const PUSH_REWIND_MAX := 0.6

## 터치 버튼 이름 (scripts/ui/touch_controls.gd 가 읽음)
var touch_jump_label := "폭탄"
var touch_push_label := "차기"
var touch_when_dead := true       ## 유령도 스틱·버튼을 씀

@export var bot_count := 5

var board: Board
var teams := 0
var floor_y := 0.0
var play_start_t := -1.0
var elapsed := 0.0
var bombs := {}                   ## id -> {id, owner, cell:int, t:폭발 시각, power, slide:[from,to,t0], ghost:bool, node, pass:[Fighter]}
var flames: Array = []            ## [{cells: {칸: 주인 slot}, t0, t1}]
var items := {}                   ## 칸 -> 아이템 종류 (바닥에 드러난 것)
var stats := {}                   ## slot -> [폭탄 수, 불꽃, 신발]
var out_info := {}                ## slot -> [탈락 시각(경기 시작부터), 범인 slot]
var ghosts := {}                  ## slot -> {s, cool (다음 던지기 가능 시각), node, target_s}
var feed: Array = []
var winner_text := ""
var human_result := ""

# 서버·오프라인
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

# 화면
var _cam_anchor: Node3D
var _ghost_cam: Node3D            ## 내 유령 (카메라 기준점이 유령과 가운데 사이를 따라감)
var _crate_bodies := {}           ## 칸 -> StaticBody3D
var _item_nodes := {}             ## 칸 -> Node3D
var _mat_bomb: Material
var _mat_fuse: Material
var _mat_spark: StandardMaterial3D
var _mat_flame: StandardMaterial3D
var _mat_flame_core: StandardMaterial3D
var _mat_crate: Material
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
    var seed_value := int(online_match.get("seed", 0)) if is_online_match() else _rng.randi()
    board.generate(entries.size(), seed_value)
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


# ================================================================ 경기장
func _build_board() -> void:
    var W := board.w
    var H := board.h
    var T := Board.TILE
    # 투명 벽 (경기장 바깥으로 밀려나가지 않게 — 테두리 기둥 바깥)
    var wall_mat := ShaderMaterial.new()
    wall_mat.shader = WALL_SHADER
    # 기둥 (테두리 포함): 몸통 하나에 상자 여러 개
    var pillars := StaticBody3D.new()
    pillars.collision_layer = 4
    pillars.collision_mask = 0
    pillars.add_to_group(&"arena_wall")
    add_child(pillars)
    var pillar_shape := BoxShape3D.new()
    pillar_shape.size = Vector3(T, 4.0, T)
    var pillar_cells: Array[Vector2i] = []
    # 바닥 (살짝 솟은 판) — 캐릭터가 이 위에 선다
    var floor_body := StaticBody3D.new()
    floor_body.collision_layer = 1
    floor_body.collision_mask = 0
    add_child(floor_body)
    var fcol := CollisionShape3D.new()
    var fshape := BoxShape3D.new()
    fshape.size = Vector3(W * T, FLOOR_LIFT + 1.0, H * T)
    fcol.shape = fshape
    floor_body.add_child(fcol)
    floor_body.global_position = Vector3(0, floor_y - (FLOOR_LIFT + 1.0) * 0.5, 0)
    for y in H:
        for x in W:
            var c := Vector2i(x, y)
            var k := board.kind(c)
            if k == Board.PILLAR:
                pillar_cells.append(c)
                var col := CollisionShape3D.new()
                col.shape = pillar_shape
                col.position = board.center(c) + Vector3(0, floor_y + 2.0, 0)
                pillars.add_child(col)
            elif k == Board.CRATE:
                _make_crate(c)
    if is_server():
        return
    # 바닥: 칸마다 두 가지 색 (체크무늬) — 격자가 잘 보이게
    var img := Image.create(W, H, false, Image.FORMAT_RGB8)
    for y in H:
        for x in W:
            img.set_pixel(x, y, Color(0.66, 0.56, 0.40) if (x + y) % 2 == 0 else Color(0.58, 0.48, 0.33))
    var tex := ImageTexture.create_from_image(img)
    var floor_mat := StandardMaterial3D.new()
    floor_mat.albedo_texture = tex
    floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    floor_mat.roughness = 1.0
    var fm := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(W * T, H * T)
    fm.mesh = plane
    fm.material_override = floor_mat
    fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(fm)
    fm.global_position = Vector3(0, floor_y + 0.005, 0)
    var side := MeshInstance3D.new()
    var sb := BoxMesh.new()
    sb.size = Vector3(W * T + 0.2, FLOOR_LIFT + 0.3, H * T + 0.2)
    side.mesh = sb
    side.material_override = Toon.make(Color(0.36, 0.3, 0.24), {"rim_strength": 0.0})
    add_child(side)
    side.global_position = Vector3(0, floor_y - (FLOOR_LIFT + 0.3) * 0.5 - 0.01, 0)
    # 기둥 모양 (한 번에 그리기)
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    var pbox := BoxMesh.new()
    pbox.size = Vector3(T, 2.0, T)
    mm.mesh = pbox
    mm.instance_count = pillar_cells.size()
    for i in pillar_cells.size():
        var c: Vector2i = pillar_cells[i]
        var border := c.x == 0 or c.y == 0 or c.x == W - 1 or c.y == H - 1
        mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.25 if border else 1.0, 1)),
                board.center(c) + Vector3(0, floor_y + (1.25 if border else 1.0), 0)))
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = Toon.make(Color(0.30, 0.33, 0.44), {"rim_strength": 0.2})
    add_child(mmi)
    # 기둥 위 작은 뚜껑 (기둥과 상자를 한눈에 구분)
    var mm2 := MultiMesh.new()
    mm2.transform_format = MultiMesh.TRANSFORM_3D
    var cap := BoxMesh.new()
    cap.size = Vector3(T * 0.8, 0.12, T * 0.8)
    mm2.mesh = cap
    mm2.instance_count = pillar_cells.size()
    for i in pillar_cells.size():
        var c: Vector2i = pillar_cells[i]
        var border := c.x == 0 or c.y == 0 or c.x == W - 1 or c.y == H - 1
        mm2.set_instance_transform(i, Transform3D(Basis.IDENTITY, board.center(c) + Vector3(0, floor_y + (2.5 if border else 2.0) + 0.06, 0)))
    var mmi2 := MultiMeshInstance3D.new()
    mmi2.multimesh = mm2
    mmi2.material_override = Toon.make(Color(0.42, 0.46, 0.6), {"rim_strength": 0.1})
    add_child(mmi2)
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
    _make_materials()


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
    if _mat_debris == null:
        _mat_debris = Toon.make(Color(0.52, 0.28, 0.10), {"rim_strength": 0.0})
    _flame_mesh = BoxMesh.new()
    _flame_mesh.size = Vector3(1.7, 1.6, 1.7)
    _flame_core_mesh = SphereMesh.new()
    _flame_core_mesh.radius = 0.75
    _flame_core_mesh.height = 1.5


func _make_crate(c: Vector2i) -> void:
    var body := StaticBody3D.new()
    body.collision_layer = 4
    body.collision_mask = 0
    body.add_to_group(&"arena_wall")
    add_child(body)
    body.global_position = board.center(c) + Vector3(0, floor_y, 0)
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(Board.TILE, 4.0, Board.TILE)
    col.shape = shape
    col.position.y = 2.0
    body.add_child(col)
    _crate_bodies[board.idx(c)] = body
    if is_server():
        return
    if _mat_crate == null:
        _mat_crate = Toon.make(Color(0.80, 0.46, 0.18), {"rim_strength": 0.2})
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(1.84, 1.6, 1.84)
    mi.mesh = bm
    mi.material_override = _mat_crate
    mi.position.y = 0.8
    body.add_child(mi)
    # 나무 띠 (가로 두 줄) — 상자처럼 보이게
    if _mat_debris == null:
        _mat_debris = Toon.make(Color(0.52, 0.28, 0.10), {"rim_strength": 0.0})
    for yy in [0.35, 1.25]:
        var band := MeshInstance3D.new()
        var b2 := BoxMesh.new()
        b2.size = Vector3(1.9, 0.18, 1.9)
        band.mesh = b2
        band.material_override = _mat_debris
        band.position.y = yy
        body.add_child(band)


func _remove_crate(i: int) -> void:
    board.cells[i] = Board.EMPTY
    var body: Node3D = _crate_bodies.get(i)
    _crate_bodies.erase(i)
    if body == null:
        return
    if is_server():
        body.queue_free()
        return
    var pos := body.global_position
    body.queue_free()
    Sfx.play_at("crate_break", pos, self)
    # 나무 조각이 튄다
    for k in 6:
        var d := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.35, 0.2, 0.5)
        d.mesh = bm
        d.material_override = _mat_debris
        add_child(d)
        d.global_position = pos + Vector3(randf_range(-0.6, 0.6), 0.9, randf_range(-0.6, 0.6))
        var to := d.global_position + Vector3(randf_range(-1.6, 1.6), randf_range(0.6, 1.8), randf_range(-1.6, 1.6))
        var tw := create_tween()
        tw.set_parallel(true)
        tw.tween_property(d, "global_position", to, 0.35).set_ease(Tween.EASE_OUT)
        tw.tween_property(d, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.6)
        tw.chain().tween_property(d, "global_position:y", pos.y + 0.1, 0.3).set_ease(Tween.EASE_IN)
        tw.chain().tween_property(d, "scale", Vector3.ZERO, 0.3)
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
        f.can_jump = false
        f.move_speed = BASE_SPEED
        var c: Vector2i = board.spawns[int(spots[i])]
        var p := board.center(c)
        f.position = Vector3(p.x, floor_y + 0.2, p.z)
        f.rotation.y = atan2(p.x, p.z)          # 가운데를 바라봄 (얼굴 = -Z)
        stats[i] = [START_BOMBS, START_POWER, 0]
        if not f.is_human and not f.remote:
            var brain := BOT_BRAIN.new()
            brain.game = self
            f.add_child(brain)
        add_child(f)
        f.collision_mask = 1 | 4          # 사람끼리는 통과 (좁은 1칸 길에서 마주치면 서로 막혀 꼼짝 못 하므로)
        fighters.append(f)
        if f.is_human:
            human = f
            _setup_camera(f)


## 기본 카메라: 높이서 멀리 내려다봄 (경기장 전체가 거의 다 보이게). 마우스·터치로 돌리고, 휠로 당기거나 밀 수 있다
##   카메라는 내 캐릭터와 경기장 가운데 사이의 한 점(_cam_anchor)을 따라간다 → 내가 구석에 있어도 경기장이 화면에 들어옴
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
    var c := Vector3(0, floor_y, 0)
    return f.global_position.lerp(c, CAM_CENTER_PULL) - Vector3(0, 1.3, 0)


func alive_list() -> Array[Fighter]:
    return alive_fighters()


func stat(slot: int, k: int) -> int:
    return int(stats[slot][k]) if stats.has(slot) else 0


# ================================================================ 폭탄
func now_t() -> float:
    return net_now()


## 폭탄의 지금 칸 (미끄러지는 중이면 그 시각의 칸)
func bomb_cell(b: Dictionary, t: float) -> int:
    var sl: Array = b.slide
    if sl.is_empty():
        return int(b.cell)
    var from := board.cell(int(sl[0]))
    var to := board.cell(int(sl[1]))
    var dist := absi(to.x - from.x) + absi(to.y - from.y)
    var k := clampi(int((t - float(sl[2])) * SLIDE_SPEED / Board.TILE + 0.5), 0, dist)
    var dir := (to - from) / maxi(dist, 1)
    return board.idx(from + dir * k)


func bomb_world(b: Dictionary, t: float) -> Vector3:
    var sl: Array = b.slide
    if sl.is_empty():
        return board.center(board.cell(int(b.cell)))
    var a := board.center(board.cell(int(sl[0])))
    var z := board.center(board.cell(int(sl[1])))
    var len := a.distance_to(z)
    if len < 0.01:
        return z
    var d := clampf((t - float(sl[2])) * SLIDE_SPEED, 0.0, len)
    return a.lerp(z, d / len)


## 칸에 있는 폭탄 id (없으면 -1)
func bomb_at(i: int, t: float = -1.0) -> int:
    if t < 0.0:
        t = net_now()
    for id in bombs:
        if bomb_cell(bombs[id], t) == i:
            return int(id)
    return -1


func active_bombs_of(slot: int, ghost: bool = false) -> int:
    var n := 0
    for id in bombs:
        var b: Dictionary = bombs[id]
        if int(b.owner) == slot and bool(b.ghost) == ghost:
            n += 1
    return n


## 폭탄을 놓을 수 있는 칸인가
func can_place_at(i: int) -> bool:
    var c := board.cell(i)
    return board.in_bounds(c) and not board.solid(c) and bomb_at(i) < 0


## 서버·오프라인: 폭탄 만들기. from_s >= 0 이면 유령이 던진 것 (화면 연출용)
func _create_bomb(owner: int, i: int, power: int, ghost: bool, from_s: float = -1.0) -> void:
    var id := _next_bomb_id
    _next_bomb_id += 1
    var t := net_now() + FUSE
    _add_bomb(id, owner, i, t, power, ghost, from_s)
    # 미끄러지는 폭탄의 길을 막으면 그 앞에서 멈춘다
    for oid in bombs:
        var b: Dictionary = bombs[oid]
        if int(oid) == id or b.slide.is_empty():
            continue
        _truncate_slide(b, i)
    if is_server():
        broadcast(["bomb", id, owner, i, t, power, ghost, from_s])


func _add_bomb(id: int, owner: int, i: int, t: float, power: int, ghost: bool, from_s: float) -> void:
    var b := {"id": id, "owner": owner, "cell": i, "t": t, "power": power, "slide": [], "ghost": ghost, "node": null, "pass": []}
    bombs[id] = b
    var body := StaticBody3D.new()
    body.collision_layer = 4
    body.collision_mask = 0
    add_child(body)
    var p := board.center(board.cell(i))
    body.global_position = Vector3(p.x, floor_y, p.z)
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(BOMB_BOX, 3.0, BOMB_BOX)
    col.shape = shape
    col.position.y = 1.5
    body.add_child(col)
    b.node = body
    # 폭탄 위에 서 있던 사람(내가 움직이는 캐릭터)은 그 칸을 벗어날 때까지 통과
    for f in fighters:
        if f.remote or f.dead:
            continue
        if _overlaps_bomb(f, body.global_position):
            f.add_collision_exception_with(body)
            b.pass.append(f)
    if is_server():
        return
    var vis := Node3D.new()
    vis.name = "Vis"
    body.add_child(vis)
    var ball := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.62
    sm.height = 1.24
    ball.mesh = sm
    ball.material_override = _mat_bomb
    ball.position.y = 0.62
    vis.add_child(ball)
    var fuse := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 0.07
    cm.bottom_radius = 0.09
    cm.height = 0.35
    fuse.mesh = cm
    fuse.material_override = _mat_fuse
    fuse.position = Vector3(0, 1.36, 0)
    fuse.rotation.z = 0.3
    vis.add_child(fuse)
    var spark := MeshInstance3D.new()
    var sp := SphereMesh.new()
    sp.radius = 0.13
    sp.height = 0.26
    spark.mesh = sp
    spark.material_override = _mat_spark
    spark.position = Vector3(-0.07, 1.55, 0)
    spark.name = "Spark"
    vis.add_child(spark)
    # 주인 색 띠 (누구 폭탄인지)
    var ring := MeshInstance3D.new()
    var tm := TorusMesh.new()
    tm.inner_radius = 0.55
    tm.outer_radius = 0.68
    ring.mesh = tm
    var oc: Color = fighters[owner].body_color if owner >= 0 and owner < fighters.size() else Color.WHITE
    ring.material_override = Toon.make(oc, {"rim_strength": 0.0})
    ring.position.y = 0.62
    vis.add_child(ring)
    if from_s >= 0.0:
        # 유령이 던짐: 바깥에서 포물선으로 날아옴
        var start := board.ghost_pos(from_s) + Vector3(0, floor_y + 1.6, 0)
        vis.top_level = true
        vis.global_position = start
        var end := body.global_position
        var tw := create_tween()
        tw.tween_method(_arc.bind(vis, start, end), 0.0, 1.0, 0.5)
        tw.tween_callback(_land.bind(vis))
        Sfx.play_at("ghost_throw", start, self)
    else:
        Sfx.play_at("bomb_place", body.global_position, self)


func _arc(k: float, vis: Variant, start: Vector3, end: Vector3) -> void:
    if is_instance_valid(vis):
        (vis as Node3D).global_position = start.lerp(end, k) + Vector3(0, sin(k * PI) * 4.0, 0)


func _land(vis: Variant) -> void:
    if is_instance_valid(vis):
        (vis as Node3D).top_level = false
        (vis as Node3D).position = Vector3.ZERO


func _overlaps_bomb(f: Fighter, center: Vector3) -> bool:
    var lim := BOMB_BOX * 0.5 + Fighter.RADIUS - 0.02
    return absf(f.global_position.x - center.x) < lim and absf(f.global_position.z - center.z) < lim


func _truncate_slide(b: Dictionary, blocked_i: int) -> void:
    var sl: Array = b.slide
    var from := board.cell(int(sl[0]))
    var to := board.cell(int(sl[1]))
    var dist := absi(to.x - from.x) + absi(to.y - from.y)
    if dist == 0:
        return
    var dir := (to - from) / dist
    var cur := board.cell(bomb_cell(b, net_now()))
    var c := cur
    while c != to:
        var n: Vector2i = c + dir
        if board.idx(n) == blocked_i:
            b.slide = [sl[0], board.idx(c), sl[2]]
            if is_server():
                broadcast(["slide", int(b.id), int(sl[0]), board.idx(c), float(sl[2])])
            return
        c = n


## 폭탄 차기: 미끄러질 수 있는 끝 칸을 정해 알림 (서버·오프라인)
func _do_kick(id: int, dir: Vector2i) -> void:
    if not bombs.has(id):
        return
    var b: Dictionary = bombs[id]
    if not b.slide.is_empty():
        return
    var t := net_now()
    var from := board.cell(int(b.cell))
    var to := from
    var n: Vector2i = from + dir
    while board.in_bounds(n) and not board.solid(n) and bomb_at(board.idx(n), t) < 0 and not _fighter_in_cell(n) and not items.has(board.idx(n)):
        to = n
        n += dir
    if to == from:
        return
    b.slide = [board.idx(from), board.idx(to), t]
    if is_server():
        broadcast(["slide", id, board.idx(from), board.idx(to), t])
    else:
        Sfx.play_at("kick", board.center(from) + Vector3(0, floor_y, 0), self)


func _fighter_in_cell(c: Vector2i) -> bool:
    for f in fighters:
        if not f.dead and board.cell_at(f.global_position) == c:
            return true
    return false


## 시간이 된 폭탄 터뜨리기 + 불길 속에 들어간 폭탄은 바로 (서버·오프라인)
func _update_bombs(now: float) -> void:
    var due: Array = []
    for id in bombs:
        var b: Dictionary = bombs[id]
        if float(b.t) <= now or _flame_hit(bomb_cell(b, now), now):
            due.append(int(id))
    if not due.is_empty():
        _explode(due, now)


## 연쇄 폭발 처리 → 알림
func _explode(ids: Array, now: float) -> void:
    var queue: Array = ids.duplicate()
    var done := {}
    var fire := {}            # 칸 -> 주인
    var crates := {}
    var burned := {}
    while not queue.is_empty():
        var id: int = queue.pop_front()
        if done.has(id) or not bombs.has(id):
            continue
        done[id] = true
        var b: Dictionary = bombs[id]
        var ci := bomb_cell(b, now)
        b.cell = ci
        b.slide = []
        var owner := int(b.owner)
        var res := board.blast(board.cell(ci), int(b.power), func(c: Vector2i) -> bool:
            var i := board.idx(c)
            return items.has(i) or (bomb_at(i, now) >= 0 and not done.has(bomb_at(i, now))))
        for c: Vector2i in res[0]:
            var i := board.idx(c)
            if not fire.has(i):
                fire[i] = owner
            var other := bomb_at(i, now)
            if other >= 0 and not done.has(other):
                queue.append(other)
            if items.has(i):
                burned[i] = true
        for c: Vector2i in res[1]:
            crates[board.idx(c)] = true
    _apply_boom(done.keys(), fire, crates.keys(), burned.keys(), now)
    if is_server():
        var cells := PackedInt32Array()
        var owners := PackedInt32Array()
        for i in fire:
            cells.append(int(i))
            owners.append(int(fire[i]))
        broadcast(["boom", now, PackedInt32Array(done.keys()), cells, owners, PackedInt32Array(crates.keys()), PackedInt32Array(burned.keys())])


## 폭발 결과 반영 (모든 기기)
func _apply_boom(ids: Array, fire: Dictionary, crate_cells: Array, burned: Array, t: float) -> void:
    for id in ids:
        var b: Dictionary = bombs.get(int(id), {})
        if b.is_empty():
            continue
        if is_instance_valid(b.node):
            for f: Fighter in b.pass:
                if is_instance_valid(f):
                    f.remove_collision_exception_with(b.node)
            b.node.queue_free()
        bombs.erase(int(id))
    for i in burned:
        _remove_item(int(i), true)
    for i in crate_cells:
        _remove_crate(int(i))
        if board.crate_item.has(int(i)):
            _add_item(int(i), int(board.crate_item[int(i)]))
    flames.append({"cells": fire, "t0": t, "t1": t + FLAME_TIME})
    if not is_server():
        _show_flames(fire)
        var center := Vector3.ZERO
        for i in fire:
            center += board.center(board.cell(int(i)))
        center /= maxf(fire.size(), 1.0)
        Sfx.play_at("boom", center + Vector3(0, floor_y, 0), self, minf(ids.size() - 1, 4) * 1.0)
        if human and not human.dead:
            var d := human.global_position.distance_to(center + Vector3(0, floor_y, 0))
            human.shake = maxf(human.shake, clampf(1.0 - d / 18.0, 0.0, 1.0) * (0.5 + 0.15 * ids.size()))
        elif human and human.camera:
            human.shake = maxf(human.shake, 0.3)


func _show_flames(fire: Dictionary) -> void:
    for i in fire:
        var p := board.center(board.cell(int(i))) + Vector3(0, floor_y, 0)
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
        # 그을음 (잠깐 남음)
        var s := MeshInstance3D.new()
        var pm := PlaneMesh.new()
        pm.size = Vector2(1.7, 1.7)
        s.mesh = pm
        var sm := StandardMaterial3D.new()
        sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        sm.albedo_color = Color(0.1, 0.08, 0.06, 0.45)
        s.material_override = sm
        s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(s)
        s.global_position = p + Vector3(0, 0.035, 0)
        var tw2 := create_tween()
        tw2.tween_interval(1.2)
        tw2.tween_property(sm, "albedo_color:a", 0.0, 1.5)
        tw2.tween_callback(s.queue_free)


## 불길이 그 시각에 그 칸에 있으면 주인 slot, 없으면 -2
func _in_flame(i: int, t: float) -> int:
    for fl in flames:
        if t >= float(fl.t0) and t < float(fl.t1) and fl.cells.has(i):
            return int(fl.cells[i])
    return -2


func _flame_hit(i: int, t: float) -> bool:
    return _in_flame(i, t) > -2


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
    root.global_position = board.center(board.cell(i)) + Vector3(0, floor_y + 0.7, 0)
    var colr := [Color(1.0, 0.45, 0.15), Color(0.25, 0.25, 0.32), Color(0.3, 0.7, 1.0)][kind] as Color
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.95, 0.95, 0.95)
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
## 위치 하나로 판정: 불길·아이템
func _judge_sample(f: Fighter, t: float, pos: Vector3) -> void:
    if f.dead or _ended or play_start_t < 0.0 or t < play_start_t:
        return
    var i := board.idx(board.cell_at(pos))
    var who := _in_flame(i, t)
    if who > -2:
        _knock_out(f, who, pos)
        return
    if items.has(i):
        _pick_item(f, i)


func _knock_out(f: Fighter, killer: int, pos: Vector3) -> void:
    out_info[f.slot] = [maxf(net_now() - play_start_t, 0.0), killer]
    if is_server():
        broadcast(["out", f.slot, killer, pos])
    _on_out(f, killer)


func _on_out(f: Fighter, killer: int) -> void:
    if not f.remote and not f.dead:
        f.velocity.y = 7.0
        var c := board.center(board.cell_at(f.global_position))
        var away := Vector3(f.global_position.x - c.x, 0, f.global_position.z - c.z)
        f.knock = (away.normalized() if away.length() > 0.05 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()) * 3.0
    f.die()
    var kname := ""
    if killer == f.slot:
        kname = "자폭"
    elif killer >= 0 and killer < fighters.size():
        kname = fighters[killer].display_name + "의 폭탄"
    var text := "%s 탈락%s" % [f.display_name, (" (" + kname + ")") if kname != "" else ""]
    _feed(text, Color(1.0, 0.5, 0.45) if f == human else Color(0.9, 0.9, 0.9))
    if f == human:
        human_result = "탈락 — " + (kname if kname != "" else "불길에 닿았어요") + " · 유령이 되어 밖에서 폭탄을 던질 수 있어요"
    if not is_server():
        popup_text(f.global_position + Vector3(0, 2.4, 0), "펑!", Color(1.0, 0.55, 0.25))
        # 쓰러진 몸은 잠시 뒤 사라지고 유령이 된다
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


# ================================================================ 입력 훅 (Fighter 가 부름)
## 점프 키 = 폭탄 놓기 (내가 움직이는 캐릭터: 사람·봇)
func on_action(f: Fighter) -> void:
    if f.dead or not is_playing():
        return
    var i := board.idx(board.cell_at(f.global_position))
    if is_client():
        if f == human and active_bombs_of(f.slot) < stat(f.slot, 0) and can_place_at(i):
            send_to_server(["place", i])
        return
    _try_place(f, i)


func _try_place(f: Fighter, i: int) -> void:
    if f.dead or not is_playing() or not can_place_at(i):
        return
    if active_bombs_of(f.slot) >= stat(f.slot, 0):
        return
    _create_bomb(f.slot, i, stat(f.slot, 1), false)


## 밀치기를 했다 → 바로 앞 폭탄 차기
func on_push_released(f: Fighter) -> void:
    if f.remote or f.dead or not is_playing():
        return
    var fwd := f.facing()
    var dir := Vector2i(int(signf(fwd.x)), 0) if absf(fwd.x) >= absf(fwd.z) else Vector2i(0, int(signf(fwd.z)))
    var c := board.cell_at(f.global_position)
    for k in [1, 0]:
        var id := bomb_at(board.idx(c + dir * k))
        if id < 0:
            continue
        var b: Dictionary = bombs[id]
        if not b.slide.is_empty():
            continue
        var bp := bomb_world(b, net_now()) + Vector3(0, floor_y, 0)
        var to := bp - f.global_position
        to.y = 0.0
        if to.length() > KICK_REACH or (k == 1 and to.normalized().dot(fwd) < 0.5):
            continue
        if is_client():
            send_to_server(["kick", id, Board.DIRS.find(dir)])
            Sfx.play_at("kick", bp, self)
        else:
            _do_kick(id, dir)
        return


## 이동 보정: 격자 모퉁이에 살짝 걸리면 열린 쪽으로 미끄러지고, 길 가운데로 맞춰 준다
func adjust_move(f: Fighter, d: Vector3) -> Vector3:
    var m := d.length()
    if m < 0.05 or board == null:
        return d
    var p := f.global_position
    var c := board.cell_at(p)
    var ctr := board.center(c)
    var off := Vector2(p.x - ctr.x, p.z - ctr.z)
    var along_x := absf(d.x) >= absf(d.z)
    var s_main := int(signf(d.x if along_x else d.z))
    var lateral := off.y if along_x else off.x
    var ahead := c + (Vector2i(s_main, 0) if along_x else Vector2i(0, s_main))
    if _walkable_for(f, ahead):
        # 열린 길: 가운데 줄로 끌어당김 (옆으로 많이 누를 땐 그대로)
        var side := d.z if along_x else d.x
        var main := d.x if along_x else d.z
        if absf(lateral) > 0.06 and absf(side) < absf(main) * 0.6:
            var pull := clampf(-lateral * 2.5, -0.8, 0.8) * absf(main)
            d = Vector3(main, 0, pull) if along_x else Vector3(pull, 0, main)
            d = d.normalized() * m
        return d
    # 막힘: 비껴 선 쪽 칸이 열려 있으면 그쪽으로 미끄러짐
    if absf(lateral) > 0.12:
        var s_side := int(signf(lateral))
        var side_cell := c + (Vector2i(0, s_side) if along_x else Vector2i(s_side, 0))
        var diag := side_cell + (Vector2i(s_main, 0) if along_x else Vector2i(0, s_main))
        if _walkable_for(f, side_cell) and _walkable_for(f, diag):
            return (Vector3(0, 0, s_side) if along_x else Vector3(s_side, 0, 0)) * m
    return d


func _walkable_for(f: Fighter, c: Vector2i) -> bool:
    if not board.in_bounds(c) or board.solid(c):
        return false
    var id := bomb_at(board.idx(c))
    if id >= 0 and not (bombs[id].pass as Array).has(f):
        return false
    return true


## 폭탄 통과 해제: 폭탄 칸에서 벗어나면 다시 막힘
func _update_bomb_pass(now: float) -> void:
    for id in bombs:
        var b: Dictionary = bombs[id]
        if not is_instance_valid(b.node):
            continue
        var wp := bomb_world(b, now)
        (b.node as Node3D).global_position = Vector3(wp.x, floor_y, wp.z)
        var keep: Array = []
        for f: Fighter in b.pass:
            if not is_instance_valid(f):
                continue
            if _overlaps_bomb(f, b.node.global_position) and not f.dead:
                keep.append(f)
            else:
                f.remove_collision_exception_with(b.node)
        b.pass = keep


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
    root.global_position = board.ghost_pos(s) + Vector3(0, floor_y + 1.2, 0)
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
func _drive_my_ghost(delta: float) -> void:
    if human == null or not ghosts.has(human.slot) or not is_playing():
        return
    var g: Dictionary = ghosts[human.slot]
    var tan := board.ghost_tangent(float(g.s))
    var mv := human.intent_move
    g.s = fposmod(float(g.s) + mv.dot(tan) * GHOST_SPEED * delta, board.ghost_len())
    if human.intent_jump:
        human.intent_jump = false
        if ghost_cooldown_left(human.slot) <= 0.0:
            if is_client():
                send_to_server(["throw", float(g.s)])
                g.cool = net_now() + 0.4         # 서버 답을 기다리는 동안 연타 막기
            else:
                _ghost_throw(human.slot, float(g.s))


## 서버·오프라인: 유령 던지기
func _ghost_throw(slot: int, s: float) -> void:
    if not ghosts.has(slot) or not is_playing():
        return
    var g: Dictionary = ghosts[slot]
    if net_now() < float(g.cool) or active_bombs_of(slot, true) > 0:
        return
    var c := board.ghost_target(s, func(tc: Vector2i) -> bool: return can_place_at(board.idx(tc)))
    if c.x < 0:
        return
    g.cool = net_now() + GHOST_COOLDOWN
    if is_server():
        broadcast(["gcool", slot, float(g.cool)])
    _create_bomb(slot, board.idx(c), GHOST_POWER, true, s)


## 봇 유령: 가장 가까운 상대 쪽으로 테두리를 돌다가 던짐
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
        var goal := board.ghost_pos(float(g.s)) + Vector3(0, floor_y + 1.2 + sin(t * 2.5 + slot) * 0.15, 0)
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
            _update_bomb_pass(net_now())
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
    _update_bomb_pass(now)
    _update_ghost_nodes(delta)


func _process(delta: float) -> void:
    if is_server():
        return
    if _cam_anchor and human:
        if not human.dead:
            _cam_anchor.global_position = _anchor_goal(human)
        elif is_instance_valid(_ghost_cam):
            _cam_anchor.global_position = _ghost_cam.global_position.lerp(Vector3(0, floor_y, 0), 0.7) - Vector3(0, 1.3, 0)
    var t := net_now()
    for id in bombs:
        var b: Dictionary = bombs[id]
        if not is_instance_valid(b.node):
            continue
        var vis: Node3D = b.node.get_node_or_null("Vis")
        if vis == null or vis.top_level:
            continue
        var left := float(b.t) - t
        var rate := lerpf(16.0, 4.0, clampf(left / FUSE, 0.0, 1.0))
        var pulse := 1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.001 * rate) + clampf(0.6 - left, 0.0, 0.6) * 0.35
        vis.scale = Vector3.ONE * pulse
        var spark: Node3D = vis.get_node_or_null("Spark")
        if spark:
            spark.scale = Vector3.ONE * randf_range(0.7, 1.4)
    for i in _item_nodes:
        var n: Node3D = _item_nodes[i]
        if is_instance_valid(n):
            n.rotation.y += delta * 1.6
            n.position.y = floor_y + 0.7 + sin(Time.get_ticks_msec() * 0.003 + int(i)) * 0.12


# ================================================================ 밀치기 (돌피하기와 같은 방식)
func deliver_push(attacker: Fighter, target: Fighter, impulse: Vector3, stun: float) -> bool:
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
    _update_bomb_pass(now)
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
        "place":
            if ok and not f.dead and msg.size() >= 2:
                var i := int(msg[1])
                var c := board.cell(i)
                var mine := board.cell_at(f.global_position)
                if absi(c.x - mine.x) <= 1 and absi(c.y - mine.y) <= 1:
                    _try_place(f, i)
        "kick":
            if ok and not f.dead and msg.size() >= 3 and bombs.has(int(msg[1])):
                var d := int(msg[2])
                var b: Dictionary = bombs[int(msg[1])]
                var bp := bomb_world(b, net_now()) + Vector3(0, floor_y, 0)
                if d >= 0 and d < 4 and bp.distance_to(f.global_position) <= KICK_REACH + 1.2:
                    _do_kick(int(msg[1]), Board.DIRS[d])
        "gh":
            if f and f.dead and ghosts.has(f.slot) and msg.size() >= 2:
                ghosts[f.slot].s = fposmod(float(msg[1]), board.ghost_len())
        "throw":
            if ok and f.dead and ghosts.has(f.slot) and msg.size() >= 2:
                var s := fposmod(float(msg[1]), board.ghost_len())
                ghosts[f.slot].s = s
                _ghost_throw(f.slot, s)
        "push":
            if f and msg.size() >= 7 and ok:
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
    if t == a or t.dead:
        return
    var now := net_now()
    if apos.distance_to(a.global_position) > 3.0:
        return
    if tt < now - PUSH_REWIND_MAX or not _near_history(t, tt, tpos, 1.5):
        return
    if apos.distance_to(tpos) > a.push_reach + 1.2:
        return
    var hv := Vector3(impulse.x, 0.0, impulse.z).limit_length(Fighter.PUSH_FORCE * a.glove_force_mult() + 1.0)
    _apply_push(t, Vector3(hv.x, clampf(impulse.y, 0.0, 6.0), hv.z), clampf(stun, 0.0, Fighter.STUN_MAX), a)


func _near_history(f: Fighter, t: float, pos: Vector3, tol: float) -> bool:
    if f.net_history.is_empty():
        return f.global_position.distance_to(pos) <= tol * 2.0
    for hh in f.net_history:
        if absf(float(hh[0]) - t) <= 0.2 and (hh[1] as Vector3).distance_to(pos) <= tol:
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
                _add_bomb(int(msg[1]), int(msg[2]), int(msg[3]), float(msg[4]), int(msg[5]), bool(msg[6]), float(msg[7]))
        "slide":
            if bombs.has(int(msg[1])):
                var b: Dictionary = bombs[int(msg[1])]
                var fresh: bool = b.slide.is_empty()
                b.slide = [int(msg[2]), int(msg[3]), float(msg[4])]
                if fresh and is_instance_valid(b.node):
                    Sfx.play_at("kick", b.node.global_position, self, -4.0)
        "boom":
            var fire := {}
            var cells: PackedInt32Array = msg[3]
            var owners: PackedInt32Array = msg[4]
            for k in cells.size():
                fire[cells[k]] = owners[k]
            var ids: Array = []
            for id in (msg[2] as PackedInt32Array):
                ids.append(int(id))
            var crates: Array = []
            for i in (msg[5] as PackedInt32Array):
                crates.append(int(i))
            var burned: Array = []
            for i in (msg[6] as PackedInt32Array):
                burned.append(int(i))
            _apply_boom(ids, fire, crates, burned, float(msg[1]))
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
