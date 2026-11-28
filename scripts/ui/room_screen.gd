extends Control
const LoadingOverlay := preload("res://scripts/ui/loading_overlay.gd")
## 3단계: 대기룸 — 웹 페이지처럼: 왼쪽 = 위 막대(방 이름·상태·나가기) · 경기 설정 한 장 · 참가자 · 아래 레디/시작, 오른쪽 = 채팅만
##   경기 설정: [경기] R1 게임 ▼ · R2 게임 ▼ … [+ 라운드]  (라운드 수 = 칸 수)  /  [팀] 개인전·2팀… ▼ [인원] [봇 채우기]
##   참가자: 팀전 = 팀 색 열 (내 팀은 굵은 테두리·'내 팀'), 개인전 = 목록. 봇 자리도 사람처럼 (얼굴·이름·BOT)
##   사람에게 하는 일(팀 옮기기·방장 넘기기·강퇴·신고·차단)은 줄 오른쪽 '•••' 메뉴

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")
const Series := preload("res://scripts/core/series.gd")
const Teams := preload("res://scripts/core/teams.gd")
const CHAT_W := 300.0

var app: Node
var _title: Label
var _s_name: LineEdit
var _state_badge_holder: HBoxContainer
var _rounds_box: GridContainer        ## 경기: 라운드 1~5 칸 고정, 2열 × 3줄 (라운드별 게임)
var _mode_row: HBoxContainer          ## 참가자 제목 옆: 팀 수 · 최대 인원 · 봇 채우기
var _preview_img: Control             ## 고른 라운드 게임 썸네일
var _preview_name: Label
var _preview_desc: Label
var _focus_round := 0                 ## 지금 보고 있는 라운드 (썸네일·소개)
var _slots_label: Label
var _my_team_label: Label
var _slots: VBoxContainer
var _last_slots_key := ""
var _last_settings_key := ""
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _status: Label
var _ready_btn: Button
var _start_btn: Button
var _playing_overlay: Control
var _overlay_text: Label
var _last_members := -1
var _last_ready := false


