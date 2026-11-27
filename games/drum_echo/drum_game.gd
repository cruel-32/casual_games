extends PartyGame
## 뒷북의 달인 — 가면 쓴 진행자가 북으로 리듬을 선창하면, 모든 플레이어가 똑같이 따라 친다
##
## 진행 (chart.gd): 반주가 흐르는 동안 [쉼 2박] 진행자 선창 N마디 [텀] 모두 따라 치기 N마디 를 되풀이 (1마디 6번 → 2마디 6번)
##   진행자 리듬은 반주에 맞는 리듬 모음에서 고른다 (진행할수록 어렵게). 선창과 따라 치기 사이 텀은 4박 → 0박으로 점점 짧아짐
##   따라 치기: 같은 노트를 같은 타이밍에 → PERFECT·GOOD·BAD·MISS (피버 = 누르고 있다가 끝 박자에 뗌, 누름·뗌 각각 판정)
##   곡이 끝나면 팀원 점수 합계(개인전은 개인 점수)로 순위
##
## 판정은 각 플레이어 기기에서 한다 (박자에 민감한 리듬 게임이라 네트워크를 거치지 않게). 서버는 결과만 받아 점수에 반영하고 알린다
## 시간: 화면(노트 길)·판정은 '귀에 들리는 반주 시각'(heard_time) 하나로 맞춘다 — 반주를 기준 시계로 쓰고 소리 출력 지연을 뺀다.
##   효과음 예약은 '지금 섞이는 시각'(mix_time) 기준.
## 메시지 (서버 → 모두)
##   ["start", t0, teams, song_id]        곡 시작 시각(서버 시계)·곡 (Chart.SONGS)
##   ["turn", i, -1, notes]               i번째 차례 진행자 리듬 (쉼 전에 미리)
##   ["j", fighter_slot, judge, lane]     따라 치기 판정 (머리 위 문구만, 소리 없음). lane +2 = 피버 뗌
##   ["k", slot, lane, 1|0]               누름·뗌 — 그 사람 캐릭터가 바로 북을 친다 (판정과 상관없이 누르면 움직임)
##   ["tres", i, {slot: [점수, p, g, b, m]}]  차례 결과 (봇·놓친 노트 포함)
##   ["score", {slot: 총점}]
##   ["end", {slot: 총점}, rank, winner_text]
## 메시지 (클라이언트 → 서버): ["loaded"], 판정 결과 ["res"|"resrel", ...] (_apply_result), ["key", lane, 1|0] 누름·뗌

const Chart := preload("res://games/drum_echo/chart.gd")
const HUD_SCRIPT := preload("res://games/drum_echo/drum_hud.gd")
const Teams := preload("res://scripts/core/teams.gd")
const Toon := preload("res://scripts/world/toon.gd")

const LOAD_WAIT_MAX := 10.0
const START_DELAY := 3.0            ## 모두 준비되고 곡이 시작하기까지
const BOT_SKILL := 0.55
const BOT_COLORS := Fighter.SLOT_COLORS
const SND := {"don": preload("res://audio/drum/don.wav"), "ka": preload("res://audio/drum/ka.wav"),
        "cue": preload("res://audio/drum/cue.wav"), "miss": preload("res://audio/drum/miss.wav")}
const MaskedHost := preload("res://scripts/world/masked_host.gd")
## 북 색: 팀 색(빨강·파랑·초록·노랑)과 헷갈리지 않게 주황(둥)·보라(딱)
const DON_COLOR := Color(0.96, 0.56, 0.16)
const KA_COLOR := Color(0.60, 0.36, 0.86)
const FEVER_COLOR := Color(1.0, 0.82, 0.2)
const MUSIC_DB := 2.0
const ROLL_DB := -9.0

@export var bot_count := 3          ## 혼자 연습: 나 + 봇 3 (2팀)

var teams := 0
var my_slot := -1
var t0 := -1.0                      ## 곡 시작 (서버 시계). -1 = 아직
var song_id := Chart.DEFAULT_SONG  ## 이번 경기 곡 (서버·오프라인이 고르고 "start" 로 알림)
static var _last_song := ""         ## 바로 전 경기 곡 (연달아 같은 곡이 안 나오게)
var turns: Array = []               ## Chart.build_turns
var _roll_step := 0.125             ## 피버를 누르고 있는 동안 '드르륵' 간격 (곡의 16분음표)
var end_time := 0.0
## 화면용 (모든 PC)
var view_notes := {}                ## turn -> [[slot, lane, end], ...]
var view_attacker := {}             ## turn -> fighter slot (-1 = 진행자)
var view_final := {}                ## turn -> true (따라 칠 노트 확정)
var view_taken := {}                ## turn -> {note index: judge, -(index+1): 피버 뗌 판정} 내가 맞힌 노트
var view_hold := {}                 ## lane -> [turn, note index] 내가 피버를 누르고 있는 중
var scores := {}                    ## fighter slot -> 총점
var final_rank: Array = []          ## 끝난 뒤 [{name, score, team, rank}]
var last_judge := ""                ## 내 마지막 판정 (HUD)
var last_judge_time := -10.0
var winner_text := ""

# 판정 (서버·오프라인)
var _auth := {}                     ## turn -> {attacker(-1), notes, rhold:{slot:{lane: idx}}, taken:{slot:{key:judge}}, fixed}
var _loaded := {}
var _wait_time := 0.0
var _slot_of_peer := {}
var _announced := -1
var _finalized := -1
var _ended := false

# 화면
var _camera: Camera3D
var _drums := {}                    ## slot -> [left mesh, right mesh]
var _music: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _bot_hits: Array = []           ## [[song_time, fighter slot, lane, db, played, roll_until]] 봇·진행자·남의 공격 예약
var _pop_labels := {}               ## slot -> Label3D 머리 위 판정 글자 (한 사람에 하나)
var _popups: Array = []             ## [[song_time, fighter slot, judge]] 봇 판정 글자 (노트 시각에 머리 위)
var _rolls: Array = []              ## [{who, lane, until, next, db}] 피버 '드르륵' (until -1 = 키를 떼면 끝)
var _attack_mark: Label3D
var _key_down := [false, false]
var _press_t := [0.0, 0.0]
var _real_prev := -1
var _mats := {}                     ## 북 재질 (모두 같이 씀 → 그리기 묶음)
var _vsync_before := -1
# 진행자
var _hosts: Array = []              ## [가운데(북 치는) 진행자, 왼쪽, 오른쪽]
var _host_drums: Array = []
# 카메라
var _group_center := {}             ## team(개인전 0) -> 무대 위 무리 가운데
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _overview_pos := Vector3.ZERO
var _overview_look := Vector3.ZERO
# 시간 (화면)
var _mix_clock := -999.0            ## 반주 재생 위치로 맞춘 곡 시간 (지금 섞이는 소리)
var _loop_base := 0                 ## 반주를 튼 회차 (반주 시계: 몇 바퀴째인지 직접 센다)
var _loops := 0
var _last_pos := 0.0
var _focus_key := ""
var _focus_since := 0.0


