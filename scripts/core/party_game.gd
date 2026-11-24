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

const TOUCH_SCRIPT := preload("res://scripts/ui/touch_controls.gd")
const ROTATE_HINT := preload("res://scripts/ui/rotate_hint.gd")
const MENU_SCENE := "res://scenes/app.tscn"

enum State { COUNTDOWN, PLAYING, ENDED }

@export var arena_half := 18.0
@export var countdown_time := 3.0

var module_id := ""
var terrain: Node
var grass_material: ShaderMaterial
## 온라인 방에서 시작한 경우 Net.match_config (비어 있으면 오프라인 연습)
var online_match: Dictionary = {}

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


func alive_fighters() -> Array[Fighter]:
    var out: Array[Fighter] = []
    for f in fighters:
        if not f.dead:
            out.append(f)
    return out


## 캐릭터 머리 위 등에 잠깐 떠오르는 문구
func popup_text(pos: Vector3, text: String, color: Color) -> void:
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
    if state == State.ENDED and event.is_action_pressed(&"ui_accept"):
        leave_to_menu()
        return
    if not is_online_match() and event.is_action_pressed(&"restart"):
        restart_offline()
