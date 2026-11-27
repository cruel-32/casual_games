extends "res://games/rock_dodge/hud.gd"
## 무궁화 꽃이 피었습니다 화면
##   위: 남은 시간·통과·탈락 / 가운데: 외침 글자(말한 음절만 밝게) · "멈춰!" / 오른쪽: 진행 막대(모두의 위치)
##   빨간불이면 화면 가장자리가 붉게. 오른쪽 위 메뉴·결과 버튼·관전은 돌피하기 화면 것을 그대로 씀

var _chant: Label
var _result_shown := false


func _ready() -> void:
    _touch = Fighter.touch_device()
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _help = _make_label(16)
    if _touch:
        _help.text = "왼쪽 스틱 이동 · 오른쪽 드래그 시점 · 초록불에만 달리고 빨간불엔 멈춰요 · 밀치기로 방해!"
    else:
        _help.text = "WASD 이동 · 마우스 시점 · 초록불에만 달리고, 술래가 돌아보면 멈춰요 · 좌클릭/E 밀치기%s" \
                % ("" if game.is_online_match() else " · R 재시작")
    _help.position = Vector2(16, 10)
    _build_menu_bar()
    _build_result_box()
    _build_spectate_bar()
    _top = _make_label(24, true)
    _top.add_theme_constant_override("outline_size", 0)
    _top.add_theme_color_override("font_color", UI.CREAM)
    _top.add_theme_stylebox_override("normal", UI.box(UI.INK, 22, 20, UI.INK, 0, 4))
    _chant = _make_label(64, true)
    _center = _make_label(96, true)
    _center.add_theme_constant_override("outline_size", 16)
    _sub = _make_label(22, true)
    _status_label = _make_label(20, true)
    for i in 5:
        var l := _make_label(18)
        l.position = Vector2(16, 44 + i * 26)
        _feed_labels.append(l)


func _spectate_candidates() -> Array[Fighter]:
    var out: Array[Fighter] = []
    for f: Fighter in game.runners():
        if f != game.human:
            out.append(f)
    return out


func _process(delta: float) -> void:
    if game == null:
        return
    _tick_leave(delta)
    if _bar:
        _bar.position = Vector2(_screen().x - _bar.size.x - 14.0, 12.0)
    _update_result_box()
    _update_spectate(delta)
    var scr := _screen()
    var now: float = game.net_now()
    var ph: Array = game.phase_at(now)
    var kind: String = ph[0]
    var left: float = maxf(game.TIME_LIMIT - game.elapsed, 0.0) if game.state == PartyGame.State.PLAYING else game.TIME_LIMIT
    var outs: int = game.out_info.size()
    _top.text = "⏱ %d초     통과 %d     탈락 %d     남은 %d" % [int(ceil(left)), game.finished.size(), outs, game.runners().size()]
    var ser: Dictionary = game.series()
    if int(ser.get("total", 1)) > 1:
        _top.text = "라운드 %d/%d     " % [int(ser.round), int(ser.total)] + _top.text
    _place_centered(_top, 14 + 24)

    var human: Fighter = game.human
    var chant := ""
    var center := ""
    var sub := ""
    var center_col := UI.YELLOW
    match game.state:
        PartyGame.State.COUNTDOWN:
            center = str(int(ceil(game.countdown_time - game.state_time)))
            sub = "술래가 \"무궁화 꽃이 피었습니다\"를 외치는 동안만 달려요"
            if game.is_client() and game.play_start_t < 0.0:
                center = "…"
                sub = "다른 플레이어를 기다리는 중"
        PartyGame.State.PLAYING:
            if kind == "wait":
                center = "준비…"
                sub = "아직 움직이지 마세요"
                center_col = UI.CREAM
            elif kind == "green" or kind == "turn":
                var said := int(ph[2])
                var parts := PackedStringArray()
                for k in said:
                    parts.append(game.SYLLABLES[k])
                if said == 0:
                    chant = "…"                 # 뒤돌았지만 아직 말이 없음 (움직여도 됨)
                chant += "".join(parts.slice(0, mini(said, 3))) + (" " + "".join(parts.slice(3, mini(said, 5))) if said > 3 else "") \
                        + (" " + "".join(parts.slice(5, said)) if said > 5 else "")
                sub = "달려요!" if kind == "green" else "곧 돌아봐요!"
            elif kind == "red":
                center = "멈춰!"
                center_col = UI.RED
                sub = "움직이면 탈락"
            if human and human.dead:
                sub = game.human_result + " · 아래 버튼으로 다른 사람 시점을 볼 수 있어요"
            elif human and game.is_finished(human):
                sub = game.human_result + " · 다른 사람을 기다려요"
        PartyGame.State.ENDED:
            center = game.winner_text
            center_col = UI.YELLOW
            sub = game.human_result if game.human_result != "" else ""
    _chant.text = chant
    _chant.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if kind == "green" else UI.YELLOW)
    _center.text = center
    _center.add_theme_color_override("font_color", center_col)
    _sub.text = sub
    _play_sounds(center, human)
    _place_centered(_chant, scr.y * 0.16)
    _place_centered(_center, scr.y * 0.24)
    _place_centered(_sub, scr.y * 0.24 + 118)

    var feed: Array = game.feed
    var t_now := Time.get_ticks_msec() / 1000.0
    for i in _feed_labels.size():
        var l := _feed_labels[i]
        if i < feed.size():
            var e: Dictionary = feed[i]
            var c: Color = e["color"]
            c.a = clampf(1.0 - (t_now - float(e["time"]) - 5.0), 0.0, 1.0)
            l.text = e["text"]
            l.add_theme_color_override("font_color", c)
            l.visible = c.a > 0.0
        else:
            l.visible = false
    queue_redraw()