func _ready() -> void:
    Sfx.bgm("")                     # 메뉴 음악 끄고 이 게임 반주를 직접 튼다 (박자를 맞춰야 해서)
    teams = int(online_match.get("teams", 0)) if is_online_match() else 2
    if not is_client():
        var rng := RandomNumberGenerator.new()
        rng.randomize()
        _set_song(Chart.pick_song(rng, _last_song))
        _last_song = song_id
    else:
        _set_song(Chart.DEFAULT_SONG)   # 서버가 "start" 로 알려 주면 바꾼다
    _spawn_fighters()
    if is_server():
        return
    _build_stage()
    _build_audio()
    _lighten_scene()
    if is_client():
        Net.game_message.connect(on_server_message)
        Net.disconnected.connect(_on_net_disconnected)
        send_to_server(["loaded"])
    var layer := CanvasLayer.new()
    add_child(layer)
    var hud: Control = HUD_SCRIPT.new()
    hud.game = self
    layer.add_child(hud)
    if TOUCH_SCRIPT.should_enable():
        layer.add_child(ROTATE_HINT.new())
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 쾌적하게: 이 게임은 무대만 보므로 그림자 범위를 좁히고 먼 풀은 숨긴다. 입력 지연이 적은 화면 동기화(mailbox)
func _lighten_scene() -> void:
    var world := get_parent()
    var sun := world.get_node_or_null("Sun") as DirectionalLight3D
    if sun:
        sun.directional_shadow_max_distance = 28.0
        sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    var grass := world.get_node_or_null("Grass")
    if grass:
        var center := Vector3(0, 0, 2.0)
        for c in grass.get_children():
            var mm := c as MultiMeshInstance3D
            if mm == null:
                continue
            var box: AABB = mm.global_transform * mm.get_aabb()
            var p := box.get_center()
            if Vector2(p.x - center.x, p.z - center.z).length() > 30.0:
                mm.visible = false
    # 작은 부품은 그림자를 드리우지 않게 (그림자 그리기 줄이기)
    for f in fighters:
        for mi in f.find_children("*", "GeometryInstance3D", true, false):
            var g := mi as GeometryInstance3D
            if g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_aabb().get_longest_axis_size() < 0.35:
                g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if not OS.has_feature("web") and not OS.has_feature("mobile"):
        _vsync_before = DisplayServer.window_get_vsync_mode()
        if _vsync_before == DisplayServer.VSYNC_ENABLED:
            DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)


# ================================================================ 구성
func _spawn_fighters() -> void:
    var entries: Array = []
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
            entries.append({"peer": int(m.id), "name": String(m.nick), "team": -1})
        var total_slots: int = int(online_match.max) if online_match.bot_fill else online_match.members.size()
        for b in range(maxi(total_slots - entries.size(), 0)):
            entries.append({"peer": 0, "name": "Bot %d" % (b + 1), "team": -1})
    else:
        # 혼자 연습: 2팀 (나 + 봇 vs 봇 둘)
        entries.append({"peer": 0, "name": "나", "team": 0, "me": true})
        for b in bot_count:
            entries.append({"peer": 0, "name": "Bot %d" % (b + 1), "team": 0 if b == 0 else 1})
    var my_id := int(online_match.get("my_id", 0))
    for i in entries.size():
        var e: Dictionary = entries[i]
        var f := Fighter.new()
        f.game = self
        f.slot = i
        f.peer_id = e.peer
        f.display_name = e.name
        f.team = int(e.get("team", -1))
        f.remote = true                 # 북 치는 인형: 물리로 움직이지 않음
        f.net_on_floor = true
        f.drum_mode = true
        f.look = i
        f.body_color = Teams.color(f.team) if f.team >= 0 else BOT_COLORS[i % BOT_COLORS.size()]
        var mine: bool = bool(e.get("me", false)) if not is_online_match() else (net_role == NetRole.CLIENT and int(e.peer) == my_id)
        if mine:
            my_slot = i
        if is_server() and e.peer != 0:
            _slot_of_peer[int(e.peer)] = i
        fighters.append(f)
        scores[i] = 0
    _layout()
    for f in fighters:
        add_child(f)
        f.global_position = f.position
        if f.slot == my_slot and f.name_tag:
            f.name_tag.text = "★ " + f.display_name
    if my_slot >= 0:
        human = fighters[my_slot]


## 무대 위 배치: 팀끼리 모여 반원으로, 카메라(앞)를 바라봄
func _layout() -> void:
    var n := fighters.size()
    var groups := {}
    for f in fighters:
        var key := f.team if f.team >= 0 else 0
        if not groups.has(key):
            groups[key] = []
        groups[key].append(f)
    var order: Array = groups.keys()
    order.sort()
    var gap := 2 if order.size() > 1 else 0          # 팀 사이를 넓게 띄워 구분
    var total_slots := n + gap * (order.size() - 1)
    var span := deg_to_rad(clampf(15.0 * total_slots, 30.0, 150.0))
    var k := 0
    for g in order:
        var sum := Vector3.ZERO
        for f: Fighter in groups[g]:
            var u := 0.5 if total_slots <= 1 else float(k) / float(total_slots - 1)
            var a := -span * 0.5 + span * u
            var r := stage_radius()
            var p := Vector3(sin(a) * r, 0.0, -cos(a) * r + 2.0)
            var h: float = terrain.get_height(0, 0) if terrain else 0.0
            f.position = Vector3(p.x, h + 0.46, p.z)
            var to_cam := Vector3(0, 0, 12) - f.position
            f.rotation.y = atan2(-to_cam.x, -to_cam.z)
            sum += f.position
            k += 1
        _group_center[g] = sum / float(groups[g].size())
        k += gap


func stage_radius() -> float:
    return 4.0 + fighters.size() * 0.2


func _build_stage() -> void:
    var h: float = terrain.get_height(0, 0) if terrain else 0.0
    var r := stage_radius()
    _camera = Camera3D.new()
    _camera.fov = 50.0
    add_child(_camera)
    _overview_pos = Vector3(0, h + 3.0 + r * 0.4, 3.6 + r * 0.95)
    _overview_look = Vector3(0, h + 0.4, -r * 0.55 + 1.0)
    _cam_pos = _overview_pos
    _cam_look = _overview_look
    _camera.global_position = _cam_pos
    _camera.look_at(_cam_look, Vector3.UP)
    _camera.current = true
    # 둥근 나무 무대 (돌피하기 아레나와 같은 장난감 색감)
    var stage := MeshInstance3D.new()
    var disc := CylinderMesh.new()
    disc.top_radius = r + 1.6
    disc.bottom_radius = r + 1.8
    disc.height = 1.0
    disc.radial_segments = 48
    disc.rings = 1
    stage.mesh = disc
    stage.material_override = Toon.make(Color(0.78, 0.53, 0.31), {"rim_strength": 0.2, "shade_softness": 0.1})
    add_child(stage)
    stage.global_position = Vector3(0, h - 0.05, 2.0)       # 윗면 = h + 0.45 (풀보다 높게)
    var rim := MeshInstance3D.new()
    var tor := TorusMesh.new()
    tor.inner_radius = r + 1.55
    tor.outer_radius = r + 1.9
    tor.rings = 48
    tor.ring_segments = 8
    rim.mesh = tor
    rim.material_override = Toon.make(Color(0.95, 0.74, 0.25), {"rim_strength": 0.3})
    add_child(rim)
    rim.global_position = Vector3(0, h + 0.46, 2.0)
    rim.scale = Vector3(1, 0.4, 1)
    _build_team_areas(h)
    # 북 두 개 (화면 왼쪽 둥 = 큰 주황 북, 오른쪽 딱 = 작은 보라 북)
    for f in fighters:
        _drums[f.slot] = _make_drum_pair(f, 1.0)
    _build_hosts(h, r)
    _attack_mark = Label3D.new()
    _attack_mark.text = "공격!"
    _attack_mark.font_size = 72
    _attack_mark.outline_size = 18
    _attack_mark.pixel_size = 0.006
    _attack_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _attack_mark.no_depth_test = true
    _attack_mark.modulate = Color(1.0, 0.85, 0.2)
    _attack_mark.visible = false
    add_child(_attack_mark)


