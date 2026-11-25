extends Control
## HUD: 생존/시간, 카운트다운·결과 메시지, 풍향 나침반(카메라 기준), 밀치기 게이지/쿨타임

var game: Node

const UI := preload("res://scripts/ui/ui_kit.gd")

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
        _help.text = "WASD 이동 · 마우스 시점 · Space 점프 · 좌클릭/E 밀치기 (길게 누르면 차징 돌진)%s · Esc 마우스 해제 · M 소리" \
                % ("" if game.is_online_match() else " · R 재시작")
    _help.position = Vector2(16, 10)

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
        l.position = Vector2(16, 44 + i * 26)
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


func _process(_delta: float) -> void:
    if game == null:
        return
    var scr := _screen()
    var alive: int = game.alive_fighters().size()
    var total: int = game.fighters.size()
    var my_kills: int = game.human.kills if game.human else 0
    _top.text = "생존 %d / %d     %s     킬 %d" % [alive, total, _fmt_time(game.elapsed), my_kills]
    _place_centered(_top, 14 + 24)

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
                var watch_hint := "끝나면 방으로 돌아갑니다" if game.is_online_match() else ("끝나면 다시 할 수 있습니다" if _touch else "R 다시 하기")
                sub = "생존 %s · 관전 중 · %s" % [_fmt_time(game.human_death_time), watch_hint]
        PartyGame.State.ENDED:
            var w: Fighter = game.winner
            if total == 1:
                center = "게임 오버"
            elif w == null:
                center = "무승부"
            elif w == human:
                center = "승리!"
            else:
                center = "%s 승리" % w.display_name
            var t: float = game.human_death_time if game.human_death_time >= 0.0 else game.elapsed
            var hint := "Enter 방으로 돌아가기" if game.is_online_match() else "R 다시 하기 · Enter 메인 메뉴"
            if _touch:
                hint = "아래 버튼을 누르세요"
            sub = "내 생존 시간 %s · 킬 %d · %s" % [_fmt_time(t), my_kills, hint]
    _center.text = center
    _sub.text = sub
    _play_event_sounds(center, human)
    _place_centered(_center, scr.y * 0.30)
    _place_centered(_sub, scr.y * 0.30 + 96)

    var spd: float = game.wind.length()
    _wind_label.text = "바람 %.1f m/s" % spd
    _wind_label.size = _wind_label.get_minimum_size()
    _wind_label.position = Vector2(scr.x - 90 - _wind_label.size.x * 0.5, 150)

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
    if h.heavy_timer > 0.0:
        parts.append("무거운 신발 %.0f초" % ceilf(h.heavy_timer))
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
    var c := Vector2(scr.x - 90, 90)
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
    var yaw := human.rotation.y
    if human.dead and human.pitch_pivot:
        yaw += human.pitch_pivot.rotation.y
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



## M: 소리 켜기/끄기
func _unhandled_key_input(event: InputEvent) -> void:
    var k := event as InputEventKey
    if k and k.pressed and not k.echo and k.keycode == KEY_M:
        Sfx.set_enabled(not Sfx.enabled)