func _draw() -> void:
    if game == null:
        return
    var scr := _screen()
    var ph: Array = game.phase_at(game.net_now())
    # 빨간불: 화면 가장자리를 붉게
    if game.state == PartyGame.State.PLAYING and (ph[0] == "red" or ph[0] == "turn"):
        var a := 0.28 if ph[0] == "red" else 0.12
        var w := 26.0
        var c := Color(0.95, 0.1, 0.12, a)
        draw_rect(Rect2(0, 0, scr.x, w), c)
        draw_rect(Rect2(0, scr.y - w, scr.x, w), c)
        draw_rect(Rect2(0, 0, w, scr.y), c)
        draw_rect(Rect2(scr.x - w, 0, w, scr.y), c)
    _draw_light(scr, ph)
    _draw_progress(scr)


## 신호등 (위 가운데): 초록 = 달려요, 빨강 = 멈춰요 (돌아보는 중엔 노랑)
func _draw_light(scr: Vector2, ph: Array) -> void:
    if game.state != PartyGame.State.PLAYING:
        return
    var lab: Label = _chant if _chant.text != "" else _center
    if lab.text == "":
        return
    var c := Vector2(lab.position.x - 44.0, lab.position.y + lab.size.y * 0.5)
    var col := UI.RED
    if ph[0] == "green":
        col = Color(0.3, 0.9, 0.45)
    elif ph[0] == "turn":
        col = UI.YELLOW
    draw_circle(c, 34.0, UI.INK)
    draw_circle(c, 28.0, col)
    draw_circle(c + Vector2(-9, -9), 8.0, Color(1, 1, 1, 0.45))


## 오른쪽 세로 막대: 아래 = 출발선, 위 = 결승선. 점 = 각 참가자 (나는 크게, 탈락은 회색)
func _draw_progress(scr: Vector2) -> void:
    var x := scr.x - 46.0
    var top := 150.0
    var bottom := scr.y - (230.0 if _touch else 150.0)
    if bottom - top < 120.0:
        return
    var frame := StyleBoxFlat.new()
    frame.bg_color = Color(UI.CREAM, 0.85)
    frame.border_color = UI.INK
    frame.set_border_width_all(3)
    frame.set_corner_radius_all(12)
    draw_style_box(frame, Rect2(Vector2(x - 12, top - 14), Vector2(24, bottom - top + 28)))
    draw_line(Vector2(x - 10, top), Vector2(x + 10, top), UI.RED, 4.0)
    var font := get_theme_default_font()
    draw_string(font, Vector2(x - 40, top - 22), "결승", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, UI.INK)
    var me: Fighter = game.human
    for f: Fighter in game.fighters:
        if f == me:
            continue
        _dot(f, x, top, bottom, 6.0)
    if me:
        _dot(me, x, top, bottom, 10.0)


func _dot(f: Fighter, x: float, top: float, bottom: float, r: float) -> void:
    var p: float = game.progress(f)
    var y := lerpf(bottom, top, p)
    var col: Color = f.body_color
    if f.dead:
        col = Color(0.55, 0.55, 0.6, 0.8)
    elif game.is_finished(f):
        col = UI.YELLOW
    draw_circle(Vector2(x, y), r + 2.0, UI.INK)
    draw_circle(Vector2(x, y), r, col)


# ---- 소리: 카운트다운·통과·끝
var _last_c := ""
var _last_s := -1
var _last_result := ""


func _play_sounds(center: String, human: Fighter) -> void:
    if center != _last_c and game.state == PartyGame.State.COUNTDOWN and center.is_valid_int():
        Sfx.play("count_tick")
    if game.human_result != _last_result and human and game.is_finished(human):
        Sfx.play("count_go")
    if game.state != _last_s and game.state == PartyGame.State.ENDED:
        if human and game.is_finished(human) and int(game.finished[human.slot][0]) == 1:
            Sfx.play("win")
        else:
            Sfx.play("whistle")
    _last_c = center
    _last_s = game.state
    _last_result = game.human_result