## 툰 셰이더에 넣을 때 화면에서 원래 색처럼 진하게 보이도록 (sRGB → 선형)
static func _vivid(c: Color) -> Color:
    return c.srgb_to_linear()


## 북 한 쌍을 parent 앞에 (parent 는 화면 쪽을 바라봄 → 화면 왼쪽 = parent 의 +X)
func _make_drum_pair(parent: Node3D, size: float) -> Array:
    # 툰 셰이더는 색을 밝게 띄우므로 진하게 넘김 (화면 버튼의 주황·보라와 같아 보이게). 재질은 모든 북이 같이 씀
    if not _mats.has("don"):
        _mats.merge({"don": Toon.make(_vivid(DON_COLOR), {"rim_strength": 0.25}), "ka": Toon.make(_vivid(KA_COLOR), {"rim_strength": 0.25}),
                "skin": Toon.make(Color(0.98, 0.94, 0.84), {"rim_strength": 0.3}), "band": Toon.make(Color(0.25, 0.17, 0.12), {"rim_strength": 0.2})})
    var don_mat: Material = _mats.don
    var ka_mat: Material = _mats.ka
    var skin_mat: Material = _mats.skin
    var band_mat: Material = _mats.band
    var pair := []
    for side in 2:
        var holder := Node3D.new()
        parent.add_child(holder)
        holder.position = Vector3(0.32 if side == 0 else -0.32, 0.0, -0.55) * size
        holder.scale = Vector3.ONE * size
        var body := MeshInstance3D.new()
        var cyl := CylinderMesh.new()
        cyl.top_radius = 0.30 if side == 0 else 0.22
        cyl.bottom_radius = cyl.top_radius * 0.92
        cyl.height = 0.62 if side == 0 else 0.55
        cyl.radial_segments = 20
        cyl.rings = 1
        body.mesh = cyl
        body.material_override = don_mat if side == 0 else ka_mat
        body.position.y = cyl.height * 0.5
        holder.add_child(body)
        var band := MeshInstance3D.new()
        var bt := TorusMesh.new()
        bt.inner_radius = cyl.top_radius * 0.98
        bt.outer_radius = cyl.top_radius * 1.08
        bt.rings = 20
        bt.ring_segments = 6
        band.mesh = bt
        band.material_override = band_mat
        band.position.y = cyl.height - 0.02
        band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        holder.add_child(band)
        var top := MeshInstance3D.new()
        var disk := CylinderMesh.new()
        disk.top_radius = cyl.top_radius * 1.02
        disk.bottom_radius = disk.top_radius
        disk.height = 0.03
        disk.radial_segments = 20
        disk.rings = 1
        top.mesh = disk
        top.material_override = skin_mat
        top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        top.position.y = cyl.height + 0.01
        holder.add_child(top)
        pair.append(holder)
    return pair


## 팀 구역: 바닥 색으로 구분 — 팀원들이 선 자리를 팀 색 큰 원판들로 이어 칠해 한 덩어리 구역으로 보이게
##   개인전은 각자 발밑만 자기 색
func _build_team_areas(h: float) -> void:
    # 이웃한 자리 사이 거리 (같은 팀 원판이 서로 겹쳐 이어지도록)
    var step := 1.2
    if fighters.size() > 1:
        step = 99.0
        for a in fighters:
            for b in fighters:
                if a != b and a.team == b.team:
                    step = minf(step, Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length())
        if step > 90.0:
            step = 1.2
    var rad := 0.8 if teams < 2 else maxf(1.05, step * 0.62)
    for f in fighters:
        var mat := MeshInstance3D.new()
        var d := CylinderMesh.new()
        d.top_radius = rad
        d.bottom_radius = rad
        d.height = 0.04
        d.radial_segments = 32
        d.rings = 1
        mat.mesh = d
        var c: Color = Teams.color(f.team) if f.team >= 0 else f.body_color
        var mk := "pad%s" % c.to_html()
        if not _mats.has(mk):
            _mats[mk] = Toon.make(_vivid(c), {"rim_strength": 0.15})
        mat.material_override = _mats[mk]
        mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(mat)
        mat.global_position = Vector3(f.position.x, h + 0.47, f.position.z - 0.2)


## 가면 쓴 진행자: 가운데 뒤 단상에 북 치는 진행자 1명, 무대 양옆에 지켜보는 진행자 2명
func _build_hosts(h: float, r: float) -> void:
    var podium_mat := Toon.make(Color(0.16, 0.15, 0.2), {"rim_strength": 0.3})
    var spots := [
        [Vector3(0, h + 0.45, 2.0 - r - 1.0), 0, 0.9],            # 가운데 뒤 (높은 단상)
        [Vector3(-(r + 0.9), h + 0.45, 2.6), 1, 0.0],
        [Vector3(r + 0.9, h + 0.45, 2.6), 2, 0.0],
    ]
    for sp in spots:
        var p: Vector3 = sp[0]
        var lift: float = sp[2]
        if lift > 0.0:
            var pod := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 1.0
            cyl.bottom_radius = 1.15
            cyl.height = lift
            cyl.radial_segments = 20
            cyl.rings = 1
            pod.mesh = cyl
            pod.material_override = podium_mat
            add_child(pod)
            pod.global_position = p + Vector3(0, lift * 0.5, 0)
        var host: Node3D = MaskedHost.new()
        host.variant = int(sp[1])
        host.turn_body = lift <= 0.0                   # 북 치는 진행자는 앞(화면)을 계속 봄
        var to_cam := _overview_pos - p
        host.rotation.y = atan2(-to_cam.x, -to_cam.z)
        add_child(host)
        host.global_position = p + Vector3(0, lift, 0)
        _hosts.append(host)
    _host_drums = _make_drum_pair(_hosts[0], 1.35)


func _host_look(p: Vector3) -> void:
    for i in _hosts.size():
        _hosts[i].look_at_point(p)


func _host_gesture(kind: String) -> void:
    for i in range(1, _hosts.size()):
        _hosts[i].gesture(kind)


## 곡 정하기: 진행표·끝 시각·반주를 그 곡으로
func _set_song(id: String) -> void:
    song_id = id if Chart.SONGS.has(id) else Chart.DEFAULT_SONG
    turns = Chart.build_turns(teams, song_id)
    end_time = Chart.end_time(turns, song_id)
    _roll_step = Chart.beat_of(song_id) / 4.0
    if _music:
        _music.stop()
        var st: AudioStreamOggVorbis = Chart.song_backing(song_id).duplicate()
        st.loop = false             # 완성곡 한 번 (반복 없음)
        _music.stream = st


