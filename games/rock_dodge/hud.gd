extends Control
## HUD: 생존/시간, 카운트다운·결과 메시지, 풍향 나침반(카메라 기준), 밀치기 게이지/쿨타임

var game: Node

const UI := preload("res://scripts/ui/ui_kit.gd")
const SeriesPanel := preload("res://scripts/ui/series_panel.gd")
const Teams := preload("res://scripts/core/teams.gd")

var _top: Label
var _center: Label
var _sub: Label
var _help: Label
var _wind_label: Label
var _skill_label: Label
var _status_label: Label
var _feed_labels: Array[Label] = []
var _touch := false

const BAR_W := 280.0
const BAR_H := 14.0


func _ready() -> void:
    _touch = Fighter.touch_device()
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    _help = _make_label(16)
    if _touch:
        _help.text = "왼쪽 스틱 이동 · 오른쪽 드래그 시점 · 점프 · 밀치기 (길게 누르면 차징 돌진)"
    else:
        _help.text = "WASD 이동 · 마우스 시점 · Space 점프 · 좌클릭/E 밀치기 (길게 누르면 차징 돌진)%s · Esc 마우스 해제 (오른쪽 위 버튼 사용)" \
                % ("" if game.is_online_match() else " · R 재시작")
    _help.position = Vector2(22, 20)
    _build_menu_bar()
    _build_result_box()
    _build_spectate_bar()

    _top = _make_label(24, true)
    _top.add_theme_constant_override("outline_size", 0)
    _top.add_theme_color_override("font_color", UI.CREAM)
    _top.add_theme_stylebox_override("normal", UI.box(UI.INK, 22, 20, UI.INK, 0, 4))
    _center = _make_label(80, true)
    _center.add_theme_color_override("font_color", UI.YELLOW)
    _center.add_theme_constant_override("outline_size", 14)
    _center.add_theme_color_override("font_shadow_color", Color(UI.INK, 0.5))
    _center.add_theme_constant_override("shadow_offset_x", 5)
    _center.add_theme_constant_override("shadow_offset_y", 5)
    _center.add_theme_constant_override("shadow_outline_size", 14)
    _sub = _make_label(22, true)
    _wind_label = _make_label(16)
    _skill_label = _make_label(18)
    _status_label = _make_label(18)
    for i in 5:
        var l := _make_label(18)
        l.position = Vector2(22, 62 + i * 30)
        _feed_labels.append(l)


## display: 제목 글꼴(Jua). 글자는 흰색 + 남색 테두리 (어떤 배경 위에서도 보이게)
func _make_label(font_size: int, display: bool = false) -> Label:
    var l := Label.new()
    if display:
        l.add_theme_font_override("font", UI.DISPLAY_FONT)
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", Color.WHITE)
    l.add_theme_color_override("font_outline_color", Color(UI.INK, 0.85))
    l.add_theme_constant_override("outline_size", maxi(4, font_size / 5))
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(l)
    return l


func _screen() -> Vector2:
    return get_viewport_rect().size


func _place_centered(l: Label, y: float) -> void:
    l.size = l.get_minimum_size()
    l.position = Vector2((_screen().x - l.size.x) * 0.5, y)


