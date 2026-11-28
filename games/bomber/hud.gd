extends "res://games/rock_dodge/hud.gd"
## 연쇄폭탄마 화면
##   위: 남은 시간·생존 / 가운데: 카운트다운·결과 / 아래: 내 폭탄·불꽃·신발 개수, 유령이면 던지기 안내
##   오른쪽 위 메뉴·결과 버튼은 돌피하기 화면 것을 그대로 씀. 탈락해도 관전 대신 유령으로 계속 참여

var _stats: Label
var _ghost: Label


func _ready() -> void:
    _touch = Fighter.touch_device()
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _help = _make_label(16)
    if _touch:
        _help.text = "왼쪽 스틱 이동 · 오른쪽 드래그 시점 · 던지기 버튼 탭 = 발밑에 놓기, 누르다 떼기 = 던지기 · 점프 버튼"
    else:
        _help.text = "WASD 이동 · 마우스 시점 · 휠 확대/축소 · 좌클릭/E 탭 = 발밑에 놓기, 누르다 떼기 = 멀리 던지기 · Space 점프%s" \
                % ("" if game.is_online_match() else " · R 재시작")
    _help.position = Vector2(16, 10)
    _build_menu_bar()
    _build_result_box()
    _build_spectate_bar()
    _top = _make_label(24, true)
    _top.add_theme_constant_override("outline_size", 0)
    _top.add_theme_color_override("font_color", UI.CREAM)
    _top.add_theme_stylebox_override("normal", UI.box(UI.INK, 22, 20, UI.INK, 0, 4))
    _center = _make_label(96, true)
    _center.add_theme_constant_override("outline_size", 16)
    _sub = _make_label(22, true)
    _status_label = _make_label(20, true)
    _stats = _make_label(26, true)
    _stats.add_theme_constant_override("outline_size", 0)
    _stats.add_theme_color_override("font_color", UI.CREAM)
    _stats.add_theme_stylebox_override("normal", UI.box(UI.INK, 18, 12, UI.INK, 0, 4))
    _ghost = _make_label(22, true)
    for i in 5:
        var l := _make_label(18)
        l.position = Vector2(16, 44 + i * 26)
        _feed_labels.append(l)


func _spectate_candidates() -> Array[Fighter]:
    return []


func _process(delta: float) -> void:
    if game == null:
        return
    _tick_leave(delta)
    if _bar:
        _bar.position = Vector2(_screen().x - _bar.size.x - 14.0, 12.0)
    _update_result_box()
    var scr := _screen()
    var left: float = maxf(game.TIME_LIMIT - game.elapsed, 0.0) if game.state == PartyGame.State.PLAYING else game.TIME_LIMIT
    var alive: int = game.alive_fighters().size()
    _top.text = "⏱ %d:%02d     생존 %d / %d" % [int(ceil(left)) / 60, int(ceil(left)) % 60, alive, game.fighters.size()]
    if int(game.teams) >= 2:
        var parts := PackedStringArray()
        for t in int(game.teams):
            var n := 0
            for f: Fighter in game.fighters:
                if f.team == t and not f.dead:
                    n += 1
            parts.append("%s %d" % [Teams.SHORT[t], n])
        _top.text += "     " + " · ".join(parts)
    var ser: Dictionary = game.series()
    if int(ser.get("total", 1)) > 1:
        _top.text = "라운드 %d/%d     " % [int(ser.round), int(ser.total)] + _top.text
    _place_centered(_top, 14 + 24)

    var human: Fighter = game.human
    var center := ""
    var sub := ""
    var center_col := UI.YELLOW
    match game.state:
        PartyGame.State.COUNTDOWN:
            center = str(int(ceil(game.countdown_time - game.state_time)))
            sub = "폭탄을 던져 블록을 부수고 상대를 맞혀요! 불길에 맞거나 용암에 떨어지면 탈락"
            if game.is_client() and game.play_start_t < 0.0:
                center = "…"
                sub = "다른 플레이어를 기다리는 중"
        PartyGame.State.PLAYING:
            if game.state_time < 1.0:
                center = "시작!"
            if human and human.dead:
                sub = game.human_result
        PartyGame.State.ENDED:
            center = game.winner_text
            sub = game.human_result if human and human.dead else ""
    _center.text = center
    _center.add_theme_color_override("font_color", center_col)
    _sub.text = sub
    _play_sounds(center, human)
    _place_centered(_center, scr.y * 0.22)
    _place_centered(_sub, scr.y * 0.22 + 118)

    # 내 능력치 / 유령 안내
    var bottom := scr.y - (250.0 if _touch else 70.0)
    if human and not human.dead and game.state != PartyGame.State.ENDED:
        var s := human.slot
        _stats.text = "💣 폭탄 %d   🔥 불꽃 %d   ⚡ 속도 %d" % [game.stat(s, 0), game.stat(s, 1), game.stat(s, 2)]
        _stats.visible = true
        _place_centered(_stats, bottom)
    else:
        _stats.visible = false
    if human and human.dead and game.ghosts.has(human.slot) and game.state == PartyGame.State.PLAYING:
        var cd: float = game.ghost_cooldown_left(human.slot)
        var key := "던지기 버튼" if _touch else "좌클릭/E"
        _ghost.text = "👻 유령: 이동으로 테두리를 돌고 %s로 폭탄 던지기 — %s" % [key, ("%.1f초 뒤 다시 던질 수 있어요" % cd) if cd > 0.0 else "지금 던질 수 있어요!"]
        _ghost.add_theme_color_override("font_color", UI.CREAM if cd > 0.0 else UI.YELLOW)
        _ghost.visible = true
        _place_centered(_ghost, bottom)
    else:
        _ghost.visible = false

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
    if game == null or game.board == null or game.state == PartyGame.State.COUNTDOWN:
        return
    _draw_minimap()