func _ready() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_bottom", 22)
    add_child(margin)
    var root := UI.hbox(18)
    margin.add_child(root)

    # ---- 왼쪽
    var left := UI.vbox(10)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.add_child(left)

    # 위 막대: 방 이름 (방장은 바로 고침) · 상태 · 소리 · 나가기
    var top := UI.hbox(12)
    left.add_child(top)
    _title = UI.title("", 32)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _title.clip_text = true
    _title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(_title)
    _s_name = UI.line_edit("방 이름", "", Net.ROOM_NAME_MAX)
    _s_name.custom_minimum_size = Vector2(0, 42)
    _s_name.add_theme_font_size_override("font_size", 21)
    _s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _s_name.tooltip_text = "방 이름 (방장만 바꿀 수 있어요)"
    _s_name.text_submitted.connect(func(t): Net.update_settings({"name": t}))
    _s_name.focus_exited.connect(func(): Net.update_settings({"name": _s_name.text}))
    _s_name.visible = false
    top.add_child(_s_name)
    _state_badge_holder = UI.hbox(8)
    _state_badge_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(_state_badge_holder)
    var snd := UI.sound_button()
    snd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(snd)
    var leave := UI.pill_button("방 나가기")
    leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    leave.pressed.connect(func(): Net.leave_room())
    top.add_child(leave)

    # 경기 설정 한 장
    var setp := PanelContainer.new()
    var ssb := UI.box(Color(1, 0.99, 0.95), 16, 18, UI.INK, 3, 4)
    ssb.content_margin_top = 10
    ssb.content_margin_bottom = 10
    setp.add_theme_stylebox_override("panel", ssb)
    left.add_child(setp)
    # 왼쪽: 라운드 다섯 줄 (고정) / 오른쪽: 고른 라운드 게임 썸네일 + 소개
    var sh := UI.hbox(18)
    setp.add_child(sh)
    var lv2 := UI.vbox(4)
    lv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sh.add_child(lv2)
    var cap := UI.hbox(8)
    lv2.add_child(cap)
    cap.add_child(UI.heading("경기", 18))
    var pts := UI.label("라운드마다 1등 3점 · 2등 2점 · 3등 1점, 합계 1위가 우승", 12, UI.MUTED)
    pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    pts.clip_text = true
    pts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cap.add_child(pts)
    _rounds_box = GridContainer.new()
    _rounds_box.columns = 2
    _rounds_box.add_theme_constant_override("h_separation", 8)
    _rounds_box.add_theme_constant_override("v_separation", 5)
    _rounds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lv2.add_child(_rounds_box)
    var rv := UI.vbox(4)
    rv.custom_minimum_size.x = 220
    sh.add_child(rv)
    _preview_img = UI.vbox(0)
    rv.add_child(_preview_img)
    _preview_name = UI.heading("", 16)
    _preview_name.clip_text = true
    rv.add_child(_preview_name)
    _preview_desc = UI.label("", 13, UI.MUTED)
    _preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _preview_desc.custom_minimum_size = Vector2(220, 0)
    _preview_desc.max_lines_visible = 2
    rv.add_child(_preview_desc)

    # 참가자
    var pp := PanelContainer.new()
    pp.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(pp)
    var pv := UI.vbox(8)
    pp.add_child(pv)
    var ph := UI.hbox(12)
    pv.add_child(ph)
    _slots_label = UI.heading("참가자", 22)
    ph.add_child(_slots_label)
    _my_team_label = UI.label("", 15, UI.MUTED)
    _my_team_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _my_team_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ph.add_child(_my_team_label)
    _mode_row = UI.hbox(8)
    _mode_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    ph.add_child(_mode_row)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    pv.add_child(scroll)
    var pad := MarginContainer.new()
    pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_theme_constant_override("margin_bottom", 2)
    pad.add_theme_constant_override("margin_right", 8)
    scroll.add_child(pad)
    _slots = UI.vbox(12)
    _slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_child(_slots)

    # 아래: 상태 · 레디/시작
    var bottom := UI.hbox(16)
    left.add_child(bottom)
    _status = UI.heading("", 18, UI.CREAM)
    _status.add_theme_stylebox_override("normal", UI.box(UI.INK, 22, 18))
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    bottom.add_child(_status)
    bottom.add_child(UI.spacer())
    _ready_btn = UI.good_button("레디!")
    _ready_btn.custom_minimum_size = Vector2(220, 52)
    _ready_btn.add_theme_font_size_override("font_size", 26)
    _ready_btn.pressed.connect(_on_ready_pressed)
    bottom.add_child(_ready_btn)
    _start_btn = UI.cta_button("게임 시작!")
    _start_btn.custom_minimum_size = Vector2(240, 52)
    _start_btn.add_theme_font_size_override("font_size", 26)
    _start_btn.pressed.connect(func():
        LoadingOverlay.open(get_tree(), "게임 시작 준비 중…")
        Net.start_game())
    bottom.add_child(_start_btn)

    # ---- 오른쪽: 채팅만 (위아래 꽉)
    var chat_panel := PanelContainer.new()
    chat_panel.custom_minimum_size.x = CHAT_W
    chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(chat_panel)
    var cv := UI.vbox(10)
    chat_panel.add_child(cv)
    cv.add_child(UI.heading("채팅", 22))
    _chat_log = RichTextLabel.new()
    _chat_log.bbcode_enabled = true
    _chat_log.scroll_following = true
    _chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _chat_log.add_theme_font_size_override("normal_font_size", 16)
    _chat_log.add_theme_font_size_override("bold_font_size", 16)
    cv.add_child(_chat_log)
    _chat_input = UI.line_edit("메시지 입력 후 Enter", "", Net.CHAT_MAX)
    _chat_input.custom_minimum_size.y = 46
    _chat_input.add_theme_font_size_override("font_size", 17)
    _chat_input.text_submitted.connect(_on_chat_submit)
    cv.add_child(_chat_input)

    # 게임 중 대기 오버레이
    _playing_overlay = ColorRect.new()
    (_playing_overlay as ColorRect).color = Color(UI.INK, 0.55)
    _playing_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _playing_overlay.visible = false
    add_child(_playing_overlay)
    var ov := UI.centered_panel(_playing_overlay, 480)
    var oh := UI.heading("게임 진행 중", 30)
    oh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ov.add_child(oh)
    _overlay_text = UI.label("다른 플레이어가 돌아오기를 기다리는 중…", 18, UI.MUTED)
    _overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ov.add_child(_overlay_text)

    Net.room_updated.connect(_refresh)
    Net.chat_received.connect(_on_chat)
    for e in Net.chat_log:
        _append_chat(e.nick, e.text, e.system)
    resized.connect(_update_columns)
    _refresh(Net.room)


func _exit_tree() -> void:
    Net.room_updated.disconnect(_refresh)
    Net.chat_received.disconnect(_on_chat)


func _update_columns() -> void:
    _last_slots_key = ""
    if not Net.room.is_empty():
        _refresh(Net.room)


func _row_title(text: String) -> Label:
    var l := UI.heading(text, 17, UI.MUTED)
    l.custom_minimum_size.x = 44
    l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    l.custom_minimum_size.y = 40
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return l