func _process(delta: float) -> void:
    if game == null:
        return
    _tick_leave(delta)
    if _bar:
        _bar.position = Vector2(_screen().x - _bar.size.x - 22.0, 18.0)
    _update_result_box()
    _update_spectate(delta)
    var scr := _screen()
    var alive: int = game.alive_fighters().size()
    var total: int = game.fighters.size()
    var my_kills: int = game.human.kills if game.human else 0
    _top.text = "생존 %d / %d     %s     킬 %d" % [alive, total, _fmt_time(game.elapsed), my_kills]
    if game.teams >= 2:
        # 팀전: 팀별 생존 인원
        var parts := PackedStringArray()
        for t in game.teams:
            var n := 0
            for f in game.fighters:
                if f.team == t and not f.dead:
                    n += 1
            parts.append("%s %d" % [Teams.SHORT[t], n])
        _top.text = "  ".join(parts) + "     %s     킬 %d" % [_fmt_time(game.elapsed), my_kills]
    var ser: Dictionary = game.series()
    if int(ser.get("total", 1)) > 1:
        _top.text = "라운드 %d/%d     " % [int(ser.round), int(ser.total)] + _top.text
    _place_centered(_top, 52)

    var center := ""
    var sub := ""
    var human: Fighter = game.human
    match game.state:
        PartyGame.State.COUNTDOWN:
            center = str(int(ceil(game.countdown_time - game.state_time)))
            sub = "떨어지는 돌을 피하고, 상대를 밀쳐내 살아남으세요"
            if game.is_client() and game.play_start_t < 0.0:
                center = "…"
                sub = "다른 플레이어를 기다리는 중"
        PartyGame.State.PLAYING:
            if game.state_time < 0.8:
                center = "시작!"
            elif game.elapsed - game.last_intensify_time < 1.5 and alive > 1:
                center = "낙석 증가!"
                sub = "남은 인원 %d명" % alive
            elif human and human.dead:
                center = "탈락!"
                sub = "생존 %s · 아래 버튼으로 다른 사람 시점을 볼 수 있어요" % _fmt_time(game.human_death_time)
        PartyGame.State.ENDED:
            var w: Fighter = game.winner
            if game.teams >= 2:
                if game.winner_team < 0:
                    center = "무승부"
                elif human and human.team == game.winner_team:
                    center = "우리 팀 승리!"
                else:
                    center = "%s 승리" % Teams.team_name(game.winner_team)
            elif total == 1:
                center = "게임 오버"
            elif w == null:
                center = "무승부"
            elif w == human:
                center = "승리!"
            else:
                center = "%s 승리" % w.display_name
            var t: float = game.human_death_time if game.human_death_time >= 0.0 else game.elapsed
            sub = "내 생존 시간 %s · 킬 %d" % [_fmt_time(t), my_kills]
    _center.text = center
    _sub.text = sub
    _play_event_sounds(center, human)
    _place_centered(_center, scr.y * 0.30)
    _place_centered(_sub, scr.y * 0.30 + 96)

    var spd: float = game.wind.length()
    _wind_label.text = "바람 %.1f m/s" % spd
    _wind_label.size = _wind_label.get_minimum_size()
    _wind_label.position = Vector2(scr.x - 90 - _wind_label.size.x * 0.5, 206)

    _skill_label.text = _skill_text()
    _place_centered(_skill_label, scr.y - 100)

    _status_label.text = _status_text()
    _status_label.size = _status_label.get_minimum_size()
    _status_label.position = Vector2(16, scr.y - 40)

    var feed: Array = game.kill_feed
    for i in _feed_labels.size():
        var l := _feed_labels[i]
        if i < feed.size():
            var e: Dictionary = feed[i]
            var age: float = game.elapsed - e["time"]
            l.text = e["text"]
            var c: Color = e["color"]
            c.a = clampf(1.0 - (age - 5.0), 0.0, 1.0)
            l.add_theme_color_override("font_color", c)
            l.visible = c.a > 0.0
        else:
            l.visible = false
    queue_redraw()


func _skill_text() -> String:
    var h: Fighter = game.human
    if h == null or h.dead:
        return ""
    var extra := "   [무적]" if h.is_invulnerable() else ""
    if h.is_stunned():
        return "경직!" + extra
    if h.charging:
        var c := h.get_charge_ratio()
        if h.charge_time < h.tap_threshold:
            return "밀치기" + extra
        if c >= 0.999:
            return "풀차징! 놓으면 돌진" + extra
        return "차징 %d%%" % int(c * 100.0) + extra
    if h.cooldown_timer > 0.0:
        return "쿨타임 %.1f초" % h.cooldown_timer + extra
    return "밀치기 준비 — 좌클릭/E" + extra


func _status_text() -> String:
    var h: Fighter = game.human
    if h == null or h.dead:
        return ""
    var parts: PackedStringArray = []
    if h.helmets > 0:
        parts.append("헬멧 %d/%d" % [h.helmets, Fighter.MAX_HELMETS])
    if h.charge_stacks > 0:
        parts.append("차징 가속 ×%d" % h.charge_stacks)
    if h.cooldown_stacks > 0:
        parts.append("쿨타임 감소 ×%d" % h.cooldown_stacks)
    if h.glove_stacks > 0:
        parts.append("글러브 ×%d" % h.glove_stacks)
    if h.shield_timer > 0.0:
        parts.append("무적 %.1f초" % h.shield_timer)
    return "  ·  ".join(parts)