## 오른쪽 아래 작은 지도: 기둥·상자·폭탄·사람 (카메라를 가까이 당겨도 전체 상황이 보이게)
func _draw_minimap() -> void:
    var b = game.board
    var cell := 7.0
    var size := Vector2(b.w, b.h) * cell
    var scr := _screen()
    var origin := Vector2(scr.x - size.x - 18.0, scr.y - size.y - (250.0 if _touch else 18.0))
    if origin.y < 160.0:
        return
    draw_rect(Rect2(origin - Vector2(4, 4), size + Vector2(8, 8)), Color(UI.INK, 0.8))
    for y in b.h:
        for x in b.w:
            var c0 := Vector2i(x, y)
            var hh: int = b.height(c0)
            var col := Color(0.42, 0.44, 0.52)
            if hh == 0:
                col = Color(1.0, 0.36, 0.08)
            elif hh > 0:
                col = Color(0.45, 0.3, 0.2).lerp(Color(0.92, 0.8, 0.52), float(hh) / 5.0)
            draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell - 1, cell - 1)), col)
    var now: float = game.net_now()
    for fl in game.flames:
        if now < float(fl.t1):
            for i in fl.cells:
                var c: Vector2i = b.cell(int(i))
                draw_rect(Rect2(origin + Vector2(c) * cell, Vector2(cell - 1, cell - 1)), Color(1.0, 0.92, 0.25))
    for id in game.bombs:
        var c: Vector2i = b.cell(int(game.bombs[id].cell))
        draw_circle(origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell, cell * 0.4, Color(0.1, 0.1, 0.12))
    for f: Fighter in game.fighters:
        if f.dead:
            continue
        var p: Vector3 = f.global_position
        var m := origin + Vector2((p.x - b.x0) / b.TILE, (p.z - b.z0) / b.TILE) * cell
        var r := 4.5 if f == game.human else 3.0
        draw_circle(m, r + 1.5, UI.INK)
        draw_circle(m, r, f.body_color)


# ---- 소리: 카운트다운·끝
var _last_c := ""
var _last_s := -1


func _play_sounds(center: String, human: Fighter) -> void:
    if center != _last_c and game.state == PartyGame.State.COUNTDOWN and center.is_valid_int():
        Sfx.play("count_tick")
    if center == "시작!" and _last_c != center:
        Sfx.play("count_go")
    if game.state != _last_s and game.state == PartyGame.State.ENDED:
        if human and not human.dead:
            Sfx.play("win")
        else:
            Sfx.play("whistle")
    _last_c = center
    _last_s = game.state
