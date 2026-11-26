extends Control
## 3단계: 대기룸 — 참가자 슬롯(캐릭터 초상화, 최대 12), 레디, 방장 설정/강퇴/위임, 채팅, 게임 시작
## 슬롯 색 = 게임 안 캐릭터 색 (Fighter.SLOT_COLORS, 초상화 ui/portraits/slot_N.png)

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")
const Series := preload("res://scripts/core/series.gd")
const Teams := preload("res://scripts/core/teams.gd")

var app: Node
var _title: Label
var _state_badge_holder: HBoxContainer
var _slots_label: Label
var _grid: GridContainer
var _game_img_holder: Control
var _game_name: Label
var _game_desc: Label
var _settings_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _status: Label
var _ready_btn: Button
var _start_btn: Button
var _playing_overlay: Control
var _s_name: LineEdit
var _s_max: SpinBox
var _s_bots: CheckBox
var _s_rounds: SpinBox
var _s_teams: OptionButton
var _s_round_box: GridContainer
var _s_round_opts: Array[OptionButton] = []
var _overlay_text: Label
var _settings_mode := ""
var _shown_game := ""


var _last_members := -1
var _last_ready := false


func _ready() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 28)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_bottom", 22)
    add_child(margin)
    var root := UI.vbox(14)
    margin.add_child(root)

    # 상단 바: 방 이름 · 게임/상태 배지 · 나가기
    var top := UI.hbox(12)
    root.add_child(top)
    _title = UI.title("", 38)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _title.clip_text = true
    _title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _title.size_flags_stretch_ratio = 3.0
    top.add_child(_title)
    _state_badge_holder = UI.hbox(8)
    top.add_child(_state_badge_holder)
    var snd := UI.sound_button()
    snd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(snd)
    var leave := UI.pill_button("방 나가기")
    leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    leave.pressed.connect(func(): Net.leave_room())
    top.add_child(leave)

    # 본문: 왼쪽 슬롯 / 오른쪽 게임 카드 + 채팅
    var body := UI.hbox(16)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)

    var left := PanelContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(left)
    var lv := UI.vbox(10)
    left.add_child(lv)
    _slots_label = UI.heading("참가자", 26)
    lv.add_child(_slots_label)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    lv.add_child(scroll)
    var pad := MarginContainer.new()
    pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_theme_constant_override("margin_bottom", 8)
    pad.add_theme_constant_override("margin_right", 6)
    scroll.add_child(pad)
    _grid = GridContainer.new()
    _grid.columns = 4
    _grid.add_theme_constant_override("h_separation", 12)
    _grid.add_theme_constant_override("v_separation", 12)
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_child(_grid)

    var right := UI.vbox(14)
    right.custom_minimum_size.x = 370
    body.add_child(right)

    # 게임 카드 (썸네일 + 이름 + 설명 + 설정)
    var game_panel := PanelContainer.new()
    right.add_child(game_panel)
    var gv := UI.vbox(10)
    game_panel.add_child(gv)
    var gh := UI.hbox(12)
    gv.add_child(gh)
    _game_img_holder = UI.vbox(0)
    gh.add_child(_game_img_holder)
    var gt := UI.vbox(2)
    gt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    gt.alignment = BoxContainer.ALIGNMENT_CENTER
    gh.add_child(gt)
    _game_name = UI.heading("", 22)
    _game_name.clip_text = true
    _game_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    gt.add_child(_game_name)
    _game_desc = UI.label("", 13, UI.MUTED)
    _game_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    gt.add_child(_game_desc)
    _settings_box = UI.vbox(8)
    gv.add_child(_settings_box)

    var chat_panel := PanelContainer.new()
    chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(chat_panel)
    var cv := UI.vbox(8)
    chat_panel.add_child(cv)
    cv.add_child(UI.heading("채팅", 20))
    _chat_log = RichTextLabel.new()
    _chat_log.bbcode_enabled = true
    _chat_log.scroll_following = true
    _chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _chat_log.custom_minimum_size.y = 50
    _chat_log.add_theme_font_size_override("normal_font_size", 16)
    _chat_log.add_theme_font_size_override("bold_font_size", 16)
    cv.add_child(_chat_log)
    _chat_input = UI.line_edit("메시지 입력 후 Enter", "", Net.CHAT_MAX)
    _chat_input.custom_minimum_size.y = 46
    _chat_input.add_theme_font_size_override("font_size", 17)
    _chat_input.text_submitted.connect(_on_chat_submit)
    cv.add_child(_chat_input)

    # 하단 바: 상태 문구 + 큰 버튼
    var bottom := UI.hbox(14)
    root.add_child(bottom)
    _status = UI.heading("", 19, UI.CREAM)
    _status.add_theme_stylebox_override("normal", UI.box(UI.INK, 22, 18))
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    bottom.add_child(_status)
    bottom.add_child(UI.spacer())
    _ready_btn = UI.good_button("레디!")
    _ready_btn.custom_minimum_size = Vector2(230, 62)
    _ready_btn.add_theme_font_size_override("font_size", 28)
    _ready_btn.pressed.connect(_on_ready_pressed)
    bottom.add_child(_ready_btn)
    _start_btn = UI.cta_button("게임 시작!")
    _start_btn.custom_minimum_size = Vector2(250, 62)
    _start_btn.add_theme_font_size_override("font_size", 28)
    _start_btn.pressed.connect(func(): Net.start_game())
    bottom.add_child(_start_btn)

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
    _update_columns()
    _refresh(Net.room)