func _fmt_time(t: float) -> String:
    return "%02d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func _draw() -> void:
    if game == null:
        return
    _draw_wind_compass()
    _draw_skill_bar()


func _draw_wind_compass() -> void:
    var scr := _screen()
    var c := Vector2(scr.x - 90, 146)       # 오른쪽 위 버튼 줄 아래
    var r := 46.0
    draw_circle(c, r + 4, UI.INK)
    draw_circle(c, r, UI.CREAM)
    for i in 12:
        var a := i * TAU / 12.0
        draw_line(c + Vector2(cos(a), sin(a)) * (r - 6), c + Vector2(cos(a), sin(a)) * (r - 2), Color(UI.INK, 0.35), 2.0)
    # 위쪽 = 카메라 정면
    draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 1), c + Vector2(-6, -r + 9), c + Vector2(6, -r + 9)]), UI.RED)

    var human: Fighter = game.human
    if human == null:
        return
    var cam := get_viewport().get_camera_3d()
    if cam == null:
        return
    var fwd := -cam.global_transform.basis.z
    var yaw := atan2(-fwd.x, -fwd.z)          # 카메라가 보는 방향 (캐릭터 방향과 다를 수 있음)
    var w: Vector2 = game.wind
    var spd := w.length()
    if spd < 0.05:
        draw_circle(c, 5, UI.INK)
        return
    var local := Vector3(w.x, 0, w.y).rotated(Vector3.UP, -yaw)
    var dir := Vector2(local.x, local.z).normalized()
    var len := clampf(spd / 8.0, 0.25, 1.0) * (r - 6)
    var tip := c + dir * len
    var tail := c - dir * len * 0.6
    var col := UI.BLUE.lerp(UI.RED, clampf(spd / 8.0, 0.0, 1.0))
    draw_line(tail, tip, col, 4.0, true)
    var side := Vector2(-dir.y, dir.x)
    draw_colored_polygon(PackedVector2Array([tip + dir * 6, tip - dir * 10 + side * 8, tip - dir * 10 - side * 8]), col)


func _draw_skill_bar() -> void:
    var h: Fighter = game.human
    if h == null or h.dead:
        return
    var scr := _screen()
    var pos := Vector2((scr.x - BAR_W) * 0.5, scr.y - 70)
    var frame := StyleBoxFlat.new()
    frame.bg_color = UI.CREAM
    frame.border_color = UI.INK
    frame.set_border_width_all(3)
    frame.set_corner_radius_all(int(BAR_H * 0.5 + 4))
    draw_style_box(frame, Rect2(pos - Vector2(5, 5), Vector2(BAR_W + 10, BAR_H + 10)))
    var fill := 0.0
    var col := UI.TEAL
    if h.charging:
        fill = h.get_charge_ratio()
        col = UI.YELLOW.lerp(UI.RED, fill)
        if fill >= 0.999:
            col = col.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.025))
    elif h.cooldown_timer > 0.0:
        fill = 1.0 - h.cooldown_timer / maxf(h.cooldown_total, 0.01)
        col = UI.BLUE
    else:
        fill = 1.0
    if fill > 0.02:
        var bar := StyleBoxFlat.new()
        bar.bg_color = col
        bar.set_corner_radius_all(int(BAR_H * 0.5))
        draw_style_box(bar, Rect2(pos, Vector2(maxf(BAR_W * fill, BAR_H), BAR_H)))


# ---- 소리: 화면에 뜨는 큰 글자·상태 변화에 맞춰 효과음
var _last_center := ""
var _last_state := -1
var _last_wind := Vector2.ZERO


func _play_event_sounds(center: String, human: Fighter) -> void:
    if _last_state == -1:
        Sfx.bgm("match")
    if center != _last_center:
        if game.state == PartyGame.State.COUNTDOWN and center.is_valid_int():
            Sfx.play("count_tick")
        elif center == "시작!":
            Sfx.play("count_go")
        elif center == "낙석 증가!":
            Sfx.play("whistle", -4.0, 1.15)
    if game.state != _last_state and game.state == PartyGame.State.ENDED:
        Sfx.duck(3.5)
        if game.winner != null and game.winner == human:
            Sfx.play("win")
        elif human == null or not human.dead:
            Sfx.play("whistle")
    var wt: Vector2 = game.get("_wind_target") if game.get("_wind_target") != null else Vector2.ZERO
    if _last_state != -1 and wt.distance_to(_last_wind) > 1.5 and wt.length() > 2.0:
        Sfx.play("wind", minf(wt.length() - 4.0, 4.0))
    _last_wind = wt
    _last_center = center
    _last_state = game.state




