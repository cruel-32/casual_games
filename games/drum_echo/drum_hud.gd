extends Control
## 뒷북의 달인 화면: 위 = 지금 상황(공격·따라 치기) · 박자 점 · 점수, 아래 = 노트 길 + 북 버튼 두 개

const UI := preload("res://scripts/ui/ui_kit.gd")
const Chart := preload("res://games/drum_echo/chart.gd")
const Teams := preload("res://scripts/core/teams.gd")
const SeriesPanel := preload("res://scripts/ui/series_panel.gd")

const LOOK_AHEAD := 2.2             ## 노트 길에 보이는 앞쪽 시간(초)
const LOOK_BACK := 0.6
const DrumGame := preload("res://games/drum_echo/drum_game.gd")
const DON := DrumGame.DON_COLOR
const KA := DrumGame.KA_COLOR
const FEVER := DrumGame.FEVER_COLOR

var game

var _banner: Label
var _sub: Label
var _judge: Label
var _score_box: VBoxContainer
var _buttons: Array[Button] = []
var _leave_btn: Button
var _leave_armed := 0.0
var _result: PanelContainer
var _result_list: VBoxContainer
var _result_title: Label
var _score_key := ""


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _banner = _label(32, true)
    _sub = _label(17)
    _judge = _label(46, true)
    _score_box = UI.vbox(4)
    _score_box.position = Vector2(18, 16)
    add_child(_score_box)
    _build_menu_bar()
    _build_drum_buttons()
    _build_results()


func _label(size: int, display: bool = false) -> Label:
    var l := Label.new()
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", UI.CREAM)
    l.add_theme_color_override("font_outline_color", UI.INK)
    l.add_theme_constant_override("outline_size", 10 if display else 7)
    if display:
        l.add_theme_font_override("font", UI.DISPLAY_FONT)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(l)
    return l


func _screen() -> Vector2:
    return get_viewport_rect().size


# ---------------------------------------------------------------- 버튼
func _build_menu_bar() -> void:
    var bar := UI.hbox(8)
    bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
    bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    add_child(bar)
    bar.add_child(UI.sound_button())
    if not game.is_online_match():
        var again := UI.pill_button("다시 하기", UI.YELLOW, UI.INK)
        again.pressed.connect(func(): game.restart_offline())
        again.focus_mode = Control.FOCUS_NONE
        bar.add_child(again)
    _leave_btn = UI.pill_button("나가기", UI.RED)
    _leave_btn.pressed.connect(_on_leave)
    _leave_btn.focus_mode = Control.FOCUS_NONE
    bar.add_child(_leave_btn)


func _on_leave() -> void:
    var risky: bool = game.is_online_match() and game.state != PartyGame.State.ENDED
    if risky and _leave_armed <= 0.0:
        _leave_armed = 3.0
        _leave_btn.text = "정말 나가기? (기권)"
        return
    game.leave_to_menu()


## 화면 아래 양쪽 큰 북 버튼 (터치·마우스). 키보드: Space = 둥, Enter = 딱
func _build_drum_buttons() -> void:
    for lane in 2:
        var b := Button.new()
        b.text = ("둥\n[Space]" if lane == 0 else "딱\n[Enter]") if not PartyGame.TOUCH_SCRIPT.should_enable() else ("둥" if lane == 0 else "딱")
        b.focus_mode = Control.FOCUS_NONE
        b.add_theme_font_size_override("font_size", 30)
        var col := DON if lane == 0 else KA
        for st in ["normal", "hover", "pressed", "focus"]:
            var sb := UI.box(col.lightened(0.15) if st == "pressed" else col, 80, 10, UI.INK, 5, 6 if st != "pressed" else 2)
            b.add_theme_stylebox_override(st, sb)
        b.add_theme_color_override("font_color", Color.WHITE)
        b.add_theme_color_override("font_pressed_color", Color.WHITE)
        b.add_theme_color_override("font_hover_color", Color.WHITE)
        b.button_down.connect(func(): game.press(lane))
        b.button_up.connect(func(): game.release(lane))     # 피버: 누르고 있다가 뗌
        add_child(b)
        _buttons.append(b)


