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
var _sync_label: Label
var _spec: Label                    ## 마디 수·노트 수 (쉼·공격 동안 크게)
var _spec_box: PanelContainer


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _banner = _label(40, true)
    _sub = _label(20)
    _judge = _label(46, true)
    _spec_box = PanelContainer.new()
    _spec_box.add_theme_stylebox_override("panel", UI.box(Color(0.11, 0.16, 0.27, 0.88), 16, 10, UI.YELLOW, 4, 0))
    _spec_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_spec_box)
    _spec = _label(26, true)
    remove_child(_spec)
    _spec_box.add_child(_spec)
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
    # 박자 보정: 소리가 늦게 들리는 기기(블루투스 이어폰 등)에서 판정을 맞춤
    var sync := UI.hbox(2)
    var minus := UI.pill_button("−", UI.CREAM, UI.INK)
    minus.focus_mode = Control.FOCUS_NONE
    minus.tooltip_text = "판정이 늦다고(내가 일찍 친다고) 나오면 줄여요"
    minus.pressed.connect(func(): game.change_sync(-10))
    sync.add_child(minus)
    _sync_label = UI.label("", 15, UI.CREAM)
    _sync_label.add_theme_color_override("font_outline_color", UI.INK)
    _sync_label.add_theme_constant_override("outline_size", 6)
    _sync_label.custom_minimum_size.x = 96
    _sync_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _sync_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _sync_label.size_flags_vertical = Control.SIZE_FILL
    sync.add_child(_sync_label)
    var plus := UI.pill_button("+", UI.CREAM, UI.INK)
    plus.focus_mode = Control.FOCUS_NONE
    plus.tooltip_text = "판정이 이르다고(내가 늦게 친다고) 나오면 늘려요"
    plus.pressed.connect(func(): game.change_sync(10))
    sync.add_child(plus)
    bar.add_child(sync)
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
    _sync_label.text = "박자 보정 %+dms" % game.sync_offset_ms
    _update_banner(t)
    _place(_banner, 70.0)
    _place(_sub, 122.0)
    _spec_box.size = _spec_box.get_minimum_size()
    _spec_box.position = Vector2((sc.x - _spec_box.size.x) * 0.5, 146.0)
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
        _judge.position = Vector2(r.position.x + r.size.x * 0.12 - _judge.size.x * 0.5 + 40, r.position.y - _judge.size.y - 6)
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
    _spec_box.visible = false
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
    var i := int(ph[0])
    var me: int = game.my_slot
    var kind: String = ph[1]
    if kind == "ready_attack" or kind == "attack":
        var who := int(game.view_attacker.get(i, -2))
        var team := int(game.turns[i].attack_team)
        var bars := int(game.turns[i].bars)
        _banner.add_theme_color_override("font_color", Teams.color(team).lightened(0.35) if team >= 0 else UI.CREAM)
        var spec: Dictionary = game.view_spec.get(i, {})
        if not spec.is_empty():
            _spec_box.visible = true
            if who == me and me >= 0 and kind == "attack":
                _spec.text = _progress_text(spec, game.view_notes.get(i, []))
            else:
                _spec.text = "%d마디 · %s" % [bars, Chart.spec_text(spec)]
        if kind == "ready_attack":
            if who == me and me >= 0:
                _banner.text = "준비! 내가 공격해요"
                _sub.text = "정해진 개수만큼만 — 많거나 적으면 감점"
            else:
                _banner.text = "준비! %s 공격" % _team_name_of(team)
                _sub.text = ("%s 님이 칠 리듬을 잘 들어요" % game.fighters[who].display_name) if who >= 0 else "진행자가 칠 리듬을 잘 들어요"
                if me >= 0 and not game.is_responder(me, i) and who >= 0:
                    _sub.text = "우리 팀 차례 — %s 님 화이팅!" % game.fighters[who].display_name
        elif who == me and me >= 0:
            _banner.text = "내가 공격! 북을 쳐요"
            _sub.text = "반 박(8분음표) 칸에 맞춰져요 · 피버는 누르고 있다가 박자에 떼요"
        elif team < 0:
            _banner.text = "진행자 공격!"
            _sub.text = "진행자가 치는 리듬을 잘 듣고, 똑같이"
        else:
            _banner.text = "%s 공격" % _team_name_of(team)
            _sub.text = ("%s 님이 치는 리듬을 잘 들어요" % game.fighters[who].display_name) if who >= 0 else ""
            if me >= 0 and not game.is_responder(me, i):
                _sub.text = "우리 팀 차례 — %s 님 화이팅!" % (game.fighters[who].display_name if who >= 0 else "")
    elif kind == "ready_response" or kind == "response":
        _banner.add_theme_color_override("font_color", UI.YELLOW)
        var mine: bool = me >= 0 and game.is_responder(me, i)
        if kind == "ready_response":
            _banner.text = "따라 칠 준비!" if mine else "상대가 따라 칠 차례"
        else:
            _banner.text = "따라 쳐요!" if mine else "상대가 따라 치는 중"
        _sub.text = "같은 타이밍, 같은 북으로 · 피버는 끝 박자에 떼요" if mine else ""
        # 사람 공격의 개수 결과
        if game.view_cnt.has(i):
            var c: Array = game.view_cnt[i]
            _spec_box.visible = true
            var who := int(game.view_attacker.get(i, -1))
            var name: String = "내" if who == me else (game.fighters[who].display_name + " 님" if who >= 0 else "")
            _spec.text = ("%s 공격 개수 정확!" % name) if int(c[1]) == 0 else ("%s 공격 개수 틀림 −%d · 컴퓨터가 개수를 맞췄어요" % [name, int(c[1])])
    else:
        _banner.add_theme_color_override("font_color", UI.CREAM)
        var nx := int(ph[2])
        if nx < game.turns.size():
            var who := int(game.view_attacker.get(nx, -2))
            _banner.text = "다음은 내가 공격!" if who == me and me >= 0 else "준비…"
            _sub.text = "%s 공격 · %d마디" % [_team_name_of(int(game.turns[nx].attack_team)), int(game.turns[nx].bars)]
        else:
            _banner.text = "마무리!"
            _sub.text = ""


