extends PartyGame
## 뒷북의 달인 — 공격팀 한 명이 북으로 리듬을 치면, 나머지 팀이 다음 마디에 똑같이 따라 친다
##
## 진행 (chart.gd): 반주가 흐르는 동안 팀이 돌아가며 공격 (1 → 2 → 4마디). 개인전이면 컴퓨터가 공격
##   공격: 그 팀 사람 중 한 명(봇만 있는 팀이면 봇)이 두 북(둥·딱)을 친다. 박자에서 벗어난 노트는 감점 후 보정
##   따라 치기: 공격팀 밖의 모두가 같은 노트를 같은 타이밍에 친다 → PERFECT·GOOD·BAD·MISS
##   곡이 끝나면 팀원 점수 합계(개인전은 개인 점수)로 순위
##
## 판정은 서버(오프라인이면 이 PC)가 한다. 클라이언트는 친 시각(곡 시간)을 보내고, 화면에는 즉시 예상 판정을 보여 준다.
## 메시지 (서버 → 모두)
##   ["start", t0, teams]            곡 시작 시각(서버 시계)
##   ["turn", i, attacker_slot, notes]  i번째 차례 공격자 발표 (공격 한 마디 전). notes 가 있으면 컴퓨터·봇 공격
##   ["note", i, slot, lane, judge]  사람 공격자가 친 노트 (보정된 칸)
##   ["j", fighter_slot, judge]      따라 치기 판정 (머리 위 문구)
##   ["tres", i, {slot: [점수, p, g, b, m]}]  차례 결과 (봇·놓친 노트 포함)
##   ["score", {slot: 총점}]
##   ["end", {slot: 총점}, team_totals]
## 메시지 (클라이언트 → 서버): ["loaded"], ["hit", lane, song_time]

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
const SONG := preload("res://audio/drum/groove.ogg")

@export var bot_count := 3          ## 혼자 연습: 나 + 봇 3 (2팀)

var teams := 0
var my_slot := -1
var t0 := -1.0                      ## 곡 시작 (서버 시계). -1 = 아직
var turns: Array = []               ## Chart.build_turns
var end_time := 0.0
## 화면용 (모든 PC)
var view_notes := {}                ## turn -> [[slot, lane], ...]
var view_attacker := {}             ## turn -> fighter slot (-1 = 컴퓨터)
var view_taken := {}                ## turn -> {note index: judge} 내가 맞힌 노트
var scores := {}                    ## fighter slot -> 총점
var final_rank: Array = []          ## 끝난 뒤 [{name, score, team, rank}]
var last_judge := ""                ## 내 마지막 판정 (HUD)
var last_judge_time := -10.0
var winner_text := ""

# 판정 (서버·오프라인)
var _auth := {}                     ## turn -> {attacker, notes, attack_judges, per_bar, taken:{slot:{i:judge}}, done, fallback}
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
var _bot_hits: Array = []           ## [[song_time, fighter slot, lane]] 봇·컴퓨터·남의 공격 애니메이션 예약
var _cue_beat := -1
var _attack_mark: Label3D


func _ready() -> void:
    Sfx.bgm("")                     # 메뉴 음악 끄고 이 게임 반주를 직접 튼다 (박자를 맞춰야 해서)
    teams = int(online_match.get("teams", 0)) if is_online_match() else 2
    turns = Chart.build_turns(teams)
    end_time = Chart.bar_time(Chart.total_bars(turns))
    _spawn_fighters()
    if is_server():
        return
    _build_stage()
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
    if TOUCH_SCRIPT.should_enable():
        layer.add_child(ROTATE_HINT.new())
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
    var gap := 1 if order.size() > 1 else 0
    var total_slots := n + gap * (order.size() - 1)
    var span := deg_to_rad(clampf(17.0 * total_slots, 30.0, 140.0))
    var k := 0
    for g in order:
        for f: Fighter in groups[g]:
            var u := 0.5 if total_slots <= 1 else float(k) / float(total_slots - 1)
            var a := -span * 0.5 + span * u
            var r := stage_radius()
            var p := Vector3(sin(a) * r, 0.0, -cos(a) * r + 2.0)
            var h: float = terrain.get_height(0, 0) if terrain else 0.0
            f.position = Vector3(p.x, h + 0.46, p.z)
            var to_cam := Vector3(0, 0, 12) - f.position
            f.rotation.y = atan2(-to_cam.x, -to_cam.z)
            k += 1
        k += gap


func stage_radius() -> float:
    return 4.0 + fighters.size() * 0.2