# ---- 오른쪽 위 버튼: 소리 켬/끔 · (혼자 연습) 다시 하기 · 나가기
var _leave_btn: Button
var _bar: HBoxContainer
var _leave_armed := 0.0


func _build_menu_bar() -> void:
    var bar := UI.hbox(12)
    bar.add_to_group("touch_block")      # 터치 조작(스틱·시점)이 이 영역은 무시
    add_child(bar)
    _bar = bar
    # 시점 버튼 (모든 게임 공통): 기본 → 넓은 → 전체 시점 (PC 는 V 키도)
    _view_btn = UI.pill_button("기본 시점", UI.BLUE)
    _view_btn.focus_mode = Control.FOCUS_NONE
    _view_btn.pressed.connect(func():
        var h: Fighter = game.human
        if h:
            h.cycle_view())
    bar.add_child(_view_btn)
    bar.add_child(UI.sound_button())
    if not game.is_online_match():
        var again := UI.pill_button("다시 하기", UI.YELLOW, UI.INK)
        again.pressed.connect(func(): game.restart_offline())
        bar.add_child(again)
    _leave_btn = UI.pill_button("나가기", UI.RED)
    _leave_btn.pressed.connect(_on_leave_pressed)
    bar.add_child(_leave_btn)


## 온라인 경기 도중이면 한 번 더 눌러야 나감 (기권 처리되므로)
func _on_leave_pressed() -> void:
    var human: Fighter = game.human
    var risky: bool = game.is_online_match() and game.state != PartyGame.State.ENDED and human != null and not human.dead
    if risky and _leave_armed <= 0.0:
        _leave_armed = 3.0
        _leave_btn.text = "정말 나가기? (기권)"
        return
    game.leave_to_menu()


var _view_btn: Button
var _view_idx := -1


func _tick_leave(delta: float) -> void:
    var h: Fighter = game.human if game else null
    if _view_btn and h and h.spring_arm:
        var i := h.view_index()
        if i != _view_idx:
            _view_idx = i
            _view_btn.text = String(Fighter.VIEW_NAMES[i])
    if _leave_armed > 0.0:
        _leave_armed -= delta
        if _leave_armed <= 0.0:
            _leave_btn.text = "나가기"



# ---- 결과 화면 버튼 (모든 기기): 온라인 = 방으로 돌아가기 / 혼자 연습 = 다시 하기 · 메인으로
var _result_box: HBoxContainer
var _was_ended := false


func _build_result_box() -> void:
    _result_box = UI.hbox(14)
    _result_box.visible = false
    _result_box.add_to_group("touch_block")
    add_child(_result_box)
    if game.is_online_match():
        # 온라인: 라운드 결과·합계 점수·다음 라운드 레디 (모든 게임 공통 패널)
        var panel := SeriesPanel.new()
        panel.game = game
        add_child(panel)
    else:
        _add_result_button("다시 하기", UI.PRIMARY, func(): game.restart_offline())
        _add_result_button("메인으로", UI.SECONDARY, func(): game.leave_to_menu())


func _add_result_button(text: String, color: Color, cb: Callable) -> void:
    var b := UI.colored_button(text, color, color.lightened(0.15))
    b.custom_minimum_size = Vector2(220, 64)
    b.add_theme_font_size_override("font_size", 22)
    b.pressed.connect(cb)
    _result_box.add_child(b)


func _update_result_box() -> void:
    var ended: bool = game.state == PartyGame.State.ENDED
    _result_box.visible = ended and not game.is_online_match()
    if ended:
        if not _was_ended:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE      # 버튼을 누를 수 있게 마우스 풀기
        _result_box.size = _result_box.get_minimum_size()
        _result_box.position = Vector2((_screen().x - _result_box.size.x) * 0.5, _screen().y * 0.30 + 150)
    _was_ended = ended


