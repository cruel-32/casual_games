class_name PartyGame
extends Node3D
## 모든 파티 게임 모듈의 공통 기반 (games/<게임>/... 의 게임 스크립트가 상속)
##
## 월드(scripts/world/world.gd)가 하늘·지형·풀을 만든 뒤, 선택된 모듈의 게임 노드를 만들어
## terrain / grass_material / arena_half / online_match 를 채우고 add_child 한다.
##
## 모듈이 할 일
##   - _ready(): 경기 구성 (캐릭터 생성 → fighters / human 채우기, HUD 등)
##   - state 전환: COUNTDOWN → PLAYING → ENDED
## 공통으로 제공하는 것
##   - 상태 조회(is_playing, alive_fighters …), 팝업 문구, 메뉴/방 복귀, 결과 화면 입력,
##     터치 컨트롤·세로 화면 안내(add_common_ui)
##   - 온라인 역할(net_role)과 메시지 보내기 도우미
##
## 온라인 구조 (서버 판정 + 내 캐릭터는 내 PC에서 즉시 이동)
##   OFFLINE: 이 PC 혼자 전부 진행
##   SERVER : 서버가 방마다 같은 게임 노드를 돌린다. 규칙·생성(낙석·아이템·바람)·봇·사망·승패 판정
##            서버 쪽 게임은 on_client_message(pid, msg) 로 클라이언트 메시지를 받는다
##   CLIENT : 내 캐릭터만 직접 움직여 상태를 보내고, 나머지는 서버가 보낸 대로 보여준다
##            on_server_message(msg) 로 서버 메시지를 받는다

const TOUCH_SCRIPT := preload("res://scripts/ui/touch_controls.gd")
const ROTATE_HINT := preload("res://scripts/ui/rotate_hint.gd")
const LOADING_WATCH := preload("res://scripts/ui/loading_watch.gd")
const MENU_SCENE := "res://scenes/app.tscn"

enum State { COUNTDOWN, PLAYING, ENDED }
enum NetRole { OFFLINE, CLIENT, SERVER }

@export var arena_half := 18.0
@export var countdown_time := 3.0

var module_id := ""
var terrain: Node
var grass_material: ShaderMaterial
## 온라인 방에서 시작한 경우 Net.match_config (비어 있으면 오프라인 연습)
var online_match: Dictionary = {}

var net_role := NetRole.OFFLINE

var fighters: Array[Fighter] = []
var human: Fighter
var state := State.COUNTDOWN
var state_time := 0.0


func is_playing() -> bool:
    return state == State.PLAYING


func is_ended() -> bool:
    return state == State.ENDED


func is_online_match() -> bool:
    return not online_match.is_empty()


func is_server() -> bool:
    return net_role == NetRole.SERVER


func is_client() -> bool:
    return net_role == NetRole.CLIENT


func room_id() -> int:
    return int(online_match.get("room_id", 0))


## 서버 시계 (오프라인이면 이 PC 시계)
func net_now() -> float:
    return Net.server_now() if net_role != NetRole.OFFLINE else Net.local_time()


## CLIENT → 서버
func send_to_server(msg: Array, reliable: bool = true) -> void:
    Net.send_game(msg, reliable)


## SERVER → 방의 모든 플레이어
func broadcast(msg: Array, reliable: bool = true, except_pid: int = 0) -> void:
    Net.broadcast_game(room_id(), msg, reliable, except_pid)


## SERVER → 한 플레이어
func send_to_peer(pid: int, msg: Array, reliable: bool = true) -> void:
    Net.send_game_to(pid, msg, reliable)


func alive_fighters() -> Array[Fighter]:
    var out: Array[Fighter] = []
    for f in fighters:
        if not f.dead:
            out.append(f)
    return out


## 캐릭터 머리 위 등에 잠깐 떠오르는 문구
## relay: 온라인에서 내 캐릭터가 만든 문구를 다른 사람 화면에도 띄운다 (서버를 거쳐 전달)
func popup_text(pos: Vector3, text: String, color: Color, relay: bool = false) -> void:
    if net_role == NetRole.SERVER:
        broadcast(["pop", text, pos, color])
        return
    if relay and net_role == NetRole.CLIENT:
        send_to_server(["pop", text, pos, color])
    var l := Label3D.new()
    l.text = text
    l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    l.font_size = 56
    l.outline_size = 12
    l.pixel_size = 0.006
    l.modulate = color
    l.no_depth_test = true
    add_child(l)
    l.global_position = pos
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(l, "global_position", pos + Vector3(0, 1.0, 0), 0.9)
    tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.4)
    tw.chain().tween_callback(l.queue_free)


