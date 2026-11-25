extends Control
## 터치 기기(모바일 웹·모바일 앱)용 화면 컨트롤
## - 왼쪽 아래: 이동 스틱 (화면 왼쪽 절반 어디를 눌러도 그 자리에 스틱이 생김)
## - 오른쪽 화면 드래그: 시점 회전
## - 오른쪽 아래 버튼: 밀치기(길게 누르면 차징), 점프
## - 결과 화면: 방으로 / 다시 하기 / 메인으로 버튼
## 멀티터치(스틱을 움직이며 동시에 시점 회전·버튼)를 지원한다.
## - 점프·밀치기 버튼을 누른 손가락을 그대로 끌면 시점도 함께 돌아간다
## - 시점 회전량은 손가락별로 직접 기록한 위치 차이로 계산한다.
##   (모바일 웹에서 여러 손가락을 동시에 쓰면 드래그 이벤트의 relative 값이 다른 손가락
##    기준으로 계산돼 크게 튀는 경우가 있어, 그 값을 쓰지 않는다)

const UI := preload("res://scripts/ui/ui_kit.gd")

const STICK_RADIUS := 80.0
const KNOB_RADIUS := 34.0
const DEAD_ZONE := 0.15
const LOOK_SENSITIVITY := 0.0045
const BUTTON_LOOK_SLOP := 10.0      # 버튼 손가락이 이만큼(px) 움직여야 시점 회전 시작 (누를 때 떨림 무시)
const MAX_LOOK_STEP := 90.0         # 한 번의 드래그 이벤트에서 인정하는 최대 이동(px) — 튀는 값 방지

var game: Node
var fighter: Fighter

var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_index := -1
var _push_index := -1
var _jump_index := -1
var _last_pos := {}                 # 손가락 index -> 마지막 위치
var _press_pos := {}                # 손가락 index -> 누른 위치
var _button_looking := {}           # 버튼 손가락이 시점 회전을 시작했는가
var _result_box: HBoxContainer


## 터치 컨트롤을 켤지: 휴대폰·태블릿
static func should_enable() -> bool:
    return Fighter.touch_device()


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    fighter.touch_mode = true

    _result_box = UI.hbox(14)
    _result_box.visible = false
    add_child(_result_box)
    if game.is_online_match():
        _add_result_button("방으로 돌아가기", UI.PRIMARY, func(): game.leave_to_menu())
    else:
        _add_result_button("다시 하기", UI.PRIMARY, func(): get_tree().reload_current_scene())
        _add_result_button("메인으로", UI.SECONDARY, func(): game.leave_to_menu())


func _add_result_button(text: String, color: Color, cb: Callable) -> void:
    var b := UI.colored_button(text, color, color.lightened(0.15))
    b.custom_minimum_size = Vector2(220, 64)
    b.add_theme_font_size_override("font_size", 22)
    b.pressed.connect(cb)
    _result_box.add_child(b)


func _scr() -> Vector2:
    return get_viewport_rect().size


func _push_center() -> Vector2:
    var s := _scr()
    return Vector2(s.x - 120, s.y - 120)


func _jump_center() -> Vector2:
    var s := _scr()
    return Vector2(s.x - 255, s.y - 85)


func _push_radius() -> float:
    return 66.0


func _jump_radius() -> float:
    return 50.0


func _input(event: InputEvent) -> void:
    if fighter == null:
        return
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        if t.pressed:
            _on_touch_down(t.index, t.position)
        else:
            _on_touch_up(t.index)
    elif event is InputEventScreenDrag:
        var d := event as InputEventScreenDrag
        var last: Vector2 = _last_pos.get(d.index, d.position)
        _last_pos[d.index] = d.position
        if d.index == _stick_index:
            _stick_pos = d.position
            _update_stick()
        elif d.index == _look_index:
            _look(d.position - last)
        elif d.index == _push_index or d.index == _jump_index:
            # 버튼을 누른 채 끌기 → 시점 회전 (조금 움직인 뒤부터)
            if not _button_looking.get(d.index, false):
                if d.position.distance_to(_press_pos.get(d.index, d.position)) < BUTTON_LOOK_SLOP:
                    return
                _button_looking[d.index] = true
                last = d.position          # 문턱을 넘는 순간 시점이 튀지 않게
            _look(d.position - last)