func _exit_tree() -> void:
    Net.room_updated.disconnect(_refresh)
    Net.chat_received.disconnect(_on_chat)


func _update_columns() -> void:
    if _grid:
        _grid.columns = 4 if size.x >= 1180 else 3


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
    var first_choice := String(r.get("game", ""))
    var module = GameRegistry.get_or_default(first_choice)
    var rounds: int = int(r.get("rounds", 1))
    _title.text = String(r.name)
    for c in _state_badge_holder.get_children():
        c.queue_free()
    var playing: bool = r.state == "playing"
    var teams := int(r.get("teams", 0))
    _state_badge_holder.add_child(UI.badge(Teams.mode_name(teams), UI.PRIMARY if teams >= 2 else UI.SECONDARY))
    _state_badge_holder.add_child(UI.badge("%d라운드" % rounds, UI.SECONDARY))
    _state_badge_holder.add_child(UI.badge("게임 중" if playing else "대기 중", UI.DANGER if playing else UI.GOOD))
    _playing_overlay.visible = playing
    var ser: Dictionary = r.get("series", {})
    if playing and not ser.is_empty():
        _overlay_text.text = "라운드 %d/%d 진행 중 · 끝나면 이 방으로 돌아와요" % [int(ser.round), int(ser.total)]
    else:
        _overlay_text.text = "다른 플레이어가 돌아오기를 기다리는 중…"

    # 게임 카드
    var card_id: String = first_choice if first_choice == Series.RANDOM else String(module.id)
    if _shown_game != card_id:
        _shown_game = card_id
        for c in _game_img_holder.get_children():
            c.queue_free()
        if card_id == Series.RANDOM:
            _game_img_holder.add_child(UI.image_card(null, Vector2(150, 86), UI.YELLOW))
        else:
            _game_img_holder.add_child(UI.image_card(module.thumbnail(), Vector2(150, 86), module.accent))
    var rg: Array = r.get("round_games", [first_choice])
    var names := PackedStringArray()
    for g in rg:
        names.append(Series.choice_name(String(g)))
    _game_name.text = Series.choice_name(first_choice) if rounds == 1 else "%d라운드 경기" % rounds
    if rounds > 1:
        _game_desc.text = "%s\n라운드마다 1등 3점 · 2등 2점 · 3등 1점, 합계 1위가 우승" % " → ".join(names)
    else:
        _game_desc.text = module.description if first_choice != Series.RANDOM else "게임을 무작위로 골라요"

    # 슬롯
    for c in _grid.get_children():
        c.queue_free()
    var members: Array = r.members
    _slots_label.text = "참가자  %d / %d" % [members.size(), int(r.max)]
    for i in int(r.max):
        if i < members.size():
            _grid.add_child(_member_card(members[i], i, host, teams))
        else:
            _grid.add_child(_empty_card(i, bool(r.bot_fill)))

    _build_settings(r, host, module)

    # 하단 버튼/상태
    var me := _my_entry(r)
    _ready_btn.visible = not host
    _start_btn.visible = host
    if not host:
        var rd: bool = me.get("ready", false)
        _ready_btn.text = "레디 취소" if rd else "레디!"
        var sb := UI.toon_box(UI.MUTED if rd else UI.GOOD)
        _ready_btn.add_theme_stylebox_override("normal", sb)
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