func _refresh(r: Dictionary) -> void:
    if r.is_empty():
        return
    # 소리: 누가 들어오거나 나감, 내 준비 상태 변화
    var member_count: int = (r.get("members", []) as Array).size()
    var my_ready: bool = _my_entry(r).get("ready", false)
    if _last_members >= 0:
        if member_count > _last_members:
            Sfx.play("join")
        elif member_count < _last_members:
            Sfx.play("leave")
        if my_ready != _last_ready:
            Sfx.play("ready_on" if my_ready else "ready_off")
    _last_members = member_count
    _last_ready = my_ready
    var host := Net.is_host()
    var playing: bool = r.state == "playing"
    var teams := int(r.get("teams", 0))
    _title.text = String(r.name)
    _title.visible = not host
    _s_name.visible = host
    if host and not _s_name.has_focus():
        _s_name.text = String(r.name)
    for c in _state_badge_holder.get_children():
        c.queue_free()
    _state_badge_holder.add_child(UI.badge("게임 중" if playing else "대기 중", UI.DANGER if playing else UI.GOOD))
    _playing_overlay.visible = playing
    var ser: Dictionary = r.get("series", {})
    if playing and not ser.is_empty():
        _overlay_text.text = "라운드 %d/%d 진행 중 · 끝나면 이 방으로 돌아와요" % [int(ser.round), int(ser.total)]
    else:
        _overlay_text.text = "다른 플레이어가 돌아오기를 기다리는 중…"

    _build_settings(r, host and not playing)

    var members: Array = r.members
    _slots_label.text = "참가자  %d / %d" % [members.size(), int(r.max)]
    var my_team := int(_my_entry(r).get("team", -1)) if teams >= 2 else -1
    _my_team_label.text = ("내 팀: %s" % Teams.team_name(my_team)) if my_team >= 0 else ""
    if my_team >= 0:
        _my_team_label.add_theme_color_override("font_color", Teams.color(my_team).darkened(0.25))
    _build_slots(r, host, teams)

    # 아래 버튼/상태
    var me := _my_entry(r)
    _ready_btn.visible = not host
    _start_btn.visible = host
    if not host:
        var rd: bool = me.get("ready", false)
        _ready_btn.text = "레디 취소" if rd else "레디!"
        _ready_btn.add_theme_stylebox_override("normal", UI.toon_box(UI.MUTED if rd else UI.GOOD))
        _ready_btn.disabled = playing
    var reason := Net.start_block_reason(r)
    _start_btn.disabled = reason != ""
    if host:
        _status.text = "모두 준비 완료! 게임을 시작하세요" if reason == "" else reason
    else:
        var ready_count := 0
        for m in members:
            if m.ready or m.host:
                ready_count += 1
        _status.text = "준비 %d / %d  ·  방장이 시작하면 게임이 열려요" % [ready_count, members.size()]
    _status.add_theme_color_override("font_color", UI.YELLOW if (host and reason == "") else UI.CREAM)


func _my_entry(r: Dictionary) -> Dictionary:
    for m in r.members:
        if int(m.id) == Net.my_id:
            return m
    return {}


