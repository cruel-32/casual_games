extends Control
## 3단계: 대기룸 — 참가자 슬롯(캐릭터 초상화, 최대 12), 레디, 방장 설정/강퇴/위임, 채팅, 게임 시작
## 슬롯 색 = 게임 안 캐릭터 색 (Fighter.SLOT_COLORS, 초상화 ui/portraits/slot_N.png)

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")

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
var _s_game: OptionButton
var _settings_mode := ""
var _shown_game := ""


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
    var ol := UI.label("다른 플레이어가 돌아오기를 기다리는 중…", 18, UI.MUTED)
    ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ov.add_child(ol)

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
    var host := Net.is_host()
    var module = GameRegistry.get_or_default(String(r.get("game", "")))
    _title.text = String(r.name)
    for c in _state_badge_holder.get_children():
        c.queue_free()
    var playing: bool = r.state == "playing"
    _state_badge_holder.add_child(UI.badge(module.display_name, module.accent))
    _state_badge_holder.add_child(UI.badge("게임 중" if playing else "대기 중", UI.DANGER if playing else UI.GOOD))
    _playing_overlay.visible = playing

    # 게임 카드
    if _shown_game != module.id:
        _shown_game = module.id
        for c in _game_img_holder.get_children():
            c.queue_free()
        _game_img_holder.add_child(UI.image_card(module.thumbnail(), Vector2(150, 86), module.accent))
    _game_name.text = module.display_name
    _game_desc.text = module.description

    # 슬롯
    for c in _grid.get_children():
        c.queue_free()
    var members: Array = r.members
    _slots_label.text = "참가자  %d / %d" % [members.size(), int(r.max)]
    for i in int(r.max):
        if i < members.size():
            _grid.add_child(_member_card(members[i], i, host))
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


func _member_card(m: Dictionary, index: int, viewer_is_host: bool) -> Control:
    var is_me := int(m.id) == Net.my_id
    var color: Color = Fighter.SLOT_COLORS[index % Fighter.SLOT_COLORS.size()]
    var card := _slot_card(index, UI.CTA if is_me else UI.INK, 5 if is_me else 3,
            color.lerp(Color.WHITE, 0.78))
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

    var name_l := UI.heading(String(m.nick), 20)
    name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_l.clip_text = true
    name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    v.add_child(name_l)
    if is_me:
        var me_l := UI.label("나", 13, UI.MUTED)
        me_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        v.add_child(me_l)

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
    return card


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
    if host and _settings_mode == "host":
        var gi := _module_index(module.id)
        if _s_game.selected != gi:
            _s_game.select(gi)
        _s_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, module.max_players)
        _s_bots.disabled = not module.supports_bots
        _s_max.set_value_no_signal(int(r.max))
        _s_bots.set_pressed_no_signal(bool(r.bot_fill))
        if not _s_name.has_focus():
            _s_name.text = String(r.name)
        return
    _settings_mode = "host" if host else "guest"
    for c in _settings_box.get_children():
        c.queue_free()
    if host:
        var grow := UI.hbox(8)
        _settings_box.add_child(grow)
        grow.add_child(_field_label("게임"))
        _s_game = OptionButton.new()
        _s_game.custom_minimum_size.y = 42
        _s_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        for m in GameRegistry.all():
            _s_game.add_item(m.display_name)
        _s_game.select(_module_index(module.id))
        _s_game.item_selected.connect(func(i): Net.update_settings({"game": GameRegistry.all()[i].id}))
        grow.add_child(_s_game)

        var nrow := UI.hbox(8)
        _settings_box.add_child(nrow)
        nrow.add_child(_field_label("방 이름"))
        _s_name = UI.line_edit("방 이름", String(r.name), Net.ROOM_NAME_MAX)
        _s_name.custom_minimum_size.y = 42
        _s_name.add_theme_font_size_override("font_size", 17)
        _s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _s_name.text_submitted.connect(func(t): Net.update_settings({"name": t}))
        _s_name.focus_exited.connect(func(): Net.update_settings({"name": _s_name.text}))
        nrow.add_child(_s_name)

        var mrow := UI.hbox(8)
        _settings_box.add_child(mrow)
        mrow.add_child(_field_label("최대 인원"))
        _s_max = SpinBox.new()
        _s_max.min_value = 2
        _s_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, module.max_players)
        _s_max.value = int(r.max)
        _s_max.suffix = "명"
        _s_max.custom_minimum_size = Vector2(110, 42)
        _s_max.value_changed.connect(func(v): Net.update_settings({"max": int(v)}))
        mrow.add_child(_s_max)
        _s_bots = CheckBox.new()
        _s_bots.text = "봇 채우기"
        _s_bots.add_theme_font_size_override("font_size", 17)
        _s_bots.button_pressed = bool(r.bot_fill)
        _s_bots.disabled = not module.supports_bots
        _s_bots.toggled.connect(func(on): Net.update_settings({"bot_fill": on}))
        mrow.add_child(_s_bots)
    else:
        var chips := UI.hbox(6)
        _settings_box.add_child(chips)
        chips.add_child(UI.badge("최대 %d명" % int(r.max), UI.SECONDARY))
        chips.add_child(UI.badge("봇 채우기 %s" % ("ON" if r.bot_fill else "OFF"), UI.GOOD if r.bot_fill else UI.MUTED))
        _settings_box.add_child(UI.label("설정은 방장만 바꿀 수 있어요", 13, UI.MUTED))


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


func _append_chat(nick: String, text: String, system: bool) -> void:
    var safe := text.replace("[", "[lb]")
    if system:
        _chat_log.append_text("[color=#8a90a6]· %s[/color]\n" % safe)
    else:
        var col := "#e8603f" if nick == Net.nickname else "#2f6fd6"
        _chat_log.append_text("[b][color=%s]%s[/color][/b]  %s\n" % [col, nick.replace("[", "[lb]"), safe])