func _look(delta_px: Vector2) -> void:
    if delta_px.length() > MAX_LOOK_STEP:
        delta_px = delta_px.normalized() * MAX_LOOK_STEP
    fighter.apply_look(delta_px * LOOK_SENSITIVITY)


func _on_touch_down(index: int, pos: Vector2) -> void:
    _last_pos[index] = pos
    _press_pos[index] = pos
    _button_looking.erase(index)
    if _result_box.visible:
        return   # 결과 화면에선 버튼(Control)이 처리
    if pos.distance_to(_push_center()) <= _push_radius() + 12.0:
        _push_index = index
        fighter.touch_push = true
        return
    if pos.distance_to(_jump_center()) <= _jump_radius() + 12.0:
        _jump_index = index
        fighter.touch_jump = true
        return
    if pos.x < _scr().x * 0.45 and _stick_index == -1:
        _stick_index = index
        _stick_origin = pos
        _stick_pos = pos
        _update_stick()
        return
    if _look_index == -1:
        _look_index = index


func _on_touch_up(index: int) -> void:
    _last_pos.erase(index)
    _press_pos.erase(index)
    _button_looking.erase(index)
    if index == _stick_index:
        _stick_index = -1
        fighter.touch_move = Vector2.ZERO
    elif index == _look_index:
        _look_index = -1
    elif index == _push_index:
        _push_index = -1
        fighter.touch_push = false
    elif index == _jump_index:
        _jump_index = -1


func _update_stick() -> void:
    var off := _stick_pos - _stick_origin
    if off.length() > STICK_RADIUS:
        off = off.normalized() * STICK_RADIUS
    var v := off / STICK_RADIUS
    fighter.touch_move = v if v.length() > DEAD_ZONE else Vector2.ZERO


func _process(_delta: float) -> void:
    var ended: bool = game.state == PartyGame.State.ENDED
    _result_box.visible = ended
    if ended:
        _result_box.size = _result_box.get_minimum_size()
        _result_box.position = Vector2((_scr().x - _result_box.size.x) * 0.5, _scr().y * 0.30 + 150)
        _stick_index = -1
        _look_index = -1
        fighter.touch_move = Vector2.ZERO
        fighter.touch_push = false
    queue_redraw()


func _draw() -> void:
    if _result_box.visible or fighter.dead:
        return
    var s := _scr()
    # 이동 스틱 (누르지 않을 땐 기본 위치에 흐리게)
    var origin := _stick_origin if _stick_index != -1 else Vector2(150, s.y - 150)
    var knob := origin + fighter.touch_move * STICK_RADIUS if _stick_index != -1 else origin
    draw_circle(origin, STICK_RADIUS, Color(1, 1, 1, 0.18 if _stick_index != -1 else 0.1))
    draw_arc(origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
    draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, 0.55 if _stick_index != -1 else 0.3))

    # 밀치기 버튼 (차징 게이지 링 포함)
    var pc := _push_center()
    var pushing := _push_index != -1
    var cd_ready := fighter.cooldown_timer <= 0.0
    var push_col := UI.PRIMARY if cd_ready else Color(0.55, 0.58, 0.65)
    push_col.a = 0.85 if pushing else 0.6
    draw_circle(pc, _push_radius(), push_col)
    draw_arc(pc, _push_radius(), 0, TAU, 48, Color(UI.INK, 0.8), 4.0, true)
    if fighter.charging:
        var c := fighter.get_charge_ratio()
        draw_arc(pc, _push_radius() + 7, -PI * 0.5, -PI * 0.5 + TAU * c, 48, UI.YELLOW, 7.0, true)
    elif not cd_ready:
        var f := 1.0 - fighter.cooldown_timer / maxf(fighter.cooldown_total, 0.01)
        draw_arc(pc, _push_radius() + 7, -PI * 0.5, -PI * 0.5 + TAU * f, 48, Color(1, 1, 1, 0.6), 5.0, true)
    _draw_label(pc, "밀치기", 22)

    # 점프 버튼
    var jc := _jump_center()
    var jcol := UI.TEAL
    jcol.a = 0.85 if _jump_index != -1 else 0.6
    draw_circle(jc, _jump_radius(), jcol)
    draw_arc(jc, _jump_radius(), 0, TAU, 48, Color(UI.INK, 0.8), 4.0, true)
    _draw_label(jc, "점프", 20)


func _draw_label(center: Vector2, text: String, size: int) -> void:
    var font: Font = UI.DISPLAY_FONT
    var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    draw_string(font, center + Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