# ---------------------------------------------------------------- 경기 설정
## 경기: 라운드 1~5 칸 고정 (2열 × 3줄, R1 R2 / R3 R4 / R5). 쓰는 라운드는 [R1][게임 ▼], 안 쓰는 줄은 '+ 라운드 추가'(방장, 바로 다음 줄만)·흐린 칸
##   줄을 누르면 그 라운드 게임의 썸네일·소개를 오른쪽에. 마지막 라운드 줄 끝 × = 빼기
## 참가자 제목 옆: [팀 수 ▼] [최대 n명] [봇 채우기]  (방장이 아니면 작은 배지)
func _build_settings(r: Dictionary, editable: bool) -> void:
    var rg: Array = r.get("round_games", [String(r.get("game", ""))])
    var teams := int(r.get("teams", 0))
    _focus_round = clampi(_focus_round, 0, rg.size() - 1)
    var key := "%s|%s|%d|%d|%s|%d" % [str(rg), editable, teams, int(r.max), r.get("bot_fill", false), _focus_round]
    if key == _last_settings_key:
        return
    _last_settings_key = key
    for c in _rounds_box.get_children():
        c.queue_free()
    for c in _mode_row.get_children():
        c.queue_free()
    for i in Series.MAX_ROUNDS:
        _rounds_box.add_child(_round_line(i, rg, editable))
    _show_preview(String(rg[_focus_round]))
    # 팀 · 인원 · 봇 (참가자 제목 옆, 작게)
    if editable:
        var tsel := _small_option()
        tsel.custom_minimum_size = Vector2(92, 30)
        for t in Teams.MODES:
            tsel.add_item("개인전" if t == 0 else "%d팀" % t)
        tsel.select(Teams.MODES.find(teams))
        tsel.tooltip_text = "팀 나누기"
        tsel.item_selected.connect(func(idx): Net.update_settings({"teams": int(Teams.MODES[idx])}))
        _mode_row.add_child(tsel)
        var mx := SpinBox.new()
        mx.min_value = teams if teams >= 2 else 2
        mx.step = teams if teams >= 2 else 1
        mx.max_value = mini(Net.MAX_PLAYERS_LIMIT, Series.max_players_for(rg))
        mx.value = int(r.max)
        mx.prefix = "최대"
        mx.suffix = "명"
        mx.custom_minimum_size = Vector2(112, 30)
        mx.tooltip_text = "%d팀전: 인원은 %d명 단위" % [teams, teams] if teams >= 2 else "최대 인원"
        mx.get_line_edit().add_theme_font_size_override("font_size", 14)
        for st in ["normal", "focus"]:
            var lsb := UI.box(Color.WHITE, 10, 10, Color(UI.INK, 0.3), 2, 0)
            lsb.content_margin_top = 2
            lsb.content_margin_bottom = 2
            mx.get_line_edit().add_theme_stylebox_override(st, lsb)
        mx.value_changed.connect(func(v): Net.update_settings({"max": int(v)}))
        _mode_row.add_child(mx)
        var bots := CheckBox.new()
        bots.text = "봇 채우기"
        bots.add_theme_font_size_override("font_size", 14)
        bots.button_pressed = bool(r.bot_fill)
        bots.toggled.connect(func(on): Net.update_settings({"bot_fill": on}))
        _mode_row.add_child(bots)
    else:
        _mode_row.add_child(_mini_badge(Teams.mode_name(teams) if teams >= 2 else "개인전", UI.PRIMARY))
        _mode_row.add_child(_mini_badge("최대 %d명" % int(r.max), UI.SECONDARY))
        _mode_row.add_child(_mini_badge("봇 %s" % ("ON" if r.bot_fill else "OFF"), UI.GOOD if r.bot_fill else UI.MUTED))


func _mini_badge(text: String, color: Color) -> Control:
    var b := UI.badge(text, color)
    (b.get_child(0) as Label).add_theme_font_size_override("font_size", 13)
    return b


## 라운드 한 줄 (높이 32 고정)
func _round_line(i: int, rg: Array, editable: bool) -> Control:
    var used := i < rg.size()
    var focus := used and i == _focus_round
    var line := PanelContainer.new()
    line.custom_minimum_size.y = 31
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var bg := Color(1.0, 0.93, 0.7) if focus else (Color.WHITE if used else Color(1, 1, 1, 0.35))
    var sb := UI.box(bg, 10, 8, UI.YELLOW.darkened(0.2) if focus else Color(UI.INK, 0.15 if used else 0.08), 2, 0)
    sb.content_margin_top = 1
    sb.content_margin_bottom = 1
    line.add_theme_stylebox_override("panel", sb)
    var h := UI.hbox(8)
    line.add_child(h)
    var tag := UI.label("R%d" % (i + 1), 14, UI.INK if used else Color(UI.INK, 0.3))
    tag.custom_minimum_size.x = 26
    tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(tag)
    if used:
        var ri: int = i
        line.mouse_filter = Control.MOUSE_FILTER_STOP
        line.gui_input.connect(func(e):
            if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
                _set_focus_round(ri))
        if editable:
            var o := _small_option()
            o.custom_minimum_size = Vector2(0, 26)
            o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            o.add_theme_font_size_override("font_size", 14)
            for m in GameRegistry.all():
                o.add_item(m.display_name)
            o.add_item("랜덤")
            o.select(_choice_index(String(rg[i])))
            o.pressed.connect(func(): _set_focus_round(ri))
            o.item_selected.connect(func(idx):
                _focus_round = ri
                Net.update_settings({"round_game": [ri, _choice_at(idx)]}))
            h.add_child(o)
            if i == rg.size() - 1 and rg.size() > Series.MIN_ROUNDS:
                var x := _tiny_button("×", "%d라운드 빼기" % (i + 1))
                x.custom_minimum_size = Vector2(28, 26)
                x.pressed.connect(func(): Net.update_settings({"rounds": rg.size() - 1}))
                h.add_child(x)
        else:
            var l := UI.label(Series.choice_name(String(rg[i])), 15, UI.INK)
            l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            h.add_child(l)
    elif editable and i == rg.size():
        var add := _tiny_button("+ 라운드 추가", "%d라운드 추가" % (i + 1))
        add.custom_minimum_size = Vector2(0, 26)
        add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add.pressed.connect(func():
            _focus_round = i
            Net.update_settings({"rounds": i + 1}))
        h.add_child(add)
    else:
        var l := UI.label("—", 14, Color(UI.INK, 0.25))
        l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        h.add_child(l)
    return line