func _build_results() -> void:
    if game.is_online_match():
        var panel := SeriesPanel.new()
        panel.game = game
        add_child(panel)
        return
    _result = PanelContainer.new()
    _result.add_theme_stylebox_override("panel", UI.box(UI.CREAM, 22, 22, UI.INK, 4, 8))
    _result.visible = false
    add_child(_result)
    var v := UI.vbox(10)
    _result.add_child(v)
    _result_title = UI.heading("", 32)
    _result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(_result_title)
    _result_list = UI.vbox(6)
    v.add_child(_result_list)
    var row := UI.hbox(12)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    var again := UI.cta_button("다시 하기")
    again.pressed.connect(func(): game.restart_offline())
    row.add_child(again)
    var out := UI.secondary_button("메인으로")
    out.pressed.connect(func(): game.leave_to_menu())
    row.add_child(out)


# ---------------------------------------------------------------- 매 프레임
func _process(delta: float) -> void:
    if _leave_armed > 0.0:
        _leave_armed -= delta
        if _leave_armed <= 0.0:
            _leave_btn.text = "나가기"
    var sc := _screen()
    var t: float = game.heard_time()
    _update_banner(t)
    # 안내 글은 트랙 바로 위 (시선이 한곳에 모이게)
    var hr := _highway_rect()
    _place(_banner, hr.position.y - 50.0)
    _place(_sub, hr.position.y - 16.0)
    # 판정 문구 (노트 길 위, 0.6초 동안)
    var age: float = Time.get_ticks_msec() / 1000.0 - game.last_judge_time
    _judge.visible = age < 0.6 and game.last_judge != ""
    if _judge.visible:
        _judge.text = Chart.JUDGE_NAMES.get(game.last_judge, game.last_judge)
        _judge.add_theme_color_override("font_color", game._judge_color(game.last_judge))
        _judge.scale = Vector2.ONE * (1.0 + maxf(0.15 - age, 0.0) * 2.0)
        _judge.pivot_offset = _judge.size * 0.5
        var r := _highway_rect()
        _judge.size = _judge.get_minimum_size()
        _judge.position = Vector2(r.position.x + r.size.x * 0.12 + 40, r.get_center().y - _judge.size.y * 0.5)
    # 북 버튼: 노트 길 양옆
    var bs := clampf(sc.y * 0.2, 110.0, 170.0)
    for lane in 2:
        var b := _buttons[lane]
        b.size = Vector2(bs, bs)
        b.position = Vector2(24.0 if lane == 0 else sc.x - bs - 24.0, sc.y - bs - 22.0)
        b.visible = game.state != PartyGame.State.ENDED
    _update_scores()
    _update_results()
    queue_redraw()


func _place(l: Label, y: float) -> void:
    l.size = l.get_minimum_size()
    l.position = Vector2((_screen().x - l.size.x) * 0.5, y - l.size.y * 0.5)


func _team_name_of(team: int) -> String:
    return Teams.team_name(team) if team >= 0 else "진행자"