func _build_audio() -> void:
    _music = AudioStreamPlayer.new()
    _music.bus = "Music"
    _music.volume_db = MUSIC_DB
    add_child(_music)
    _set_song(song_id)
    for i in 10:
        var p := AudioStreamPlayer.new()
        p.bus = "Sfx"
        add_child(p)
        _sfx_pool.append(p)


func _snd(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
    if _sfx_pool.is_empty():
        return
    var p: AudioStreamPlayer = _sfx_pool.pop_front()
    _sfx_pool.append(p)
    p.stream = SND[name]
    p.volume_db = db
    p.pitch_scale = pitch
    p.play()


# ================================================================ 시간
## 곡 시간 (초). 시작 전이면 음수
func song_time() -> float:
    return -999.0 if t0 < 0.0 else net_now() - t0


## 지금 섞이고 있는 반주의 곡 시각 (반주가 나오면 재생 위치 기준, 아니면 서버 시계)
func mix_time() -> float:
    return _mix_clock if _mix_clock > -900.0 else song_time()


## 지금 귀에 들리는 곡 시각 = 섞이는 시각 - 소리 출력 지연 - 사용자 보정. 노트 길·판정·박자 점은 모두 이것
func heard_time() -> float:
    if t0 < 0.0:
        return -999.0
    var lat := AudioServer.get_output_latency() if not is_server() else 0.0
    return mix_time() - lat


## 키를 누른 순간의 곡 시각: 화면 시계는 프레임마다 갱신되므로 마지막 갱신 뒤 흐른 시간을 더한다
## (안 더하면 늘 최대 한 프레임(약 16ms)만큼 이르게 잡힘)
func input_time() -> float:
    var t := heard_time()
    if _real_prev > 0 and _mix_clock > -900.0:
        t += minf((Time.get_ticks_usec() - _real_prev) / 1000000.0, 0.05)
    return t


## 지금 차례: [turn 번호, "ready_attack" | "attack" | "ready_response" | "response" | "", 다음 차례 번호]
func phase_at(t: float) -> Array:
    for i in turns.size():
        var tr: Dictionary = turns[i]
        if t < Chart.ready_t(tr):
            return [-1, "", i]
        if t < float(tr.attack_t):
            return [i, "ready_attack", i + 1]
        if t < Chart.attack_end(tr):
            return [i, "attack", i + 1]
        if t < float(tr.response_t):
            return [i, "ready_response", i + 1]
        if t < Chart.response_end(tr):
            return [i, "response", i + 1]
    return [-1, "", turns.size()]


func team_of(slot: int) -> int:
    return fighters[slot].team if slot >= 0 and slot < fighters.size() else -1


func is_responder(slot: int, turn: int) -> bool:
    var at := int(turns[turn].attack_team)
    return at < 0 or team_of(slot) != at


# ================================================================ 입력
## PC·웹: Space = 둥, Enter = 딱 (F·J 도 됨). 버튼보다 먼저 받아서 Space·Enter 가 화면 버튼을 누르지 않게 한다
func _input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key == null or key.echo:
        return
    var lane := -1
    match key.physical_keycode:
        KEY_SPACE, KEY_F:
            lane = 0
        KEY_ENTER, KEY_KP_ENTER, KEY_J:
            lane = 1
    if lane < 0:
        return
    get_viewport().set_input_as_handled()
    if key.pressed:
        press(lane)
    else:
        release(lane)


## 북 치기 (키보드·터치 버튼). lane 0 = 둥(왼쪽), 1 = 딱(오른쪽)
func press(lane: int) -> void:
    if my_slot < 0 or state == State.ENDED or t0 < 0.0 or _key_down[lane]:
        return
    _key_down[lane] = true
    var t := input_time()
    _press_t[lane] = t
    _set_hold(my_slot, lane, true)
    if is_client():
        send_to_server(["key", lane, 1])        # 다른 사람 화면에서 내 캐릭터가 치도록 (판정과 별개)
    _strike(my_slot, lane)
    _snd("don" if lane == 0 else "ka")
    _rolls.append({"who": my_slot, "lane": lane, "until": -1.0, "next": t + Chart.FEVER_HOLD_MIN, "db": ROLL_DB, "mine": true})
    # 판정은 이 기기에서 한다 (박자에 민감하므로). 서버에는 결과만 보내고, 서버는 그대로 점수에 반영해 다른 사람에게 알린다
    var rt := _response_turn_at(t)
    if rt >= 0 and is_responder(my_slot, rt) and view_final.has(rt):
        var notes: Array = view_notes.get(rt, [])
        var taken: Dictionary = view_taken.get(rt, {})
        var r := Chart.judge_response(turns[rt], notes, taken, lane, t)
        var n_i := int(r[0])
        if n_i >= 0:
            taken[n_i] = r[1]
            view_taken[rt] = taken
            if Chart.is_fever(notes[n_i]):
                view_hold[lane] = [rt, n_i]
        _show_judge(String(r[1]))
        _send_result(["res", rt, n_i, r[1], lane])


## 내 판정 결과를 서버로 (오프라인이면 바로 반영)
func _send_result(msg: Array) -> void:
    if is_client():
        send_to_server(msg)
    elif net_role == NetRole.OFFLINE:
        _apply_result(my_slot, msg)


## 북에서 손을 뗌 (피버)
func release(lane: int) -> void:
    if not _key_down[lane]:
        return
    _key_down[lane] = false
    _stop_my_roll(lane)
    _set_hold(my_slot, lane, false)
    if is_client():
        send_to_server(["key", lane, 0])
    if my_slot < 0 or state == State.ENDED or t0 < 0.0:
        return
    var t := input_time()
    if view_hold.has(lane):
        var vh: Array = view_hold[lane]
        view_hold.erase(lane)
        var notes: Array = view_notes.get(int(vh[0]), [])
        if int(vh[1]) < notes.size():
            var j := Chart.judge_release(turns[int(vh[0])], notes[int(vh[1])], t)
            var taken: Dictionary = view_taken.get(int(vh[0]), {})
            taken[-(int(vh[1]) + 1)] = j
            view_taken[int(vh[0])] = taken
            _show_judge(j)
            _send_result(["resrel", int(vh[0]), int(vh[1]), j, lane])


func _stop_my_roll(lane: int) -> void:
    for r in _rolls:
        if r.get("mine", false) and int(r.lane) == lane and float(r.until) < 0.0:
            r.until = 0.0


## 따라 치기 판정 범위(앞뒤 BAD 여유 포함) 안의 차례
func _response_turn_at(t: float) -> int:
    for i in turns.size():
        var tr: Dictionary = turns[i]
        if t >= float(tr.response_t) - Chart.BAD and t < Chart.response_end(tr) + Chart.BAD:
            return i
    return -1


func _show_judge(j: String) -> void:
    last_judge = j
    last_judge_time = Time.get_ticks_msec() / 1000.0
    if j == "miss" or j == "extra":
        _snd("miss", -8.0)


const NO_ANIM := -99                 ## 소리만 내고 인형은 움직이지 않음 (사람의 움직임은 "k" 로 따로 옴)


func _strike(slot: int, lane: int, soft: bool = false) -> void:
    if slot == NO_ANIM:
        return
    if slot < 0:
        _host_strike(lane, soft)
        return
    if slot >= fighters.size():
        return
    var f := fighters[slot]
    var amt := 0.5 if soft else 1.0
    if lane == 0:
        f.drum_r = amt          # 둥 = 화면 왼쪽 = 캐릭터 오른손
    else:
        f.drum_l = amt
    if _drums.has(slot):
        _bump(_drums[slot][lane], 1.0, soft)


func _bump(d: Node3D, base: float, soft: bool) -> void:
    var k := 0.5 if soft else 1.0
    d.scale = Vector3.ONE * base * Vector3(1.0 + 0.12 * k, 1.0 - 0.18 * k, 1.0 + 0.12 * k)
    var tw := d.create_tween()
    tw.tween_property(d, "scale", Vector3.ONE * base, 0.12)


## 누르고 있는 동안 팔을 내린 채로 (피버)
func _set_hold(slot: int, lane: int, on: bool) -> void:
    if slot < 0 or slot >= fighters.size():
        return
    if lane == 0:
        fighters[slot].drum_hold_r = on     # 둥 = 캐릭터 오른손
    else:
        fighters[slot].drum_hold_l = on


func _host_strike(lane: int, soft: bool = false) -> void:
    if _hosts.is_empty():
        return
    if not soft:
        _hosts[0].gesture("hit_r" if lane == 0 else "hit_l")       # 둥 = 화면 왼쪽 = 진행자의 오른손
    _bump(_host_drums[lane], 1.35, soft)


# ================================================================ 진행 (화면)
func _process(delta: float) -> void:
    if is_server():
        return
    _sync_music(delta)
    var t := song_time()
    if t0 >= 0.0 and state == State.COUNTDOWN and t >= 0.0:
        state = State.PLAYING
    var mt := mix_time()
    var ht := heard_time()
    # 예약된 북: 소리는 섞이는 시각에, 인형 움직임은 들리는 시각에
    var keep: Array = []
    for hit in _bot_hits:
        if not bool(hit[4]) and mt >= float(hit[0]):
            hit[4] = true
            if float(hit[3]) > -90.0:
                _snd("don" if int(hit[2]) == 0 else "ka", float(hit[3]))
            if float(hit[5]) > float(hit[0]):
                _rolls.append({"who": int(hit[1]), "lane": int(hit[2]), "until": float(hit[5]), "next": float(hit[0]) + _roll_step, "db": float(hit[3]) + ROLL_DB})
        if ht >= float(hit[0]):
            _strike(int(hit[1]), int(hit[2]))
        else:
            keep.append(hit)
    _bot_hits = keep
    if not _popups.is_empty():
        var keep_p: Array = []
        for pp in _popups:
            if ht >= float(pp[0]):
                var s := int(pp[1])
                if s >= 0 and s < fighters.size():
                    var j := String(pp[2])
                    _judge_pop(s, j)
            else:
                keep_p.append(pp)
        _popups = keep_p
    _update_rolls(mt, ht)
    _check_hold_miss(ht)
    # 진행자 머리 위: 선창 중 "선창!"
    var cur := phase_at(ht)
    _attack_mark.visible = state == State.PLAYING and cur[1] == "attack"
    if _attack_mark.visible:
        _attack_mark.global_position = _hosts[0].global_position + Vector3(0, 3.0 + sin(t * 8.0) * 0.08, 0)
        _attack_mark.text = "선창!"
        _attack_mark.modulate = Color(1.0, 0.85, 0.2)
    _update_camera(delta, ht, cur, -1)


## 피버 '드르륵': 누르고 있는 동안 16분음표마다 작은 북소리 + 살짝 두드리는 움직임
##   내 북: 키를 FEVER_HOLD_MIN 넘게 누르고 있으면 뗄 때까지 (until 0 = 뗌). 남·봇·진행자: until 시각까지
func _update_rolls(mt: float, ht: float) -> void:
    if _rolls.is_empty():
        return
    var keep: Array = []
    for r in _rolls:
        var mine: bool = r.get("mine", false)
        if mine and float(r.until) == 0.0:
            continue
        var clock := ht if mine else mt
        while clock >= float(r.next) and (mine or float(r.next) < float(r.until) - 0.02):
            if float(r.db) > -90.0:
                _snd("don" if int(r.lane) == 0 else "ka", float(r.db), 1.05)
            _strike(int(r.who), int(r.lane), true)
            r.next = float(r.next) + _roll_step
        if not mine and clock >= float(r.until):
            continue
        keep.append(r)
    _rolls = keep


## 피버를 끝 박자보다 한참 넘게 누르고 있으면 MISS (화면용)
func _check_hold_miss(ht: float) -> void:
    for lane in view_hold.keys():
        var vh: Array = view_hold[lane]
        var notes: Array = view_notes.get(int(vh[0]), [])
        if int(vh[1]) >= notes.size():
            view_hold.erase(lane)
            continue
        var end_t := Chart.note_end_time(turns[int(vh[0])], notes[int(vh[1])], true)
        if ht > end_t + Chart.BAD:
            view_hold.erase(lane)
            var taken: Dictionary = view_taken.get(int(vh[0]), {})
            taken[-(int(vh[1]) + 1)] = "miss"
            view_taken[int(vh[0])] = taken
            _show_judge("miss")


## 카메라 연출 (음악방송처럼): 상황에 맞는 샷을 골라 2.5~4.5초마다 컷을 바꾸고, 샷 안에서는 천천히 돌거나 다가간다
##   공격: 공격자 클로즈업 · 팀 미디엄 · 아래에서 올려다보기 · 옆에서 / 따라 치기: 팀 미디엄 · 한 명 클로즈업 · 위에서 내려다보기 · 전체
##   쉼·끝: 전체 · 진행자 클로즈업 · 이긴 팀
##   보는 점을 몸 아래쪽에 둬서 인물이 화면 위쪽(아래 UI에 안 가리게)에 오도록
const SHOTS := {
    "close": {"yaw": 0.3, "pitch": 0.14, "dist": 4.0, "spread": 0.0, "look": 0.75, "orbit": 0.05, "dolly": 0.025, "fov": 46.0},
    "medium": {"yaw": 0.22, "pitch": 0.26, "dist": 5.4, "spread": 1.5, "look": 0.55, "orbit": 0.03, "dolly": 0.02, "fov": 50.0},
    "low": {"yaw": 0.3, "pitch": 0.06, "dist": 4.8, "spread": 1.2, "look": 1.05, "orbit": 0.04, "dolly": 0.0, "fov": 52.0},
    "high": {"yaw": 0.15, "pitch": 0.8, "dist": 7.0, "spread": 1.3, "look": 0.3, "orbit": 0.06, "dolly": 0.02, "fov": 48.0},
    "side": {"yaw": 0.95, "pitch": 0.2, "dist": 4.6, "spread": 1.0, "look": 0.6, "orbit": -0.06, "dolly": 0.0, "fov": 48.0},
}
var _shot := {}
var _shot_t := 0.0
var _shot_len := 3.0
var _shot_rng := RandomNumberGenerator.new()
var _cycle_idx := -1


func _update_camera(delta: float, ht: float, cur: Array, who: int) -> void:
    if _camera == null:
        return
    var i := int(cur[0])
    var kind: String = cur[1]
    # 지금 비출 무리와 고를 샷
    #   선창: 진행자 클로즈업·아래에서 + 가끔 듣고 있는 연주자들 / 따라 치기: 연주자들을 한 명씩 번갈아 클로즈업 + 무리·위에서
    var group: Array = []
    var picks: Array = []               # [샷 이름, 무게]
    if state == State.ENDED:
        if teams >= 2 and not final_rank.is_empty():
            group = fighters.filter(func(f): return f.team == int(final_rank[0].get("team", -1)))
        picks = [["medium", 2], ["low", 1]]
    elif t0 >= 0.0 and ht >= 0.0 and i >= 0 and (kind == "attack" or kind == "ready_attack"):
        group = [_hosts[0]]
        picks = [["close", 3], ["low", 1], ["medium", 1], ["players", 2]]
    elif t0 >= 0.0 and ht >= 0.0 and i >= 0:
        group = fighters.duplicate()
        picks = [["cycle", 5], ["medium", 1], ["high", 1]] if kind == "response" else [["cycle", 2], ["medium", 1]]
    else:
        picks = [["wide", 3], ["host", 1]]
    var key := str(group.map(func(f): return f.get_instance_id())) + kind.substr(0, 5)
    var now := Time.get_ticks_msec() / 1000.0
    var fast := false
    if key != _focus_key or now - _shot_t > _shot_len or _shot.is_empty():
        fast = key != _focus_key
        _focus_key = key
        _pick_shot(picks, group)
    var age := now - _shot_t
    var want := _shot_pose(age)
    # 같은 무리 안에서 바뀐 샷은 컷(바로), 무리가 바뀌면 빠르게 따라감, 샷 안에서는 부드럽게
    var k := 1.0 - exp(-delta * (6.0 if fast or age < 0.25 else 3.0))
    if bool(_shot.get("cut", false)) and age < 0.05:
        k = 1.0
    _cam_pos = _cam_pos.lerp(want[0], k)
    _cam_look = _cam_look.lerp(want[1], k)
    _camera.fov = lerpf(_camera.fov, float(want[2]), k)
    _camera.global_position = _cam_pos
    _camera.look_at(_cam_look, Vector3.UP)
    if not _hosts.is_empty():
        _host_look(_cam_look)


func _pick_shot(picks: Array, group: Array) -> void:
    var total := 0
    for p in picks:
        total += int(p[1])
    var r := _shot_rng.randi_range(1, maxi(total, 1))
    var name: String = picks[0][0]
    for p in picks:
        r -= int(p[1])
        if r <= 0:
            name = p[0]
            break
    var prev: String = _shot.get("name", "")
    if name == prev and name != "cycle" and picks.size() > 1 and _shot_rng.randf() < 0.6:
        name = picks[(picks.find(picks.filter(func(p): return p[0] == name)[0]) + 1) % picks.size()][0]
    var targets: Array = group
    if name == "players":
        targets = fighters.duplicate()          # 듣고 있는 연주자들 (팀이 많으면 무리 하나)
        if teams >= 2:
            var tm := _shot_rng.randi_range(0, teams - 1)
            targets = fighters.filter(func(f): return f.team == tm)
        name = "medium"
    elif name == "cycle":
        # 연주자를 차례로 한 명씩 클로즈업 (같은 사람 연속 없이)
        _cycle_idx = (_cycle_idx + 1) % maxi(fighters.size(), 1)
        targets = [fighters[_cycle_idx]] if not fighters.is_empty() else group
        name = "close"
    elif name == "close" and group.size() > 1:
        targets = [group[_shot_rng.randi_range(0, group.size() - 1)]]
    if name == "host" and not _hosts.is_empty():
        targets = [_hosts[0]]
        name = "close"
    _shot = {"name": name, "targets": targets, "side": -1.0 if _shot_rng.randf() < 0.5 else 1.0,
            "cut": prev != "" and _shot_rng.randf() < 0.6}
    _shot_t = Time.get_ticks_msec() / 1000.0
    _shot_len = _shot_rng.randf_range(1.8, 2.8) if targets.size() == 1 and targets[0] is Fighter else _shot_rng.randf_range(2.5, 4.0)


## 샷의 지금 카메라 위치·보는 점·화각
func _shot_pose(age: float) -> Array:
    var name: String = _shot.get("name", "wide")
    var targets: Array = _shot.get("targets", [])
    if name == "wide" or targets.is_empty() or not SHOTS.has(name):
        var arm := (_overview_pos - _overview_look).rotated(Vector3.UP, sin(age * 0.15 + _shot_t) * 0.25)
        return [_overview_look + arm * (1.0 - 0.015 * age), _overview_look, 50.0]
    var sp: Dictionary = SHOTS[name]
    var c := Vector3.ZERO
    for f: Node3D in targets:
        c += f.global_position
    c /= float(targets.size())
    var spread := 0.0
    for f: Node3D in targets:
        spread = maxf(spread, Vector2(f.global_position.x - c.x, f.global_position.z - c.z).length())
    var front := _overview_pos - c
    front.y = 0.0
    var base_yaw := atan2(front.x, front.z)
    var side: float = _shot.get("side", 1.0)
    var yaw := base_yaw + float(sp.yaw) * side + float(sp.orbit) * age * side
    var pitch := float(sp.pitch)
    var dist := (float(sp.dist) + spread * float(sp.spread)) * maxf(1.0 - float(sp.dolly) * age, 0.8)
    var look := c + Vector3(0, float(sp.look), 0)
    var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
    return [look + dir * dist, look, float(sp.fov)]


## 반주가 기준 시계: 반주가 몇 바퀴째인지 직접 세서 곡 시간을 낸다 (화면·판정 모두 이것)
##   사운드카드 시계와 컴퓨터 시계는 조금씩 다르게 가서(0.1% 안팎) 곡 후반엔 차이가 쌓인다.
##   예전엔 그 차이가 0.3초를 넘으면 반주를 컴퓨터 시계로 다시 맞춰서 노트가 순간이동했다 → 이제는 반주를 따라간다
##   화면 시계는 실제 흐른 시간만큼 매끄럽게 가고, 반주 위치와의 작은 들쭉날쭉(오디오 버퍼 단위)은 천천히 흡수
##   반주가 멈췄다 나오는 등 1초 넘게 어긋날 때만 다시 맞춘다
func _sync_music(_delta: float) -> void:
    if _music == null or t0 < 0.0:
        return
    var now_us := Time.get_ticks_usec()
    var real_dt := 0.0 if _real_prev < 0 else (now_us - _real_prev) / 1000000.0
    _real_prev = now_us
    var t := song_time()
    var loop_len := 100000.0                    # 곡은 반복하지 않음 (한 바퀴 = 곡 전체)
    var song_len := float(Chart.song_data(song_id).length)
    if t < 0.0 or state == State.ENDED or _mix_clock >= song_len or t >= song_len:
        if _mix_clock > -900.0 and (t >= 0.0 or state == State.ENDED):
            _mix_clock += real_dt
        else:
            _mix_clock = -999.0
        return
    if not _music.playing:
        _start_music(t, loop_len)
        return
    var pos := _music.get_playback_position()
    if pos < _last_pos - loop_len * 0.5:
        _loops += 1                         # 한 바퀴 돌았음
    _last_pos = pos
    var at := (_loop_base + _loops) * loop_len + pos + AudioServer.get_time_since_last_mix()
    if absf(at - t) > 1.0:                  # 반주가 크게 어긋남(멈춤 등) → 다시 맞춤
        _music.stop()
        _start_music(t, loop_len)
        return
    _mix_clock += real_dt
    var err := at - _mix_clock
    if absf(err) > 0.25:
        _mix_clock = at
    else:
        _mix_clock += err * minf(real_dt * 1.2, 1.0)


func _start_music(t: float, loop_len: float) -> void:
    var want := fposmod(t, loop_len)
    _loop_base = int(floor(t / loop_len))
    _loops = 0
    _last_pos = want
    _music.play(want)
    _mix_clock = t


# ================================================================ 메시지 (화면)
func on_server_message(msg: Array) -> void:
    if msg.is_empty():
        return
    match String(msg[0]):
        "start":
            if msg.size() > 3 and String(msg[3]) != song_id:
                _set_song(String(msg[3]))
            t0 = float(msg[1])
        "turn":
            var i := int(msg[1])
            view_attacker[i] = int(msg[2])
            if msg.size() > 3 and msg[3] is Array and not (msg[3] as Array).is_empty():
                _set_notes(i, msg[3], int(msg[2]), true)
        "j":
            var s := int(msg[1])
            if s != my_slot and s >= 0 and s < fighters.size():
                var j := String(msg[2])
                if j != "extra":
                    _judge_pop(s, j)
                # 남의 북소리는 내지 않음 — 들리는 북은 진행자(반주 안)와 내 북뿐 (여럿이 치면 헷갈림)
        "k":
            # 다른 사람이 북을 누름·뗌 → 그 캐릭터가 바로 친다 (판정과 상관없이 누르면 움직임)
            var s := int(msg[1])
            if s != my_slot and s >= 0 and s < fighters.size():
                var lane := int(msg[2]) & 1
                var down := int(msg[3]) == 1
                if down:
                    _strike(s, lane)
                _set_hold(s, lane, down)
        "tres":
            pass
        "score":
            var d: Dictionary = msg[1]
            for k in d:
                scores[int(k)] = int(d[k])
        "end":
            var d: Dictionary = msg[1]
            for k in d:
                scores[int(k)] = int(d[k])
            final_rank = msg[2]
            winner_text = String(msg[3]) if msg.size() > 3 else ""
            state = State.ENDED
            if not _hosts.is_empty():
                _hosts[0].gesture("cheer")
                _host_gesture("clap")
            if _music:
                var tw := create_tween()
                tw.tween_property(_music, "volume_db", -40.0, 1.5)
            Sfx.play("win")


## 노트 받음. attack = true 면 컴퓨터·봇 공격(공격 마디에 공격자 인형이 침). 받은 노트로 따라 치기 확정 → 따라 치는 봇 예약
func _set_notes(i: int, notes: Array, who: int, attack: bool) -> void:
    var list := []
    for n in notes:
        list.append([int(n[0]), int(n[1]), int(n[2]) if n.size() > 2 else -1])
    view_notes[i] = list
    view_final[i] = true
    if attack:
        var now := mix_time()
        for n in list:
            var at := Chart.note_time(turns[i], n, false)
            if at > now - 0.05:
                var until := Chart.note_end_time(turns[i], n, false) if Chart.is_fever(n) else -1.0
                _bot_hits.append([at, who, int(n[1]), -99.0, false, until])     # 소리는 반주에 들어 있음 → 움직임만
    _schedule_responders(i, list)


## 따라 치는 봇 인형 움직임 예약 (소리 없음 — 들리는 북은 진행자와 내 북뿐. 사람의 움직임은 "k" 로 옴)
func _schedule_responders(i: int, notes: Array) -> void:
    for f in fighters:
        if f.slot == my_slot or not is_responder(f.slot, i):
            continue
        if f.peer_id != 0 and is_online_match():
            continue
        # 판정: 서버가 점수를 매길 때와 같은 씨앗 → 머리 위 판정과 점수가 일치
        var js := Chart.bot_judgements(Chart.units(notes), BOT_SKILL, i * 1000 + f.slot)
        var k := 0
        for n in notes:
            var jit := randf_range(-0.03, 0.04)
            var at := Chart.note_time(turns[i], n, true) + jit
            var fever := Chart.is_fever(n)
            var until := Chart.note_end_time(turns[i], n, true) + jit if fever else -1.0
            var j: String = js[k] if k < js.size() else "good"
            k += 1
            _popups.append([at, f.slot, j])
            if j != "miss":                     # 놓친 노트는 치지 않음
                _bot_hits.append([at, f.slot, int(n[1]), -99.0, false, until])
            if fever:
                _popups.append([until, f.slot, js[k] if k < js.size() else "good"])
                k += 1


## 다른 연주자 머리 위 판정 글자. 한 사람 위에는 하나만 (빠른 곡에서 겹쳐 읽기 어려움 → 새 판정이 앞 판정을 바꿈)
func _judge_pop(slot: int, j: String) -> void:
    var old = _pop_labels.get(slot)
    if is_instance_valid(old):
        (old as Node).queue_free()
    var pos: Vector3 = fighters[slot].global_position + Vector3(0, 2.2, 0)
    var l := Label3D.new()
    l.text = Chart.JUDGE_NAMES.get(j, j)
    l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    l.font_size = 52
    l.outline_size = 12
    l.pixel_size = 0.006
    l.modulate = _judge_color(j)
    l.no_depth_test = true
    add_child(l)
    l.global_position = pos
    _pop_labels[slot] = l
    var tw := l.create_tween()
    tw.set_parallel(true)
    tw.tween_property(l, "global_position", pos + Vector3(0, 0.6, 0), 0.6)
    tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.35)
    tw.chain().tween_callback(l.queue_free)