func _build_stage() -> void:
    var h: float = terrain.get_height(0, 0) if terrain else 0.0
    _camera = Camera3D.new()
    _camera.fov = 50.0
    add_child(_camera)
    var r := stage_radius()
    _camera.global_position = Vector3(0, h + 2.6 + r * 0.35, 3.2 + r * 0.9)
    _camera.look_at(Vector3(0, h + 0.8, -r * 0.55 + 1.0), Vector3.UP)
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
    rim.material_override = Toon.make(Color(0.90, 0.22, 0.27), {"rim_strength": 0.3})
    add_child(rim)
    rim.global_position = Vector3(0, h + 0.46, 2.0)
    rim.scale = Vector3(1, 0.4, 1)
    # 북 두 개 (왼쪽 둥 = 큰 빨간 북, 오른쪽 딱 = 작은 파란 북)
    var don_mat := Toon.make(Color(0.86, 0.25, 0.22), {"rim_strength": 0.4})
    var ka_mat := Toon.make(Color(0.25, 0.48, 0.86), {"rim_strength": 0.4})
    var skin_mat := Toon.make(Color(0.98, 0.94, 0.84), {"rim_strength": 0.3})
    for f in fighters:
        var pair := []
        for side in 2:
            var holder := Node3D.new()
            f.add_child(holder)
            holder.position = Vector3(0.32 if side == 0 else -0.32, 0.0, -0.55)     # 캐릭터가 화면을 보므로 화면 왼쪽 = 캐릭터 오른쪽
            var body := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.30 if side == 0 else 0.23
            cyl.bottom_radius = cyl.top_radius * 0.92
            cyl.height = 0.62 if side == 0 else 0.55
            cyl.radial_segments = 20
            cyl.rings = 1
            body.mesh = cyl
            body.material_override = don_mat if side == 0 else ka_mat
            body.position.y = cyl.height * 0.5
            holder.add_child(body)
            var top := MeshInstance3D.new()
            var disk := CylinderMesh.new()
            disk.top_radius = cyl.top_radius * 1.02
            disk.bottom_radius = disk.top_radius
            disk.height = 0.03
            disk.radial_segments = 20
            disk.rings = 1
            top.mesh = disk
            top.material_override = skin_mat
            top.position.y = cyl.height + 0.01
            holder.add_child(top)
            pair.append(holder)
        _drums[f.slot] = pair
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


func _build_audio() -> void:
    _music = AudioStreamPlayer.new()
    _music.bus = "Music"
    var st: AudioStreamOggVorbis = SONG.duplicate()
    st.loop = true
    _music.stream = st
    _music.volume_db = -6.0
    add_child(_music)
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


## 내가 들은 소리 기준 시각 (출력 지연만큼 늦게 들리므로 빼 준다)
func input_time() -> float:
    var lat := AudioServer.get_output_latency() if not is_server() else 0.0
    return song_time() - lat


## 지금 차례: [turn 번호, "attack" | "response" | "", 다음 차례 번호]
func phase_at(t: float) -> Array:
    for i in turns.size():
        var tr: Dictionary = turns[i]
        var a := Chart.bar_time(int(tr.attack_bar))
        var r := Chart.bar_time(int(tr.response_bar))
        var e := r + int(tr.bars) * Chart.BAR
        if t >= a and t < r:
            return [i, "attack", i + 1]
        if t >= r and t < e:
            return [i, "response", i + 1]
        if t < a:
            return [-1, "", i]
    return [-1, "", turns.size()]


func team_of(slot: int) -> int:
    return fighters[slot].team if slot >= 0 and slot < fighters.size() else -1


func is_responder(slot: int, turn: int) -> bool:
    var at := int(turns[turn].attack_team)
    return at < 0 or team_of(slot) != at


# ================================================================ 입력
func _unhandled_input(event: InputEvent) -> void:
    super._unhandled_input(event)
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    match key.physical_keycode:
        KEY_F, KEY_LEFT, KEY_D:
            press(0)
        KEY_J, KEY_RIGHT, KEY_K:
            press(1)