func _slot_card(index: int, border: Color, border_w: int, bg: Color) -> PanelContainer:
    var card := PanelContainer.new()
    var sb := UI.box(bg, 16, 8, border, border_w, 4 if border_w > 0 else 0)
    sb.content_margin_top = 6
    sb.content_margin_bottom = 8
    card.add_theme_stylebox_override("panel", sb)
    card.custom_minimum_size = Vector2(0, 160)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return card


func _portrait_rect(index: int, alpha: float = 1.0) -> TextureRect:
    var t := TextureRect.new()
    t.texture = UI.portrait(index)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.custom_minimum_size = Vector2(0, 104)
    t.modulate.a = alpha
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return t


func _member_card(m: Dictionary, index: int, viewer_is_host: bool, teams: int = 0) -> Control:
    var is_me := int(m.id) == Net.my_id
    var color: Color = Fighter.SLOT_COLORS[index % Fighter.SLOT_COLORS.size()]
    var team := int(m.get("team", 0)) if teams >= 2 else -1
    if team >= 0:
        color = Teams.color(team)            # 팀전: 카드 색 = 팀 색
    var card := _slot_card(index, UI.CTA if is_me else (Teams.color(team).darkened(0.2) if team >= 0 else UI.INK), 5 if is_me or team >= 0 else 3,
            color.lerp(Color.WHITE, 0.72))
    var v := UI.vbox(2)
    card.add_child(v)

    # 초상화 + 왼쪽 위 상태 배지
    var face := Control.new()
    face.custom_minimum_size = Vector2(0, 104)
    v.add_child(face)
    var pr := _portrait_rect(index)
    pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    face.add_child(pr)
    var b: Control
    if m.host:
        b = UI.badge("★ 방장", UI.CTA, UI.INK)
    elif m.ready:
        b = UI.badge("READY", UI.GOOD)
    else:
        b = UI.badge("대기", UI.MUTED)
    b.position = Vector2(2, 2)
    face.add_child(b)
    if team >= 0:
        var tb := UI.badge(Teams.SHORT[team], Teams.color(team), UI.INK if team == 3 else Color.WHITE)
        tb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
        tb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        tb.grow_vertical = Control.GROW_DIRECTION_BEGIN
        face.add_child(tb)

    var name_l := UI.heading(String(m.nick), 20)
    name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_l.clip_text = true
    name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    v.add_child(name_l)
    if is_me:
        var me_l := UI.label("나", 13, UI.MUTED)
        me_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        v.add_child(me_l)

    # 팀 바꾸기: 나 자신은 누구나, 다른 사람은 방장만
    if team >= 0 and (is_me or viewer_is_host) and Net.room.get("state", "") == "waiting":
        var pid_t := int(m.id)
        var next_team := (team + 1) % teams
        var tbtn := _small_button("→ %s" % Teams.SHORT[next_team], Teams.color(next_team).darkened(0.1))
        tbtn.pressed.connect(func(): Net.set_team(pid_t, next_team))
        var trow := UI.hbox(0)
        trow.alignment = BoxContainer.ALIGNMENT_CENTER
        trow.add_child(tbtn)
        v.add_child(trow)
    if viewer_is_host and not is_me:
        var acts := UI.hbox(6)
        acts.alignment = BoxContainer.ALIGNMENT_CENTER
        v.add_child(acts)
        var pid := int(m.id)
        var kick := _small_button("강퇴", UI.DANGER)
        kick.pressed.connect(func(): Net.kick(pid))
        acts.add_child(kick)
        var give := _small_button("방장 위임", UI.SECONDARY)
        give.pressed.connect(func(): Net.transfer_host(pid))
        acts.add_child(give)
    # 신고·차단: 다른 사람 누구에게나
    if not is_me:
        var safety := UI.hbox(6)
        safety.alignment = BoxContainer.ALIGNMENT_CENTER
        v.add_child(safety)
        var pid_s := int(m.id)
        var nick_s := String(m.nick)
        var uid := String(m.get("uid", ""))
        var rep := _small_button("신고", UI.MUTED)
        rep.pressed.connect(func(): _open_report(pid_s, nick_s))
        safety.add_child(rep)
        if uid != "":
            var is_blocked := Net.blocked.has(uid)
            var blk := _small_button("차단 해제" if is_blocked else "차단", UI.SECONDARY if is_blocked else UI.MUTED)
            blk.tooltip_text = "이 사람의 채팅을 내 화면에서 숨겨요"
            blk.pressed.connect(func():
                Net.set_blocked(uid, nick_s, not is_blocked)
                _append_chat("", "%s 님을 %s" % [nick_s, "차단 해제했어요" if is_blocked else "차단했어요. 이 사람의 채팅이 보이지 않아요"], true)
                _refresh(Net.room))
            safety.add_child(blk)
        if Net.blocked.has(uid):
            var bl := UI.label("차단함", 12, UI.DANGER)
            bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            v.add_child(bl)
    return card


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