func _update_banner(t: float) -> void:
    if game.state == PartyGame.State.ENDED:
        _banner.text = game.winner_text
        _sub.text = ""
        return
    if game.t0 < 0.0:
        _banner.text = "곧 시작해요!"
        _sub.text = "모두 준비되면 반주가 나와요"
        return
    if t < 0.0:
        _banner.text = str(ceili(-t))
        _sub.text = ("Space = 둥,  Enter = 딱" if not PartyGame.TOUCH_SCRIPT.should_enable() else "왼쪽 버튼 = 둥,  오른쪽 버튼 = 딱") + "  ·  피버 = 누르고 있다가 떼기"
        return
    var ph: Array = game.phase_at(t)
    var kind: String = ph[1]
    match kind:
        "ready_attack":
            _banner.add_theme_color_override("font_color", UI.CREAM)
            _banner.text = "진행자가 선창해요"
            _sub.text = "잘 듣고 다 같이 똑같이 따라 쳐요"
        "attack":
            _banner.add_theme_color_override("font_color", UI.CREAM)
            _banner.text = "잘 들어요!"
            _sub.text = "진행자가 치는 리듬 — 곧 똑같이 따라 쳐요"
        "ready_response":
            _banner.add_theme_color_override("font_color", UI.YELLOW)
            _banner.text = "따라 칠 준비!"
            _sub.text = "같은 타이밍, 같은 북으로 · 피버는 끝 박자에 떼요"
        "response":
            _banner.add_theme_color_override("font_color", UI.YELLOW)
            _banner.text = "다 같이 따라 쳐요!"
            _sub.text = "같은 타이밍, 같은 북으로 · 피버는 끝 박자에 떼요"
        _:
            _banner.add_theme_color_override("font_color", UI.CREAM)
            _banner.text = "마무리!" if int(ph[2]) >= game.turns.size() else "반주를 들으며 준비해요"
            _sub.text = ""


func _update_scores() -> void:
    var rows := []
    if game.teams >= 2:
        var totals := {}
        for f in game.fighters:
            totals[f.team] = int(totals.get(f.team, 0)) + int(game.scores.get(f.slot, 0))
        for tm in range(game.teams):
            rows.append([Teams.team_name(tm), int(totals.get(tm, 0)), Teams.color(tm), game.my_slot >= 0 and game.fighters[game.my_slot].team == tm])
    else:
        var order: Array = game.fighters.duplicate()
        order.sort_custom(func(a, b): return int(game.scores.get(a.slot, 0)) > int(game.scores.get(b.slot, 0)))
        for f in order.slice(0, 5):
            rows.append([f.display_name, int(game.scores.get(f.slot, 0)), f.body_color, f.slot == game.my_slot])
    if game.my_slot >= 0:
        rows.append(["내 점수", int(game.scores.get(game.my_slot, 0)), UI.YELLOW, true])
    var key := str(rows)
    if key == _score_key:
        return
    _score_key = key
    for c in _score_box.get_children():
        c.queue_free()
    for r in rows:
        var h := UI.hbox(8)
        var dot := ColorRect.new()
        dot.color = r[2]
        dot.custom_minimum_size = Vector2(14, 14)
        dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        h.add_child(dot)
        var l := UI.label("%s  %d" % [r[0], r[1]], 20 if r[3] else 17, UI.CREAM)
        l.add_theme_color_override("font_outline_color", UI.INK)
        l.add_theme_constant_override("outline_size", 6)
        h.add_child(l)
        _score_box.add_child(h)


func _update_results() -> void:
    if _result == null:
        return
    var ended: bool = game.state == PartyGame.State.ENDED and not game.final_rank.is_empty()
    _result.visible = ended
    if not ended:
        return
    if _result_list.get_child_count() == 0:
        _result_title.text = game.winner_text
        for r in game.final_rank:
            var l := UI.label("%d위  %s  —  %d점" % [int(r.rank), String(r.name), int(r.score)], 22, UI.INK)
            _result_list.add_child(l)
    _result.size = _result.get_minimum_size()
    _result.position = (_screen() - _result.size) * 0.5


# ---------------------------------------------------------------- 노트 길
func _highway_rect() -> Rect2:
    var sc := _screen()
    var bs := clampf(sc.y * 0.2, 110.0, 170.0)
    var w := sc.x - (bs + 48.0) * 2.0
    var h := clampf(sc.y * 0.16, 92.0, 124.0)
    return Rect2(Vector2((sc.x - w) * 0.5, sc.y - h - 26.0), Vector2(w, h))


