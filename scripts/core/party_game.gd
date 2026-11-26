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
    if TOUCH_SCRIPT.should_enable() and human:
        var touch: Control = TOUCH_SCRIPT.new()
        touch.game = self
        touch.fighter = human
        layer.add_child(touch)
        layer.add_child(ROTATE_HINT.new())


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
            and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
        leave_to_menu()
        return
    if not is_online_match() and event.is_action_pressed(&"restart"):
        restart_offline()