func _empty_card(index: int, bot_fill: bool) -> Control:
    var card := _slot_card(index, Color(UI.INK, 0.18), 3, Color(0.9, 0.92, 0.96))
    (card.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size = 0
    var v := UI.vbox(2)
    card.add_child(v)
    var pr := _portrait_rect(index, 0.6 if bot_fill else 1.0)
    if not bot_fill:
        pr.modulate = Color(0.55, 0.58, 0.66, 0.35)      # 실루엣
    v.add_child(pr)
    var l := UI.heading("봇" if bot_fill else "빈 자리", 19, UI.MUTED)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(l)
    return card


func _small_button(text: String, color: Color) -> Button:
    var b := UI.colored_button(text, color, color.lightened(0.15))
    b.custom_minimum_size = Vector2(0, 32)
    b.add_theme_font_size_override("font_size", 14)
    b.remove_theme_constant_override("outline_size")
    for st in ["normal", "hover", "pressed", "disabled"]:
        var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
        sb.content_margin_left = 8
        sb.content_margin_right = 8
        sb.content_margin_top = 2
        sb.content_margin_bottom = 4
        sb.set_border_width_all(2)
        sb.shadow_offset = Vector2(0, 2)
        b.add_theme_stylebox_override(st, sb)
    return b


# ---------------------------------------------------------------- 설정
func _build_settings(r: Dictionary, host: bool, module) -> void:
    # 방장이 입력 중일 때 덮어쓰지 않도록, 방장 화면은 값만 갱신하고 위젯은 유지
    var rg: Array = r.get("round_games", [String(r.get("game", ""))])
    if host and _settings_mode == "host":
        _sync_round_widgets(rg)
        var ti := Teams.MODES.find(int(r.get("teams", 0)))
        if _s_teams.selected != ti:
            _s_teams.select(ti)
        _s_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, Series.max_players_for(rg))
        _s_max.set_value_no_signal(int(r.max))
        _s_bots.set_pressed_no_signal(bool(r.bot_fill))
        if not _s_name.has_focus():
            _s_name.text = String(r.name)
        return
    _settings_mode = "host" if host else "guest"
    for c in _settings_box.get_children():
        c.queue_free()
    if host:
        # 1줄: 방 이름
        var nrow := UI.hbox(8)
        _settings_box.add_child(nrow)
        nrow.add_child(_field_label("방 이름"))
        _s_name = UI.line_edit("방 이름", String(r.name), Net.ROOM_NAME_MAX)
        _s_name.custom_minimum_size.y = 40
        _s_name.add_theme_font_size_override("font_size", 17)
        _s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _s_name.text_submitted.connect(func(t): Net.update_settings({"name": t}))
        _s_name.focus_exited.connect(func(): Net.update_settings({"name": _s_name.text}))
        nrow.add_child(_s_name)
        _s_teams = OptionButton.new()
        _s_teams.custom_minimum_size = Vector2(112, 40)
        _s_teams.add_theme_font_size_override("font_size", 15)
        for t in Teams.MODES:
            _s_teams.add_item(Teams.mode_name(t))
        _s_teams.select(Teams.MODES.find(int(r.get("teams", 0))))
        _s_teams.item_selected.connect(func(idx): Net.update_settings({"teams": Teams.MODES[idx]}))
        nrow.add_child(_s_teams)

        # 2줄: 라운드 수(1~5) · 최대 인원 · 봇 채우기
        var mrow := UI.hbox(8)
        _settings_box.add_child(mrow)
        _s_rounds = SpinBox.new()
        _s_rounds.min_value = Series.MIN_ROUNDS
        _s_rounds.max_value = Series.MAX_ROUNDS
        _s_rounds.value = rg.size()
        _s_rounds.suffix = "라운드"
        _s_rounds.custom_minimum_size = Vector2(128, 40)
        _s_rounds.value_changed.connect(func(v): Net.update_settings({"rounds": int(v)}))
        mrow.add_child(_s_rounds)
        _s_max = SpinBox.new()
        _s_max.min_value = 2
        _s_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, Series.max_players_for(rg))
        _s_max.value = int(r.max)
        _s_max.suffix = "명"
        _s_max.custom_minimum_size = Vector2(104, 40)
        _s_max.value_changed.connect(func(v): Net.update_settings({"max": int(v)}))
        mrow.add_child(_s_max)
        _s_bots = CheckBox.new()
        _s_bots.text = "봇 채우기"
        _s_bots.add_theme_font_size_override("font_size", 16)
        _s_bots.button_pressed = bool(r.bot_fill)
        _s_bots.toggled.connect(func(on): Net.update_settings({"bot_fill": on}))
        mrow.add_child(_s_bots)

        # 라운드별 게임 (같은 게임 여러 번 / 랜덤) — 두 칸씩
        var grid := GridContainer.new()
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 8)
        grid.add_theme_constant_override("v_separation", 6)
        _settings_box.add_child(grid)
        _s_round_box = grid
        _s_round_opts.clear()
        _sync_round_widgets(rg)
    else:
        var list := PackedStringArray()
        for i in rg.size():
            list.append("%d. %s" % [i + 1, Series.choice_name(String(rg[i]))])
        var rl := UI.label("\n".join(list), 15, UI.INK)
        _settings_box.add_child(rl)
        var chips := UI.hbox(6)
        _settings_box.add_child(chips)
        chips.add_child(UI.badge(Teams.mode_name(int(r.get("teams", 0))), UI.PRIMARY if int(r.get("teams", 0)) >= 2 else UI.SECONDARY))
        chips.add_child(UI.badge("최대 %d명" % int(r.max), UI.SECONDARY))
        chips.add_child(UI.badge("봇 채우기 %s" % ("ON" if r.bot_fill else "OFF"), UI.GOOD if r.bot_fill else UI.MUTED))
        _settings_box.add_child(UI.label("설정은 방장만 바꿀 수 있어요", 13, UI.MUTED))