static func _judge_color(j: String) -> Color:
    if j == "off":
        return Color(1.0, 0.65, 0.35)       # 엇박 (점수 절반)
    match j:
        "perfect":
            return Color(1.0, 0.85, 0.2)
        "good":
            return Color(0.45, 0.9, 0.5)
        "bad":
            return Color(0.6, 0.75, 1.0)
        _:
            return Color(0.75, 0.75, 0.8)


# ================================================================ 판정 (서버·오프라인)
func _emit(msg: Array) -> void:
    if is_server():
        broadcast(msg)
    else:
        on_server_message(msg)


func _physics_process(delta: float) -> void:
    if is_client():
        return
    if is_server() and t0 < 0.0:
        _wait_time += delta
        var all_loaded := true
        for m in online_match.get("members", []):
            if not _loaded.has(int(m.id)) and Net._peer_alive(int(m.id)):
                all_loaded = false
        if all_loaded or _wait_time > LOAD_WAIT_MAX:
            t0 = net_now() + START_DELAY
            _emit(["start", t0, teams, song_id])
        return
    if t0 < 0.0:
        t0 = net_now() + START_DELAY
        _emit(["start", t0, teams, song_id])
        return
    var t := song_time()
    if t >= 0.0 and state == State.COUNTDOWN and is_server():
        state = State.PLAYING
    # 진행자 리듬 발표: 쉼이 시작되기 1초 전 (따라 칠 노트를 미리 다 알려 줌 — 화면엔 소리가 난 뒤에만 나타남)
    while _announced + 1 < turns.size() and t >= Chart.ready_t(turns[_announced + 1]) - 1.0:
        _announced += 1
        _announce(_announced)
    # 따라 치기 끝난 차례 정리
    while _finalized + 1 <= _announced and _finalized + 1 < turns.size():
        if t < Chart.response_end(turns[_finalized + 1]) + 1.0:
            break
        _finalized += 1
        _finalize(_finalized)
    if t >= end_time and not _ended:
        _end()