func _set_focus_round(i: int) -> void:
    if i == _focus_round:
        return
    _focus_round = i
    _last_settings_key = ""
    _refresh(Net.room)


## 오른쪽: 고른 라운드 게임 썸네일 + 이름 + 소개 (2줄)
func _show_preview(choice: String) -> void:
    for c in _preview_img.get_children():
        c.queue_free()
    var size_v := Vector2(220, 112)
    if choice == Series.RANDOM:
        var card := UI.image_card(null, size_v, UI.YELLOW)
        var q := UI.title("?", 64, UI.INK)
        q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        card.add_child(q)
        _preview_img.add_child(card)
        _preview_name.text = "R%d · 랜덤" % (_focus_round + 1)
        _preview_desc.text = "이 라운드는 시작할 때 게임을 무작위로 골라요"
    else:
        var m = GameRegistry.get_or_default(choice)
        _preview_img.add_child(UI.image_card(m.thumbnail(), size_v, m.accent))
        _preview_name.text = "R%d · %s" % [_focus_round + 1, m.display_name]
        _preview_desc.text = m.description


func _choice_at(idx: int) -> String:
    var mods: Array = GameRegistry.all()
    return mods[idx].id if idx < mods.size() else Series.RANDOM


func _choice_index(id: String) -> int:
    return GameRegistry.all().size() if id == Series.RANDOM else _module_index(id)


func _module_index(id: String) -> int:
    var mods: Array = GameRegistry.all()
    for i in mods.size():
        if mods[i].id == id:
            return i
    return 0


## 작은 고르기 상자 (설정 줄용: 높이 34)
func _small_option() -> OptionButton:
    var o := OptionButton.new()
    o.custom_minimum_size = Vector2(120, 34)
    o.clip_text = true
    o.focus_mode = Control.FOCUS_NONE
    o.add_theme_font_size_override("font_size", 15)
    for st in ["normal", "hover", "pressed", "focus"]:
        var sb := UI.box(Color.WHITE if st != "hover" else Color(1.0, 0.96, 0.88), 10, 12, Color(UI.INK, 0.3), 2, 0)
        sb.content_margin_top = 4
        sb.content_margin_bottom = 4
        o.add_theme_stylebox_override(st, sb)
    return o


## 작은 글자 단추 (×, + 라운드)
func _tiny_button(text: String, tip: String) -> Button:
    var b := Button.new()
    b.text = text
    b.tooltip_text = tip
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size = Vector2(30, 30)
    b.add_theme_font_size_override("font_size", 15)
    for st in ["normal", "hover", "pressed"]:
        var sb := UI.box(Color(UI.TEAL, 0.12) if st == "normal" else Color(UI.TEAL, 0.25), 10, 8, Color(UI.TEAL, 0.5), 2, 0)
        sb.content_margin_top = 2
        sb.content_margin_bottom = 2
        b.add_theme_stylebox_override(st, sb)
    for st in ["font_color", "font_hover_color", "font_pressed_color"]:
        b.add_theme_color_override(st, UI.TEAL.darkened(0.3))
    return b


# ---------------------------------------------------------------- 참가자
func _portrait_rect(index: int, alpha: float = 1.0) -> TextureRect:
    var t := TextureRect.new()
    t.texture = UI.portrait(index)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.custom_minimum_size = Vector2(42, 44)
    t.modulate.a = alpha
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return t


func _slots_width() -> float:
    return maxf(size.x - 48.0 - 18.0 - CHAT_W - 60.0, 280.0)