# ---- 관전 (내가 탈락한 뒤): 살아 있는 다른 사람 시점으로 카메라를 옮긴다. ◀ ▶ 버튼 (키보드 ← →)
var _spec_bar: HBoxContainer
var _spec_label: Label
var _spec_wait := 0.0          # 보던 사람이 탈락하면 잠깐 보여 준 뒤 다음 사람으로
var _was_dead := false


func _build_spectate_bar() -> void:
    _spec_bar = UI.hbox(10)
    _spec_bar.visible = false
    _spec_bar.add_to_group("touch_block")
    add_child(_spec_bar)
    var prev := UI.pill_button("◀ 이전", UI.INK)
    prev.custom_minimum_size = Vector2(110, 52)
    prev.focus_mode = Control.FOCUS_NONE
    prev.pressed.connect(func(): _cycle_spectate(-1))
    _spec_bar.add_child(prev)
    _spec_label = Label.new()
    _spec_label.add_theme_font_override("font", UI.DISPLAY_FONT)
    _spec_label.add_theme_font_size_override("font_size", 22)
    _spec_label.add_theme_color_override("font_color", UI.INK)
    _spec_label.add_theme_stylebox_override("normal", UI.box(UI.CREAM, 18, 16, UI.INK, 3, 4))
    _spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _spec_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _spec_label.custom_minimum_size = Vector2(240, 52)
    _spec_bar.add_child(_spec_label)
    var next := UI.pill_button("다음 ▶", UI.INK)
    next.custom_minimum_size = Vector2(110, 52)
    next.focus_mode = Control.FOCUS_NONE
    next.pressed.connect(func(): _cycle_spectate(1))
    _spec_bar.add_child(next)


## 관전할 수 있는 사람 (나 빼고 살아 있는 캐릭터)
func _spectate_candidates() -> Array[Fighter]:
    var out: Array[Fighter] = []
    for f: Fighter in game.alive_fighters():
        if f != game.human:
            out.append(f)
    return out


func _cycle_spectate(dir: int) -> void:
    var human: Fighter = game.human
    if human == null or not human.dead:
        return
    var list := _spectate_candidates()
    if list.is_empty():
        return
    var i := list.find(human.spectating)
    i = (0 if dir > 0 else list.size() - 1) if i < 0 else posmod(i + dir, list.size())
    human.set_spectate(list[i])
    _spec_wait = 1.2


func _update_spectate(delta: float) -> void:
    var human: Fighter = game.human
    var dead: bool = human != null and human.dead and game.state == PartyGame.State.PLAYING
    if dead and not _was_dead:
        # 방금 탈락: 마우스를 풀어 버튼을 누를 수 있게 하고, 1초 뒤 나를 떨어뜨린 사람(없으면 아무나)을 비춘다
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _spec_wait = 1.0
    _was_dead = dead
    var list := _spectate_candidates() if dead else ([] as Array[Fighter])
    _spec_bar.visible = dead and not list.is_empty()
    if not dead:
        return
    var cur: Fighter = human.spectating
    if cur == null or cur.dead:
        # 아직 아무도 안 봄 → 1초 뒤 / 보던 사람이 탈락 → 1.2초 보여 준 뒤 다음 사람으로
        _spec_wait -= delta
        if _spec_wait <= 0.0 and not list.is_empty():
            var pick: Fighter = list[0]
            var killer: Fighter = human.last_attacker
            if cur == null and killer and not killer.dead and killer != human:
                pick = killer
            human.set_spectate(pick)
            _spec_wait = 1.2
    if _spec_bar.visible:
        var who: Fighter = human.spectating
        _spec_label.text = ("관전: %s" % who.display_name) if who and not who.dead else "관전"
        _spec_bar.size = _spec_bar.get_minimum_size()
        var y := _screen().y - _spec_bar.size.y - (200.0 if _touch else 90.0)
        _spec_bar.position = Vector2((_screen().x - _spec_bar.size.x) * 0.5, y)


func _unhandled_key_input(event: InputEvent) -> void:
    var k := event as InputEventKey
    if k == null or not k.pressed or k.echo:
        return
    if _spec_bar and _spec_bar.visible:
        if k.keycode == KEY_LEFT:
            Sfx.play("click")
            _cycle_spectate(-1)
            get_viewport().set_input_as_handled()
        elif k.keycode == KEY_RIGHT:
            Sfx.play("click")
            _cycle_spectate(1)
            get_viewport().set_input_as_handled()