## 북 치기 (키보드·터치 버튼). lane 0 = 둥(왼쪽), 1 = 딱(오른쪽)
func press(lane: int) -> void:
    if my_slot < 0 or state == State.ENDED or t0 < 0.0:
        return
    var t := input_time()
    _strike(my_slot, lane)
    _snd("don" if lane == 0 else "ka")
    # 화면용 예상 판정 (진짜 판정은 서버)
    var ph := phase_at(t + 0.12)
    var i := int(ph[0])
    if i >= 0 and ph[1] == "attack" and int(view_attacker.get(i, -2)) == my_slot:
        var q := Chart.quantize_attack(turns[i], t)
        if int(q[0]) >= 0:
            _show_judge(String(q[1]))
    else:
        var rt := _response_turn_at(t)
        if rt >= 0 and is_responder(my_slot, rt):
            var taken: Dictionary = view_taken.get(rt, {})
            var r := Chart.judge_response(turns[rt], view_notes.get(rt, []), taken, lane, t)
            if int(r[0]) >= 0:
                taken[int(r[0])] = r[1]
                view_taken[rt] = taken
            _show_judge(String(r[1]))
    if is_client():
        send_to_server(["hit", lane, t])
    elif net_role == NetRole.OFFLINE:
        _auth_hit(my_slot, lane, t)


## 따라 치기 판정 범위(앞뒤 BAD 여유 포함) 안의 차례
func _response_turn_at(t: float) -> int:
    for i in turns.size():
        var tr: Dictionary = turns[i]
        var r := Chart.bar_time(int(tr.response_bar))
        if t >= r - Chart.BAD and t < r + int(tr.bars) * Chart.BAR + Chart.BAD:
            return i
    return -1


func _show_judge(j: String) -> void:
    last_judge = j
    last_judge_time = Time.get_ticks_msec() / 1000.0
    if j == "miss" or j == "extra" or j == "wild":
        _snd("miss", -8.0)


func _strike(slot: int, lane: int) -> void:
    if slot < 0 or slot >= fighters.size():
        return
    var f := fighters[slot]
    if lane == 0:
        f.drum_r = 1.0          # 둥 = 화면 왼쪽 = 캐릭터 오른손
    else:
        f.drum_l = 1.0
    if _drums.has(slot):
        var d: Node3D = _drums[slot][lane]
        d.scale = Vector3(1.12, 0.82, 1.12)
        var tw := d.create_tween()
        tw.tween_property(d, "scale", Vector3.ONE, 0.15)


# ================================================================ 진행 (화면)
func _process(_delta: float) -> void:
    if is_server():
        return
    _sync_music()
    var t := song_time()
    if t0 >= 0.0 and state == State.COUNTDOWN and t >= 0.0:
        state = State.PLAYING
    # 박자 신호: 공격·따라 치기 시작 한 마디 전 마지막 박에 '띵'
    if t0 >= 0.0 and state != State.ENDED:
        var beat := int(floor(t / Chart.BEAT))
        if beat != _cue_beat:
            _cue_beat = beat
            var bar_pos := posmod(beat, 4)
            var next_bar := int(floor(t / Chart.BAR)) + 1
            for tr in turns:
                if (int(tr.attack_bar) == next_bar or int(tr.response_bar) == next_bar) and bar_pos >= 2:
                    _snd("cue", -4.0 if bar_pos == 3 else -10.0)
                    break
    # 봇·컴퓨터·다른 사람 공격 애니메이션
    var keep: Array = []
    for h in _bot_hits:
        if t >= float(h[0]):
            _strike(int(h[1]), int(h[2]))
            if bool(h[3]):
                _snd("don" if int(h[2]) == 0 else "ka", -3.0)
        else:
            keep.append(h)
    _bot_hits = keep
    # 공격자 표시
    var ph := phase_at(t + Chart.BAR)
    var show_i := int(ph[0]) if ph[1] == "attack" else (int(ph[2]) if int(ph[2]) < turns.size() else -1)
    var cur := phase_at(t)
    if cur[1] == "attack":
        show_i = int(cur[0])
    var who := int(view_attacker.get(show_i, -1)) if show_i >= 0 else -1
    _attack_mark.visible = who >= 0 and state == State.PLAYING and (cur[1] == "attack" or Chart.bar_time(int(turns[show_i].attack_bar)) - t < Chart.BAR)
    if _attack_mark.visible:
        _attack_mark.global_position = fighters[who].global_position + Vector3(0, 2.6 + sin(t * 8.0) * 0.08, 0)


## 반주를 서버 시계에 맞춘다 (어긋나면 다시 맞춤)
func _sync_music() -> void:
    if _music == null or t0 < 0.0 or state == State.ENDED:
        return
    var t := song_time()
    if t < 0.0:
        return
    if t >= end_time:
        _music.stop()
        return
    var loop_len := 8.0 * Chart.BAR
    var want := fposmod(t, loop_len)
    if not _music.playing:
        _music.play(want)
        return
    var pos := _music.get_playback_position() + AudioServer.get_time_since_last_mix()
    var diff := absf(pos - want)
    if diff > 0.06 and diff < loop_len - 0.06:
        _music.seek(want)