## 참가자 목록 다시 그리기 (바뀌었을 때만)
func _build_slots(r: Dictionary, host: bool, teams: int) -> void:
    var members: Array = r.members
    var key := "%s|%s|%d|%d|%s|%d|%s|%s|%d" % [str(members), host, teams, int(r.max), r.get("bot_fill", false), Net.my_id,
            str(Net.blocked.keys()), r.get("state", ""), int(_slots_width())]
    if key == _last_slots_key:
        return
    _last_slots_key = key
    for c in _slots.get_children():
        c.queue_free()
    var bot_fill := bool(r.get("bot_fill", false))
    var waiting := String(r.get("state", "")) == "waiting"
    var next_face := members.size()          # 봇 얼굴: 사람이 안 쓰는 캐릭터부터
    var bot_no := 0
    if teams >= 2:
        var per := int(ceil(float(int(r.max)) / teams))
        var compact := teams >= 3 or _slots_width() < 640.0
        var grid := GridContainer.new()
        grid.columns = teams if _slots_width() / teams >= (175.0 if compact else 290.0) else maxi(teams / 2, 1)
        grid.add_theme_constant_override("h_separation", 12 if compact else 16)
        grid.add_theme_constant_override("v_separation", 14)
        grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _slots.add_child(grid)
        var my_team := int(_my_entry(r).get("team", -1))
        for t in teams:
            var list: Array = []
            for i in members.size():
                if int(members[i].get("team", 0)) == t:
                    list.append(i)
            var col := _team_column(t, per, list.size(), my_team, waiting, compact)
            var v: VBoxContainer = col.get_meta("list")
            for i in list:
                v.add_child(_member_row(members[i], i, host, teams, t, waiting, compact))
            for k in maxi(per - list.size(), 0):
                if bot_fill:
                    bot_no += 1
                    v.add_child(_bot_row(next_face, bot_no, t, compact))
                    next_face += 1
                else:
                    v.add_child(_empty_row(t, compact))
            grid.add_child(col)
    else:
        var small := int(r.max) > 8
        var grid := GridContainer.new()
        grid.columns = clampi(int(_slots_width() / (185.0 if small else 290.0)), 1, 4 if small else 3)
        grid.add_theme_constant_override("h_separation", 12)
        grid.add_theme_constant_override("v_separation", 10)
        grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _slots.add_child(grid)
        for i in int(r.max):
            if i < members.size():
                grid.add_child(_member_row(members[i], i, host, 0, -1, waiting, small))
            elif bot_fill:
                bot_no += 1
                grid.add_child(_bot_row(i, bot_no, -1, small))
            else:
                grid.add_child(_empty_row(-1, small))


## 팀 열: 팀 색 머리글(이름·인원) — 내 팀은 굵은 테두리·진한 바탕·'내 팀' 표시, 다른 팀은 '이 팀으로' 버튼
func _team_column(t: int, per: int, count: int, my_team: int, waiting: bool, compact: bool) -> PanelContainer:
    var tc := Teams.color(t)
    var mine := t == my_team
    var col := PanelContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var sb := UI.box(tc.lerp(Color.WHITE, 0.72 if mine else 0.9), 16, 8 if compact else 12, tc.darkened(0.15) if mine else Color(tc, 0.55),
            5 if mine else 2, 5 if mine else 0)
    sb.content_margin_top = 10
    sb.content_margin_bottom = 12
    col.add_theme_stylebox_override("panel", sb)
    var v := UI.vbox(8)
    col.add_child(v)
    var head_p := PanelContainer.new()
    var hsb := UI.box(tc, 10, 10)
    hsb.content_margin_top = 6
    hsb.content_margin_bottom = 6
    head_p.add_theme_stylebox_override("panel", hsb)
    v.add_child(head_p)
    var head := UI.hbox(8)
    head_p.add_child(head)
    var fg := UI.INK if t == 3 else Color.WHITE
    var name_l := UI.heading(Teams.team_name(t), 16 if compact else 19, fg)
    name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(name_l)
    if mine:
        head.add_child(UI.badge("내 팀", Color.WHITE, tc.darkened(0.3)))
    elif waiting and my_team >= 0 and count < per:
        # 다른 팀: 머리글 안의 작은 '옮기기' 단추
        var join := Button.new()
        join.text = "옮기기" if compact else "이 팀으로"
        join.tooltip_text = "%s으로 옮기기" % Teams.team_name(t)
        join.focus_mode = Control.FOCUS_NONE
        join.add_theme_font_size_override("font_size", 13 if compact else 14)
        for st in ["normal", "hover", "pressed"]:
            var jsb := UI.box(Color.WHITE if st != "hover" else Color(1, 1, 1, 0.85), 10, 8)
            jsb.content_margin_top = 1
            jsb.content_margin_bottom = 2
            join.add_theme_stylebox_override(st, jsb)
        for st in ["font_color", "font_hover_color", "font_pressed_color"]:
            join.add_theme_color_override(st, tc.darkened(0.35))
        join.pressed.connect(func(): Net.set_team(Net.my_id, t))
        head.add_child(join)
    var cnt := UI.label("%d/%d" % [count, per], 14, fg)
    cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(cnt)
    var list := UI.vbox(8)
    v.add_child(list)
    col.set_meta("list", list)
    return col


## 줄 바탕 (사람·봇·빈 자리 공통)
func _row_panel(border: Color, border_w: int, bg: Color, compact: bool) -> Array:
    var row := PanelContainer.new()
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var sb := UI.box(bg, 12, 8 if compact else 12, border, border_w, 0)
    sb.content_margin_top = 5
    sb.content_margin_bottom = 5
    row.add_theme_stylebox_override("panel", sb)
    var h := UI.hbox(6 if compact else 12)
    row.add_child(h)
    return [row, h]