## 공격자용: 정해진 개수 대비 지금까지 만든 개수 (예: 정박 2/3 · 엇박 1/1 · 피버 0/1)
func _progress_text(spec: Dictionary, notes: Array) -> String:
    var c := Chart.count_of(notes)
    var parts := []
    for k: String in ["on", "off", "fever"]:
        var need := int(spec.get(k, 0))
        if need == 0 and int(c[k]) == 0:
            continue
        var nm: String = {"on": "정박", "off": "엇박", "fever": "피버"}[k]
        var mark := " 완료" if int(c[k]) == need else (" 넘침!" if int(c[k]) > need else "")
        parts.append("%s %d/%d%s" % [nm, int(c[k]), need, mark])
    return " · ".join(parts)


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
    var h := clampf(sc.y * 0.2, 110.0, 150.0)
    return Rect2(Vector2((sc.x - w) * 0.5, sc.y - h - 26.0), Vector2(w, h))


func _draw() -> void:
    if game.state == PartyGame.State.ENDED or game.t0 < 0.0:
        _draw_beat_dots(-1.0)
        return
    # 판정과 같은 시계(귀에 들리는 반주 시각)로 그린다 — 화면과 판정이 어긋나지 않게
    var t: float = game.heard_time()
    _draw_beat_dots(t)
    var r := _highway_rect()
    draw_style_box(UI.box(Color(0.11, 0.16, 0.27, 0.82), 18, 0, UI.INK, 4, 0), r)
    var hit_x := r.position.x + r.size.x * 0.12
    var px := (r.size.x * 0.86) / LOOK_AHEAD
    var lane_y := [r.position.y + r.size.y * 0.32, r.position.y + r.size.y * 0.72]
    var me: int = game.my_slot

    # 구간 색: 내가 따라 칠 마디 = 노랑, 공격 마디 = 공격팀 색
    for i in game.turns.size():
        var tr: Dictionary = game.turns[i]
        for kind in 2:
            var b0 := float(tr.attack_t if kind == 0 else tr.response_t)
            var b1 := b0 + int(tr.bars) * Chart.BAR
            var x0 := clampf(hit_x + (b0 - t) * px, r.position.x, r.end.x)
            var x1 := clampf(hit_x + (b1 - t) * px, r.position.x, r.end.x)
            if x1 - x0 < 1.0:
                continue
            var col: Color
            if kind == 0:
                col = Teams.color(int(tr.attack_team)) if int(tr.attack_team) >= 0 else Color(0.7, 0.7, 0.75)
                col.a = 0.16
            else:
                col = Color(1.0, 0.85, 0.2, 0.22) if me >= 0 and game.is_responder(me, i) else Color(1, 1, 1, 0.05)
            draw_rect(Rect2(Vector2(x0, r.position.y + 4), Vector2(x1 - x0, r.size.y - 8)), col)

    # 박·마디 선 + 반 박(8분음표) 눈금: 칠 수 있는 자리는 이 선들뿐
    var first_half := int(floor((t - LOOK_BACK) / Chart.SLOT))
    for k in range(first_half, first_half + int((LOOK_AHEAD + LOOK_BACK) / Chart.SLOT) + 2):
        var bt := k * Chart.SLOT
        var x := hit_x + (bt - t) * px
        if x < r.position.x or x > r.end.x:
            continue
        if posmod(k, 2) == 1:
            # 반 박: 위·아래 짧은 눈금
            draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.position.y + 18), Color(1, 1, 1, 0.22), 1.5)
            draw_line(Vector2(x, r.end.y - 18), Vector2(x, r.end.y - 6), Color(1, 1, 1, 0.22), 1.5)
            continue
        var bar := posmod(k, 8) == 0
        draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.end.y - 6), Color(1, 1, 1, 0.35 if bar else 0.14), 3.0 if bar else 1.5)

    # 칠 자리 (판정선)
    for lane in 2:
        draw_circle(Vector2(hit_x, lane_y[lane]), 24, Color(1, 1, 1, 0.16))
        draw_arc(Vector2(hit_x, lane_y[lane]), 24, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0)
    var font := get_theme_default_font()
    draw_string(font, Vector2(r.position.x + 10, lane_y[0] + 7), "둥", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DON.lightened(0.3))
    draw_string(font, Vector2(r.position.x + 10, lane_y[1] + 7), "딱", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, KA.lightened(0.3))

    # 노트: 공격(들은 리듬) = 테두리만, 따라 칠 노트 = 꽉 찬 원, 피버 = 금색 테두리 긴 막대
    #   공격 노트는 실제로 들린 뒤에야 나타난다 (진행자·봇 리듬을 미리 알 수 없게) — 판정선에서 '퐁' 생겨 왼쪽으로 지나감
    #   따라 칠 노트는 컴퓨터가 개수를 맞춰 확정한 뒤에 나타난다 (그 전엔 들은 리듬 그대로 흐리게)
    for i in game.view_notes:
        var tr: Dictionary = game.turns[i]
        var notes: Array = game.view_notes[i]
        var taken: Dictionary = game.view_taken.get(i, {})
        var mine: bool = me >= 0 and game.is_responder(me, i)
        var final: bool = game.view_final.has(i)
        for n_i in notes.size():
            var n: Array = notes[n_i]
            var lane := int(n[1])
            var col := DON if lane == 0 else KA
            var rad := 17.0 if lane == 0 else 13.0
            var y: float = lane_y[lane]
            var fever := Chart.is_fever(n)
            # 공격 (들은 리듬)
            var ta := Chart.slot_time(tr, int(n[0]), false)
            if ta <= t:
                var xa := hit_x + (ta - t) * px
                var pop := clampf((t - ta) / 0.12, 0.0, 1.0)
                if fever:
                    var te := minf(Chart.slot_time(tr, int(n[2]), false), t)
                    _capsule(xa, hit_x + (te - t) * px, y, rad, r, Color(col, 0.0), Color(FEVER, 0.85), 3.0)
                if xa > r.position.x and xa < r.end.x:
                    draw_arc(Vector2(xa, y), rad * (1.5 - 0.5 * pop), 0, TAU, 24, Color(col, 0.75 + 0.25 * (1.0 - pop)), 3.0)
            elif not fever and not final:
                continue
            # 따라 칠 노트
            if ta > t and not final:
                continue
            var tb := Chart.slot_time(tr, int(n[0]), true)
            var xb := hit_x + (tb - t) * px
            var c := col if mine else Color(col, 0.35)
            if not final:
                c = Color(col, 0.3)
            if fever:
                var tbe := Chart.slot_time(tr, int(n[2]), true)
                var end_taken := taken.has(-(n_i + 1))
                if end_taken or tbe < t - Chart.BAD:
                    continue
                var holding := false
                for lk in game.view_hold:
                    if int(game.view_hold[lk][0]) == i and int(game.view_hold[lk][1]) == n_i:
                        holding = true
                var x0 := hit_x if holding else xb
                if taken.has(n_i) and not holding:
                    c = Color(0.5, 0.5, 0.55, 0.6)      # 누름은 맞혔는데 손을 뗌
                _capsule(x0, hit_x + (tbe - t) * px, y, rad, r, Color(c, c.a * 0.55), Color(FEVER, 0.95 if mine else 0.4), 3.0)
                if not taken.has(n_i) and xb > r.position.x and xb < r.end.x:
                    draw_circle(Vector2(xb, y), rad, c)
                    draw_arc(Vector2(xb, y), rad, 0, TAU, 24, Color(FEVER, 0.95 if mine else 0.4), 3.0)
                var xe := hit_x + (tbe - t) * px
                if xe > r.position.x and xe < r.end.x:
                    draw_circle(Vector2(xe, y), rad * 0.7, Color(FEVER, 0.9 if mine else 0.35))
                continue
            if xb < r.position.x or xb > r.end.x or taken.has(n_i):
                continue
            if mine and final and tb < t - Chart.BAD:
                c = Color(0.5, 0.5, 0.55, 0.6)      # 놓침
            draw_circle(Vector2(xb, y), rad, c)
            draw_arc(Vector2(xb, y), rad, 0, TAU, 24, Color(1, 1, 1, 0.9 if mine else 0.3), 2.5)
    # 내가 공격 중 누르고 있는 북: 피버 길이 미리 보기
    for lane in game._atk_hold:
        var h: Array = game._atk_hold[lane]
        if t - float(h[2]) >= Chart.FEVER_HOLD_MIN:
            var x0 := hit_x + (float(h[2]) - t) * px
            _capsule(x0, hit_x, lane_y[lane], 15.0, r, Color(FEVER, 0.25), Color(FEVER, 0.9), 3.0)
            var font2 := get_theme_default_font()
            draw_string(font2, Vector2(hit_x + 26, lane_y[lane] + 7), "FEVER!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FEVER)


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


## 배너 아래 박자 점 4개 (지금 박이 커짐)
func _draw_beat_dots(t: float) -> void:
    var sc := _screen()
    var beat := posmod(int(floor(t / Chart.BEAT)), 4) if t >= 0.0 else -1
    var frac := fposmod(t, Chart.BEAT) / Chart.BEAT if t >= 0.0 else 1.0
    for k in 4:
        var c := Vector2(sc.x * 0.5 + (k - 1.5) * 34.0, 214.0)
        var on := k == beat
        var rad := 9.0 + (6.0 * (1.0 - frac) if on else 0.0)
        draw_circle(c, rad, UI.YELLOW if on else Color(1, 1, 1, 0.35))