# ================================================================ 메시지 (화면)
func on_server_message(msg: Array) -> void:
    if msg.is_empty():
        return
    match String(msg[0]):
        "start":
            t0 = float(msg[1])
        "turn":
            var i := int(msg[1])
            view_attacker[i] = int(msg[2])
            if msg.size() > 3 and msg[3] is Array and not (msg[3] as Array).is_empty():
                _set_notes(i, msg[3], int(msg[2]))
        "notes":
            _set_notes(i_of(msg), msg[2], -1)
        "note":
            var i := int(msg[1])
            var list: Array = view_notes.get(i, [])
            list.append([int(msg[2]), int(msg[3])])
            view_notes[i] = list
            var who := int(view_attacker.get(i, -1))
            if who >= 0 and who != my_slot:
                _strike(who, int(msg[3]))
                _snd("don" if int(msg[3]) == 0 else "ka", -3.0)
            if who == my_slot and String(msg[4]) == "wild":
                _show_judge("wild")
            _schedule_responders(i, [[int(msg[2]), int(msg[3])]])
        "j":
            var s := int(msg[1])
            if s != my_slot and s >= 0 and s < fighters.size():
                var j := String(msg[2])
                if j != "extra":
                    popup_text(fighters[s].global_position + Vector3(0, 2.2, 0), Chart.JUDGE_NAMES.get(j, j), _judge_color(j))
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
            if _music:
                var tw := create_tween()
                tw.tween_property(_music, "volume_db", -40.0, 1.5)
            Sfx.play("win")


func i_of(msg: Array) -> int:
    return int(msg[1])


## 컴퓨터·봇 공격 노트를 받음: 공격 마디에 공격자 인형이 치게 하고, 따라 치는 봇도 예약
func _set_notes(i: int, notes: Array, who: int) -> void:
    var list := []
    for n in notes:
        list.append([int(n[0]), int(n[1])])
    view_notes[i] = list
    var now := song_time()
    for n in list:
        var at := Chart.slot_time(turns[i], int(n[0]), false)
        if at > now - 0.05:          # 이미 지난 공격 소리는 몰아서 내지 않음 (컴퓨터가 늦게 채운 경우)
            _bot_hits.append([at, who, int(n[1]), true])
    _schedule_responders(i, list)


## 따라 치는 봇(과 화면에 보이는 다른 사람 대신) 인형 움직임 예약
func _schedule_responders(i: int, notes: Array) -> void:
    for f in fighters:
        if f.slot == my_slot or not is_responder(f.slot, i):
            continue
        if f.peer_id != 0 and is_online_match():
            continue            # 사람은 자기 PC에서 친다 (판정 문구만 보임)
        for n in notes:
            var at := Chart.slot_time(turns[i], int(n[0]), true) + randf_range(-0.04, 0.05)
            _bot_hits.append([at, f.slot, int(n[1]), false])


static func _judge_color(j: String) -> Color:
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
            _emit(["start", t0, teams])
        return
    if t0 < 0.0:
        t0 = net_now() + START_DELAY
        _emit(["start", t0, teams])
        return
    var t := song_time()
    if t >= 0.0 and state == State.COUNTDOWN and is_server():
        state = State.PLAYING
    # 공격자 발표: 공격 한 마디 전
    while _announced + 1 < turns.size() and t >= Chart.bar_time(int(turns[_announced + 1].attack_bar)) - Chart.BAR:
        _announced += 1
        _announce(_announced)
    # 사람 공격자가 아무것도 안 쳤으면 컴퓨터가 채움 (따라 칠 게 없으면 안 되니까)
    for i in range(maxi(_announced - 1, 0), _announced + 1):
        if i < 0 or not _auth.has(i):
            continue
        var a: Dictionary = _auth[i]
        var tr: Dictionary = turns[i]
        if not a.fallback and a.notes.is_empty() and t >= Chart.bar_time(int(tr.response_bar)) - 0.2:
            a.fallback = true
            var pat := Chart.computer_pattern(int(tr.bars), _difficulty(i), i * 97 + 13).filter(func(n): return int(n[0]) >= 2)
            a.notes = pat
            _emit(["notes", i, pat])
    # 따라 치기 끝난 차례 정리
    while _finalized + 1 <= _announced and _finalized + 1 < turns.size():
        var tr: Dictionary = turns[_finalized + 1]
        if t < Chart.bar_time(int(tr.response_bar) + int(tr.bars)) + Chart.BAD + 0.1:
            break
        _finalized += 1
        _finalize(_finalized)
    if t >= end_time and not _ended:
        _end()