func _face(index: int, col: Color, compact: bool, alpha: float = 1.0) -> Control:
    var face := PanelContainer.new()
    face.add_theme_stylebox_override("panel", UI.box(col.lerp(Color.WHITE, 0.68), 28, 0))
    var pr := _portrait_rect(index, alpha)
    if compact:
        pr.custom_minimum_size = Vector2(34, 36)
    face.add_child(pr)
    face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return face


func _name_block(h: HBoxContainer, name: String, sub: String, sub_col: Color, compact: bool) -> void:
    var mid := UI.vbox(2)
    mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mid.alignment = BoxContainer.ALIGNMENT_CENTER
    h.add_child(mid)
    var name_l := UI.heading(name, 16 if compact else 18)
    name_l.custom_minimum_size.x = 44 if compact else 72
    name_l.clip_text = true
    name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    mid.add_child(name_l)
    if sub != "":
        var sl := UI.label(sub, 12 if compact else 13, sub_col)
        sl.clip_text = true
        mid.add_child(sl)


func _member_row(m: Dictionary, index: int, host: bool, teams: int, team: int, waiting: bool, compact: bool = false) -> Control:
    var is_me := int(m.id) == Net.my_id
    var rp := _row_panel(UI.CTA if is_me else Color(UI.INK, 0.18), 3 if is_me else 2, Color.WHITE, compact)
    var row: PanelContainer = rp[0]
    var h: HBoxContainer = rp[1]
    var col: Color = Teams.color(team) if team >= 0 else Fighter.SLOT_COLORS[index % Fighter.SLOT_COLORS.size()]
    h.add_child(_face(index, col, compact))
    var uid := String(m.get("uid", ""))
    var blocked := uid != "" and Net.blocked.has(uid)
    var st_text := "방장" if m.host else ("READY" if m.ready else "대기")
    var st_col: Color = UI.YELLOW if m.host else (UI.GOOD if m.ready else UI.MUTED)
    var tags := PackedStringArray()
    if compact:
        tags.append(st_text)
    if is_me:
        tags.append("나")
    if blocked:
        tags.append("차단함")
    _name_block(h, String(m.nick), " · ".join(tags), UI.DANGER if blocked else (st_col.darkened(0.25) if compact else UI.MUTED), compact)
    if not compact:
        h.add_child(UI.badge(st_text, st_col, UI.INK if m.host else Color.WHITE))
    var acts: Array = []
    var pid := int(m.id)
    if host and not is_me and waiting and teams >= 2:
        for t in teams:
            if t != team:
                var tv: int = t
                acts.append(["%s으로 옮기기" % Teams.team_name(t), func(): Net.set_team(pid, tv)])
    if host and not is_me:
        acts.append(["방장 넘기기", func(): Net.transfer_host(pid)])
        acts.append(["내보내기 (강퇴)", func(): Net.kick(pid)])
    if not is_me:
        var nick_s := String(m.nick)
        acts.append(["신고하기", func(): _open_report(pid, nick_s)])
        if uid != "":
            acts.append(["차단 해제" if blocked else "채팅 차단", func():
                Net.set_blocked(uid, nick_s, not blocked)
                _append_chat("", "%s 님을 %s" % [nick_s, "차단 해제했어요" if blocked else "차단했어요. 이 사람의 채팅이 보이지 않아요"], true)
                _last_slots_key = ""
                _refresh(Net.room)])
    if not acts.is_empty():
        var mb := _more_menu(acts)
        if compact:
            mb.custom_minimum_size = Vector2(28, 28)
        h.add_child(mb)
    elif not compact:
        var gap := Control.new()
        gap.custom_minimum_size.x = 40
        h.add_child(gap)
    return row


## 봇 자리: 사람과 같은 줄 모양 (얼굴·이름·'BOT' 표시) — 게임에서 봇이 이 자리를 맡음
func _bot_row(face: int, no: int, team: int, compact: bool) -> Control:
    var col: Color = Teams.color(team) if team >= 0 else Fighter.SLOT_COLORS[face % Fighter.SLOT_COLORS.size()]
    var rp := _row_panel(Color(UI.INK, 0.12), 2, Color(0.96, 0.97, 1.0), compact)
    var row: PanelContainer = rp[0]
    var h: HBoxContainer = rp[1]
    h.add_child(_face(face % 12, col, compact, 0.9))
    _name_block(h, "Bot %d" % no, ("BOT · 준비됨" if compact else "컴퓨터가 함께해요"), UI.MUTED, compact)
    if not compact:
        h.add_child(UI.badge("BOT", UI.SECONDARY))
        var gap := Control.new()
        gap.custom_minimum_size.x = 40
        h.add_child(gap)
    return row