## 터치 기기용 컨트롤 + 세로 화면 안내를 HUD 레이어에 붙인다
func add_common_ui(layer: CanvasLayer) -> void:
    var watch: Node = LOADING_WATCH.new()
    watch.game = self
    add_child(watch)
    if TOUCH_SCRIPT.should_enable() and human:
        var touch: Control = TOUCH_SCRIPT.new()
        touch.game = self
        touch.fighter = human
        layer.add_child(touch)
        layer.add_child(ROTATE_HINT.new())


## 서버가 모두의 "loaded" 를 기다리는 최대 시간 (느린 기기·한 명이 끊겨도 영원히 기다리지 않게)
const LOAD_WAIT_MAX := 30.0
const SETTLE_FRAME_MS := 80          ## 이보다 빨리 그려진 프레임이 SETTLE_FRAMES 번 이어지면 '준비됨'
const SETTLE_FRAMES := 6
const SETTLE_MAX_MS := 25000


## 클라이언트: 경기 화면이 실제로 부드럽게 그려지기 시작한 뒤 서버에 "loaded" 를 보낸다
##   _ready 직후 첫 몇 프레임은 셰이더 컴파일·텍스처 올리기로 몇 초씩 멈출 수 있다. 그 전에 알리면
##   서버가 카운트다운을 시작해 버려서, 느린 기기는 멈춰 있다 들어가 보니 다들 한참 달리고 있었다
##   → 프레임이 SETTLE_FRAMES 번 연속 SETTLE_FRAME_MS 안에 그려질 때(최대 25초)까지 기다린다
var loaded_sent := false             ## 클라이언트: 화면이 준비돼 서버에 loaded 를 보냈나 (불러오는 중 표시 글자용)


func send_loaded_when_settled() -> void:
    _settle_and_send.call_deferred()


func _settle_and_send() -> void:
    var t0 := Time.get_ticks_msec()
    var last := t0
    var good := 0
    while good < SETTLE_FRAMES and Time.get_ticks_msec() - t0 < SETTLE_MAX_MS:
        await get_tree().process_frame
        if not is_inside_tree():
            return
        var now := Time.get_ticks_msec()
        good = good + 1 if now - last < SETTLE_FRAME_MS else 0
        last = now
    if is_inside_tree():
        send_to_server(["loaded"])
        loaded_sent = true


## 출발 자리 순서: 팀전이면 팀이 번갈아 서도록 (같은 팀끼리 뭉치지 않게). slot 번호는 그대로 두고 자리만 섞는다
##   teams_of[slot] = 팀 번호(-1 = 개인전) → 돌려주는 값[slot] = 자리 번호. 모든 PC에서 같은 결과
static func mixed_spots(teams_of: Array) -> Array:
    var by_team := {}
    for slot in teams_of.size():
        var t := int(teams_of[slot])
        if not by_team.has(t):
            by_team[t] = []
        by_team[t].append(slot)
    var keys: Array = by_team.keys()
    keys.sort()
    var order := []
    var k := 0
    while order.size() < teams_of.size():
        for t in keys:
            if k < by_team[t].size():
                order.append(by_team[t][k])
        k += 1
    var spot := []
    spot.resize(teams_of.size())
    for i in order.size():
        spot[order[i]] = i
    return spot


## 서버: 경기가 끝났을 때 순위를 알린다 → 라운드 승점(1등 3·2등 2·3등 1) 계산 (scripts/core/series.gd)
##   placements = [{"rank": 1, "members": [participant(f)], "team": ""}, ...]
##   팀 게임은 한 항목의 members 에 팀원 전부를 넣고 team 에 팀 이름. 동점은 같은 rank
func report_result(placements: Array) -> void:
    if is_server():
        Net.on_match_result(room_id(), placements)


## 순위표에 넣을 참가자 정보 (사람은 접속 id, 봇은 이름으로 라운드 사이에도 같은 사람으로 센다)
static func participant(f: Fighter) -> Dictionary:
    var bot := f.peer_id == 0
    return {"key": ("b:" + f.display_name) if bot else ("p:%d" % f.peer_id), "name": f.display_name, "bot": bot}


## 시리즈(여러 라운드) 정보 — 온라인 방이면 Net.room.series, 아니면 빈 값
func series() -> Dictionary:
    return Net.room.get("series", {}) if is_online_match() else {}


## 결과 화면에서 나가기: 온라인이면 방으로, 오프라인이면 메인 메뉴로
func leave_to_menu() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if is_online_match():
        Net.return_to_room()
    get_tree().change_scene_to_file(MENU_SCENE)


func restart_offline() -> void:
    get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
    # 결과 화면은 HUD 버튼으로 처리. Enter 는 보조 단축키 (Space 는 점프와 겹쳐 제외)
    var key := event as InputEventKey
    if state == State.ENDED and key and key.pressed and not key.echo \
            and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) \
            and (not is_online_match() or String(series().get("phase", "final")) == "final"):
        leave_to_menu()
        return
    if not is_online_match() and event.is_action_pressed(&"restart"):
        restart_offline()