func _difficulty(i: int) -> float:
    return clampf(float(i) / maxf(turns.size() - 1, 1.0), 0.0, 1.0)


func _announce(i: int) -> void:
    var tr: Dictionary = turns[i]
    var at := int(tr.attack_team)
    var attacker := -1
    var notes := []
    if at >= 0:
        var humans := []
        var members := []
        for f in fighters:
            if f.team == at:
                members.append(f.slot)
                if _is_live_human(f):
                    humans.append(f.slot)
        # 같은 사람이 연달아 걸리지 않게
        var prev := int(_auth[i - teams].attacker) if i - teams >= 0 and _auth.has(i - teams) else -1
        if humans.size() > 1:
            humans.erase(prev)
        if not humans.is_empty():
            attacker = humans.pick_random()
        else:
            attacker = members.pick_random() if not members.is_empty() else -1
            notes = Chart.computer_pattern(int(tr.bars), _difficulty(i), i * 131 + 7)
    else:
        notes = Chart.computer_pattern(int(tr.bars), _difficulty(i), i * 131 + 7)
    _auth[i] = {"attacker": attacker, "notes": notes, "per_bar": {}, "taken": {}, "fallback": not notes.is_empty(), "attack_points": 0}
    _emit(["turn", i, attacker, notes])


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
        "hit":
            if _slot_of_peer.has(pid) and msg.size() >= 3:
                _auth_hit(int(_slot_of_peer[pid]), int(msg[1]) & 1, float(msg[2]))


## 북 한 번 (서버·오프라인 판정)
func _auth_hit(slot: int, lane: int, t: float) -> void:
    if _ended or t0 < 0.0:
        return
    var now := song_time()
    if t > now + 0.2 or t < now - 1.0:
        return                      # 터무니없는 시각 (조작·지연) 무시
    for i in range(maxi(_announced - 2, 0), _announced + 1):
        if not _auth.has(i):
            continue
        var a: Dictionary = _auth[i]
        var tr: Dictionary = turns[i]
        var a0 := Chart.bar_time(int(tr.attack_bar))
        var a1 := Chart.bar_time(int(tr.response_bar))
        # 공격
        if int(a.attacker) == slot and not a.fallback and t >= a0 - Chart.ATTACK_BAD and t < a1 - Chart.SLOT * 0.5:
            var q := Chart.quantize_attack(tr, t)
            var s := int(q[0])
            if s < 0:
                return
            for n in a.notes:
                if int(n[0]) == s and int(n[1]) == lane:
                    return          # 같은 칸·같은 북은 한 번만
            var bar := s / Chart.SLOTS_PER_BAR
            var cnt := int(a.per_bar.get(bar, 0))
            if cnt >= Chart.MAX_NOTES_PER_BAR:
                return
            a.per_bar[bar] = cnt + 1
            a.notes.append([s, lane])
            var j := String(q[1])
            _add_score(slot, int(Chart.ATTACK_POINTS[j]))
            _emit(["note", i, s, lane, j])
            return
        # 따라 치기
        if is_responder(slot, i) and t >= a1 - Chart.BAD and t < a1 + int(tr.bars) * Chart.BAR + Chart.BAD:
            var taken: Dictionary = a.taken.get(slot, {})
            var r := Chart.judge_response(tr, a.notes, taken, lane, t)
            if int(r[0]) >= 0:
                taken[int(r[0])] = r[1]
                a.taken[slot] = taken
            _add_score(slot, int(Chart.POINTS[String(r[1])]))
            if is_server():
                broadcast(["j", slot, r[1]])
            return


func _add_score(slot: int, pts: int) -> void:
    scores[slot] = int(scores.get(slot, 0)) + pts


## 차례가 끝남: 놓친 노트는 MISS, 봇은 실력대로
func _finalize(i: int) -> void:
    var a: Dictionary = _auth[i]
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
            counts.miss += a.notes.size() - taken.size()
        else:
            for j in Chart.bot_judgements(a.notes.size(), BOT_SKILL, i * 1000 + f.slot):
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
    if Net.game_message.is_connected(on_server_message):
        Net.game_message.disconnect(on_server_message)
    if Net.disconnected.is_connected(_on_net_disconnected):
        Net.disconnected.disconnect(_on_net_disconnected)