## 방장 화면: 라운드 수에 맞춰 라운드별 게임 선택 상자를 만들고 값 맞추기
func _sync_round_widgets(rg: Array) -> void:
    if not _s_rounds.get_line_edit().has_focus():
        _s_rounds.set_value_no_signal(rg.size())
    while _s_round_opts.size() > rg.size():
        var o: OptionButton = _s_round_opts.pop_back()
        o.get_parent().queue_free()
    while _s_round_opts.size() < rg.size():
        var i := _s_round_opts.size()
        var row := UI.hbox(6)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _s_round_box.add_child(row)
        var l := UI.label("%dR" % (i + 1), 15, UI.MUTED)
        l.custom_minimum_size.x = 26
        l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(l)
        var o := OptionButton.new()
        o.custom_minimum_size.y = 36
        o.clip_text = true
        o.add_theme_font_size_override("font_size", 15)
        o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        for m in GameRegistry.all():
            o.add_item(m.display_name)
        o.add_item("랜덤")
        o.item_selected.connect(func(idx): Net.update_settings({"round_game": [i, _choice_at(idx)]}))
        row.add_child(o)
        _s_round_opts.append(o)
    for i in rg.size():
        var idx := _choice_index(String(rg[i]))
        if _s_round_opts[i].selected != idx:
            _s_round_opts[i].select(idx)


func _choice_at(idx: int) -> String:
    var mods: Array = GameRegistry.all()
    return mods[idx].id if idx < mods.size() else Series.RANDOM


func _choice_index(id: String) -> int:
    return GameRegistry.all().size() if id == Series.RANDOM else _module_index(id)


func _field_label(text: String) -> Label:
    var l := UI.heading(text, 16, UI.MUTED)
    l.custom_minimum_size.x = 72
    l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return l


func _module_index(id: String) -> int:
    var mods: Array = GameRegistry.all()
    for i in mods.size():
        if mods[i].id == id:
            return i
    return 0


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