func _difficulty(i: int) -> float:
    return clampf(float(i) / maxf(turns.size() - 1, 1.0), 0.0, 1.0)


## 차례 발표: 진행자가 칠 리듬 (모두가 따라 친다)
func _announce(i: int) -> void:
    var tr: Dictionary = turns[i]
    var notes: Array = tr.notes
    _auth[i] = {"attacker": -1, "notes": notes, "rhold": {}, "taken": {}, "fixed": true}
    _emit(["turn", i, -1, notes])


func _is_live_human(f: Fighter) -> bool:
    if net_role == NetRole.OFFLINE:
        return f.slot == my_slot
    return f.peer_id != 0 and Net._peer_alive(f.peer_id)


func on_client_message(pid: int, msg: Array) -> void:
    if msg.is_empty():
        return
    match String(msg[0]):
        "loaded":
            _loaded[pid] = true
        "res", "resrel":
            if _slot_of_peer.has(pid):
                _apply_result(int(_slot_of_peer[pid]), msg)
        "key":
            # 누름·뗌을 모두에게 그대로 전달 (캐릭터 움직임용)
            if _slot_of_peer.has(pid) and msg.size() >= 3:
                broadcast(["k", int(_slot_of_peer[pid]), int(msg[1]) & 1, 1 if int(msg[2]) == 1 else 0])