## 트랙 하나 (내가 칠 것):
##   진행자 선창: 소리가 난 노트가 판정선에서 테두리 원으로 생겨 왼쪽으로 흘러가고, 그와 동시에 내가 따라 칠 노트(꽉 찬 원)가 오른쪽에서 들어와 다가온다
##   따라 치기 구간만 밝게, 그 앞뒤는 어둡게
func track_mode(t: float) -> Array:
    var ph: Array = game.phase_at(t)
    var i := int(ph[0])
    if i < 0:
        return ["idle", -1]
    var kind: String = ph[1]
    return ["listen" if kind == "ready_attack" or kind == "attack" else "respond", i]


func _hit_x(r: Rect2) -> float:
    return r.position.x + r.size.x * 0.12


func _lane_ys(r: Rect2) -> Array:
    return [r.position.y + r.size.y * 0.3, r.position.y + r.size.y * 0.72]


func _draw() -> void:
    if game.state == PartyGame.State.ENDED or game.t0 < 0.0:
        return
    # 판정과 같은 시계(귀에 들리는 반주 시각)로 그린다 — 화면과 판정이 어긋나지 않게
    var t: float = game.heard_time()
    var r := _highway_rect()
    var mode_i := track_mode(t)
    var mode: String = mode_i[0]
    var i: int = mode_i[1]
    var font := get_theme_default_font()
    var bg := Color(0.1, 0.12, 0.2, 0.85) if mode != "respond" else Color(0.3, 0.25, 0.06, 0.9)
    draw_style_box(UI.box(bg, 16, 0, UI.INK, 4, 0), r)
    var lane_y := _lane_ys(r)
    var hit_x := _hit_x(r)
    var px := (r.size.x * 0.86) / LOOK_AHEAD
    for lane in 2:
        draw_circle(Vector2(hit_x, lane_y[lane]), 22, Color(1, 1, 1, 0.16))
        draw_arc(Vector2(hit_x, lane_y[lane]), 22, 0, TAU, 32, Color(1, 1, 1, 0.85), 3.0)
    draw_string(font, Vector2(r.position.x + 10, lane_y[0] + 7), "둥", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DON.lightened(0.3))
    draw_string(font, Vector2(r.position.x + 10, lane_y[1] + 7), "딱", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, KA.lightened(0.3))
    if i < 0:
        return
    var tr: Dictionary = game.turns[i]
    # 따라 치기 구간만 밝게
    var r0 := float(tr.response_t)
    var r1 := r0 + int(tr.bars) * Chart.BAR
    var xs := clampf(hit_x + (r0 - t) * px, r.position.x + 4, r.end.x - 4)
    var xe := clampf(hit_x + (r1 - t) * px, r.position.x + 4, r.end.x - 4)
    if xs > r.position.x + 4:
        draw_rect(Rect2(Vector2(r.position.x + 4, r.position.y + 4), Vector2(xs - r.position.x - 4, r.size.y - 8)), Color(0, 0, 0, 0.35))
    if xe < r.end.x - 4:
        draw_rect(Rect2(Vector2(xe, r.position.y + 4), Vector2(r.end.x - 4 - xe, r.size.y - 8)), Color(0, 0, 0, 0.35))
    if xe - xs > 1.0:
        draw_rect(Rect2(Vector2(xs, r.position.y + 4), Vector2(xe - xs, r.size.y - 8)), Color(1, 0.9, 0.4, 0.1))
    # 박 선 (따라 치기 구간 안, 시작·끝 굵게)
    var first := int(floor((t - LOOK_BACK - r0) / Chart.BEAT))
    for k in range(first, first + int((LOOK_AHEAD + LOOK_BACK) / Chart.BEAT) + 2):
        var bt := r0 + k * Chart.BEAT
        if bt < r0 - 0.01 or bt > r1 + 0.01:
            continue
        var x := hit_x + (bt - t) * px
        if x < r.position.x or x > r.end.x:
            continue
        var edge := k == 0 or absf(bt - r1) < 0.01
        draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.end.y - 4), Color(1, 1, 1, 0.6 if edge else 0.15), 3.0 if edge else 1.5)
    var notes: Array = game.view_notes.get(i, [])
    var taken: Dictionary = game.view_taken.get(i, {})
    for n_i in notes.size():
        var n: Array = notes[n_i]
        var lane := int(n[1])
        var col := DON if lane == 0 else KA
        var rad := 17.0 if lane == 0 else 13.0
        var y: float = lane_y[lane]
        var ta := Chart.note_time(tr, n, false)
        if ta > t:
            continue                        # 아직 진행자가 안 친 노트는 안 보임
        # 진행자 선창 (들은 리듬): 테두리 원, 판정선에서 생겨 왼쪽으로
        var xa := hit_x + (ta - t) * px
        if xa > r.position.x and xa < r.end.x:
            var pop := clampf((t - ta) / 0.12, 0.0, 1.0)
            if Chart.is_fever(n):
                _capsule(xa, hit_x + (minf(Chart.note_end_time(tr, n, false), t) - t) * px, y, rad * 0.8, r, Color(col, 0.0), Color(FEVER, 0.6), 2.0)
            draw_arc(Vector2(xa, y), rad * (1.5 - 0.5 * pop), 0, TAU, 24, Color(col, 0.8), 3.0)
        # 내가 따라 칠 노트: 꽉 찬 원, 오른쪽에서 다가옴
        var tb := Chart.note_time(tr, n, true)
        var xb := hit_x + (tb - t) * px
        var c := col
        if Chart.is_fever(n):
            var tbe := Chart.note_end_time(tr, n, true)
            if taken.has(-(n_i + 1)) or tbe < t - Chart.BAD:
                continue
            var holding := false
            for lk in game.view_hold:
                if int(game.view_hold[lk][0]) == i and int(game.view_hold[lk][1]) == n_i:
                    holding = true
            if taken.has(n_i) and not holding:
                c = Color(0.5, 0.5, 0.55, 0.6)
            _capsule(hit_x if holding else xb, hit_x + (tbe - t) * px, y, rad, r, Color(c, 0.55), Color(FEVER, 0.95), 3.0)
            var xe2 := hit_x + (tbe - t) * px
            if xe2 > r.position.x and xe2 < r.end.x:
                draw_circle(Vector2(xe2, y), rad * 0.7, Color(FEVER, 0.9))
        if taken.has(n_i) or xb < r.position.x or xb > r.end.x:
            continue
        if tb < t - Chart.BAD:
            c = Color(0.5, 0.5, 0.55, 0.6)      # 놓침
        draw_circle(Vector2(xb, y), rad, c)
        draw_arc(Vector2(xb, y), rad, 0, TAU, 24, Color(FEVER, 0.95) if Chart.is_fever(n) else Color(1, 1, 1, 0.9), 2.5)


## 피버 막대 (x0 → x1, 노트 길 안으로 잘라서)
func _capsule(x0: float, x1: float, y: float, rad: float, r: Rect2, fill: Color, line: Color, w: float) -> void:
    var a := clampf(minf(x0, x1), r.position.x + 4, r.end.x - 4)
    var b := clampf(maxf(x0, x1), r.position.x + 4, r.end.x - 4)
    if b - a < 1.0:
        return
    var h := rad * 0.8
    var rect := Rect2(Vector2(a, y - h), Vector2(b - a, h * 2.0))
    if fill.a > 0.0:
        draw_rect(rect, fill)
    draw_line(Vector2(a, y - h), Vector2(b, y - h), line, w)
    draw_line(Vector2(a, y + h), Vector2(b, y + h), line, w)


# ---------------------------------------------------------------- 남은 개수(칩)