## 빈 자리 (봇 채우기 끔): 점선 느낌의 옅은 줄
func _empty_row(team: int, compact: bool) -> Control:
    var col: Color = Teams.color(team) if team >= 0 else UI.INK
    var rp := _row_panel(Color(col, 0.3), 2, Color(1, 1, 1, 0.4), compact)
    var row: PanelContainer = rp[0]
    var h: HBoxContainer = rp[1]
    var ph := PanelContainer.new()
    ph.add_theme_stylebox_override("panel", UI.box(Color(col, 0.08), 28, 0, Color(col, 0.25), 2))
    ph.custom_minimum_size = Vector2(34, 36) if compact else Vector2(42, 44)
    ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(ph)
    _name_block(h, "빈 자리", "" if compact else "참가자를 기다려요", UI.MUTED, compact)
    return row


## '•••' 더보기 단추 → 펼침 메뉴
func _more_menu(acts: Array) -> MenuButton:
    var mb := MenuButton.new()
    mb.text = "•••"
    mb.flat = false
    mb.focus_mode = Control.FOCUS_NONE
    mb.tooltip_text = "더보기"
    mb.custom_minimum_size = Vector2(40, 34)
    mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    mb.add_theme_font_size_override("font_size", 14)
    for st in ["normal", "hover", "pressed", "focus"]:
        var sb := UI.box(Color(UI.INK, 0.06) if st == "normal" else Color(UI.INK, 0.14), 10, 8)
        mb.add_theme_stylebox_override(st, sb)
    for st in ["font_color", "font_hover_color", "font_pressed_color"]:
        mb.add_theme_color_override(st, UI.INK)
    var pop := mb.get_popup()
    pop.add_theme_font_size_override("font_size", 16)
    for i in acts.size():
        pop.add_item(String(acts[i][0]), i)
    pop.id_pressed.connect(func(id: int): (acts[id][1] as Callable).call())
    return mb


# ---------------------------------------------------------------- 신고
var _report_dlg: Control
var _report_reason: OptionButton
var _report_detail: LineEdit
var _report_title: Label
var _report_target := 0


func _open_report(pid: int, nick: String) -> void:
    if _report_dlg == null:
        _report_dlg = ColorRect.new()
        (_report_dlg as ColorRect).color = Color(UI.INK, 0.55)
        _report_dlg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(_report_dlg)
        var v := UI.centered_panel(_report_dlg, 460)
        _report_title = UI.heading("", 26)
        v.add_child(_report_title)
        var note := UI.label("운영자가 신고 내용과 이 방의 최근 채팅을 확인해요. 거짓 신고는 제재될 수 있어요.", 15, UI.MUTED)
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        v.add_child(note)
        _report_reason = OptionButton.new()
        _report_reason.add_theme_font_size_override("font_size", 18)
        for k in Net.REPORT_REASONS:
            _report_reason.add_item(Net.REPORT_REASONS[k])
            _report_reason.set_item_metadata(_report_reason.item_count - 1, k)
        v.add_child(_report_reason)
        _report_detail = UI.line_edit("자세한 내용 (선택)", "", 200)
        v.add_child(_report_detail)
        var row := UI.hbox(10)
        v.add_child(row)
        var cancel := UI.secondary_button("취소")
        cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        cancel.pressed.connect(func(): _report_dlg.visible = false)
        row.add_child(cancel)
        var send := UI.cta_button("신고하기")
        send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        send.pressed.connect(func():
            Net.report(_report_target, String(_report_reason.get_item_metadata(_report_reason.selected)), _report_detail.text)
            _report_dlg.visible = false)
        row.add_child(send)
    _report_target = pid
    _report_title.text = "%s 님 신고" % nick
    _report_reason.select(0)
    _report_detail.clear()
    _report_dlg.visible = true


# ---------------------------------------------------------------- 레디 / 채팅
func _on_ready_pressed() -> void:
    var me := _my_entry(Net.room)
    Net.set_ready(not me.get("ready", false))


func _on_chat_submit(text: String) -> void:
    if text.strip_edges() != "":
        Net.send_chat(text)
    _chat_input.clear()


func _on_chat(nick: String, text: String, system: bool) -> void:
    _append_chat(nick, text, system)
    if not system and nick != Net.nickname:
        Sfx.play("chat")


func _append_chat(nick: String, text: String, system: bool) -> void:
    if not system and Net.is_blocked_nick(nick):
        return              # 차단한 사람의 채팅은 숨김
    var safe := text.replace("[", "[lb]")
    if system:
        _chat_log.append_text("[color=#8a90a6]· %s[/color]\n" % safe)
    else:
        var col := "#e8603f" if nick == Net.nickname else "#2f6fd6"
        _chat_log.append_text("[b][color=%s]%s[/color][/b]  %s\n" % [col, nick.replace("[", "[lb]"), safe])