const RESPONSE_JUDGES := ["perfect", "good", "bad", "miss", "extra"]


## 플레이어 기기가 계산한 판정 결과를 반영 (서버·오프라인). 서버는 박자를 다시 재지 않는다 — 앞뒤가 맞는지만 본다
##   ["res", turn, 노트 번호(-1 = 헛침), judge, lane]  따라 치기 누름
##   ["resrel", turn, 노트 번호, judge, lane]   따라 치기 피버 뗌
func _apply_result(slot: int, msg: Array) -> void:
    if _ended or t0 < 0.0 or msg.size() < 5:
        return
    var i := int(msg[1])
    if not _auth.has(i):
        return
    var a: Dictionary = _auth[i]
    var tr: Dictionary = turns[i]
    match String(msg[0]):
        "res", "resrel":
            var n_i := int(msg[2])
            var j := String(msg[3])
            var lane := int(msg[4]) & 1
            if not is_responder(slot, i) or not a.fixed or not j in RESPONSE_JUDGES:
                return
            var taken: Dictionary = a.taken.get(slot, {})
            if msg[0] == "res":
                if n_i >= 0:
                    if n_i >= a.notes.size() or taken.has(n_i) or j == "extra":
                        return
                    taken[n_i] = j
                elif j != "extra":
                    return
            else:
                if n_i < 0 or n_i >= a.notes.size() or not Chart.is_fever(a.notes[n_i]) or taken.has(-(n_i + 1)):
                    return
                taken[-(n_i + 1)] = j
            a.taken[slot] = taken
            _add_score(slot, int(Chart.POINTS[j]))
            if is_server():
                broadcast(["j", slot, j, lane + (2 if msg[0] == "resrel" else 0)])


func _add_score(slot: int, pts: int) -> void:
    scores[slot] = int(scores.get(slot, 0)) + pts


## 차례가 끝남: 놓친 노트(피버 뗌 포함)는 MISS, 봇은 실력대로
func _finalize(i: int) -> void:
    var a: Dictionary = _auth[i]
    var units := Chart.units(a.notes)
    var res := {}
    for f in fighters:
        if not is_responder(f.slot, i):
            continue
        var counts := {"perfect": 0, "good": 0, "bad": 0, "miss": 0}
        var pts := 0
        if _is_live_human(f) or (net_role == NetRole.OFFLINE and f.slot == my_slot):
            var taken: Dictionary = a.taken.get(f.slot, {})
            for k in taken:
                counts[taken[k]] += 1
            counts.miss += maxi(units - taken.size(), 0)
        else:
            for j in Chart.bot_judgements(units, BOT_SKILL, i * 1000 + f.slot):
                counts[j] += 1
                pts += int(Chart.POINTS[j])
            _add_score(f.slot, pts)
        res[f.slot] = [pts, counts.perfect, counts.good, counts.bad, counts.miss]
    _emit(["tres", i, res])
    _emit(["score", scores.duplicate()])


func _end() -> void:
    _ended = true
    state = State.ENDED
    var rank := []
    var placements := []
    var win := ""
    if teams >= 2:
        var totals := {}
        var members := {}
        for f in fighters:
            totals[f.team] = int(totals.get(f.team, 0)) + int(scores.get(f.slot, 0))
            if not members.has(f.team):
                members[f.team] = []
            members[f.team].append(f)
        var order: Array = totals.keys()
        order.sort_custom(func(x, y): return totals[x] > totals[y])
        var r := 0
        var prev := -999999
        for idx in order.size():
            var tm: int = order[idx]
            if totals[tm] != prev:
                r = idx + 1
                prev = totals[tm]
            rank.append({"name": Teams.team_name(tm), "score": totals[tm], "team": tm, "rank": r})
            placements.append({"rank": r, "members": members[tm].map(func(f): return participant(f)), "team": Teams.team_name(tm)})
        win = "%s 승리!" % Teams.team_name(order[0]) if order.size() > 1 and totals[order[0]] != totals[order[1]] else "무승부!"
    else:
        var order: Array = fighters.duplicate()
        order.sort_custom(func(x, y): return int(scores[x.slot]) > int(scores[y.slot]))
        var r := 0
        var prev := -999999
        for idx in order.size():
            var f: Fighter = order[idx]
            if int(scores[f.slot]) != prev:
                r = idx + 1
                prev = int(scores[f.slot])
            rank.append({"name": f.display_name, "score": int(scores[f.slot]), "team": -1, "rank": r, "slot": f.slot})
            placements.append({"rank": r, "members": [participant(f)], "team": ""})
        win = "%s 우승!" % order[0].display_name if not order.is_empty() else ""
    _emit(["end", scores.duplicate(), rank, win])
    report_result(placements)


## 사람이 나가면: 팀전은 그 자리를 봇이 이어받고, 개인전은 그대로 (남은 노트는 MISS)
func on_player_left(pid: int) -> void:
    if not _slot_of_peer.has(pid):
        return
    var f := fighters[_slot_of_peer[pid]]
    _slot_of_peer.erase(pid)
    if teams >= 2:
        f.peer_id = 0
        f.display_name = "Bot (%s)" % f.display_name


func _on_net_disconnected() -> void:
    get_tree().create_timer(1.5).timeout.connect(func():
        if is_inside_tree():
            leave_to_menu())


func _exit_tree() -> void:
    if _vsync_before >= 0:
        DisplayServer.window_set_vsync_mode(_vsync_before)
        _vsync_before = -1
    if Net.game_message.is_connected(on_server_message):
        Net.game_message.disconnect(on_server_message)
    if Net.disconnected.is_connected(_on_net_disconnected):
        Net.disconnected.disconnect(_on_net_disconnected)
