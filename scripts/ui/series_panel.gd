extends PanelContainer
## 온라인 경기가 끝났을 때 결과 화면 (모든 게임 공통)
##   라운드 N/M 결과: 이번 라운드 순위(+승점) · 합계 순위표
##   - 라운드 사이: [다음 라운드 레디] — 모두 레디하거나 시간이 다 되면 다음 라운드가 자동으로 시작
##   - 마지막 라운드: 최종 우승 + [방으로 돌아가기]
## 점수는 서버가 계산해 방 정보(Net.room.series)로 보내 준다 (scripts/core/series.gd)

const UI := preload("res://scripts/ui/ui_kit.gd")
const Series := preload("res://scripts/core/series.gd")

var game: PartyGame

var _title: Label
var _sub: Label
var _round_list: VBoxContainer
var _total_list: VBoxContainer
var _status: Label
var _ready_btn: Button
var _leave_btn: Button
var _shown_key := ""


func _ready() -> void:
    visible = false
    add_to_group("touch_block")
    add_theme_stylebox_override("panel", UI.box(UI.CREAM, 22, 20, UI.INK, UI.OUTLINE, 8))
    custom_minimum_size.x = 640
    var v := UI.vbox(10)
    add_child(v)
    _title = UI.heading("", 28)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(_title)
    _sub = UI.label("", 16, UI.MUTED)
    _sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(_sub)
    var cols := UI.hbox(16)
    v.add_child(cols)
    _round_list = _column(cols, "이번 라운드")
    _total_list = _column(cols, "합계")
    var bottom := UI.hbox(12)
    v.add_child(bottom)
    _status = UI.label("", 15, UI.MUTED)
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    bottom.add_child(_status)
    _leave_btn = UI.pill_button("방으로 나가기", UI.INK)
    _leave_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _leave_btn.pressed.connect(func(): game.leave_to_menu())
    bottom.add_child(_leave_btn)
    _ready_btn = UI.cta_button("다음 라운드 레디")
    _ready_btn.custom_minimum_size = Vector2(230, 58)
    _ready_btn.add_theme_font_size_override("font_size", 22)
    _ready_btn.pressed.connect(_on_ready_pressed)
    bottom.add_child(_ready_btn)


func _column(parent: Control, heading: String) -> VBoxContainer:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", UI.box(UI.SOFT, 16, 14))
    p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(p)
    var v := UI.vbox(4)
    p.add_child(v)
    v.add_child(UI.heading(heading, 18, UI.MUTED))
    var list := UI.vbox(2)
    v.add_child(list)
    return list


func _process(_delta: float) -> void:
    visible = game != null and game.is_ended() and game.is_online_match()
    if not visible:
        return
    var s: Dictionary = game.series()
    var vp := get_viewport_rect().size
    size = get_minimum_size()
    position = Vector2((vp.x - size.x) * 0.5, maxf(vp.y - size.y - 24.0, vp.y * 0.36))
    if s.is_empty() or int(s.get("last", {}).get("round", -1)) != int(s.get("round", 0)):
        _title.text = "결과 집계 중…"
        _sub.text = ""
        _status.text = ""
        _ready_btn.visible = false
        _leave_btn.text = "방으로 나가기"
        return
    var phase := String(s.phase)
    var final := phase == "final"
    var key := "%s|%d|%d" % [phase, int(s.round), (s.get("standings", []) as Array).size()]
    if key != _shown_key:
        _shown_key = key
        _fill(s)
    # 아래 줄: 레디 현황·남은 시간
    if final:
        var w := PackedStringArray()
        for e in s.get("standings", []):
            if int(e.rank) == 1 and int(e.points) > 0:
                w.append(String(e.name))
        _status.text = "최종 우승: %s" % (", ".join(w) if not w.is_empty() else "없음")
        _ready_btn.text = "방으로 돌아가기"
        _ready_btn.visible = true
        _leave_btn.visible = false
    else:
        var ready_ids: Array = s.get("ready", [])
        var parts: Array = s.get("participants", [])
        var left := maxi(0, int(ceil(float(s.get("next_at", 0.0)) - Net.server_now())))
        var nxt := int(s.round)            # 다음 라운드 index (0부터)
        var rg: Array = Net.room.get("round_games", [])
        var next_name := Series.choice_name(String(rg[nxt])) if nxt < rg.size() else ""
        _status.text = "다음: %d라운드 %s  ·  레디 %d/%d  ·  %d초 뒤 자동 시작" % [nxt + 1, next_name, ready_ids.size(), parts.size(), left]
        var me_ready := ready_ids.has(Net.my_id)
        _ready_btn.text = "레디 취소" if me_ready else "다음 라운드 레디"
        _ready_btn.visible = parts.has(Net.my_id)
        _leave_btn.visible = true


func _fill(s: Dictionary) -> void:
    var final := String(s.phase) == "final"
    _title.text = "최종 결과" if final else "라운드 %d / %d 결과" % [int(s.round), int(s.total)]
    var games: Array = s.get("games", [])
    var names := PackedStringArray()
    for g in games:
        names.append(Series.choice_name(String(g)))
    _sub.text = " → ".join(names)
    for c in _round_list.get_children():
        c.queue_free()
    var rows: Array = s.get("last", {}).get("rows", [])
    for i in mini(rows.size(), 8):
        var row: Dictionary = rows[i]
        var who := String(row.names) if String(row.team) == "" else "%s (%s)" % [row.team, row.names]
        _round_list.add_child(_row("%d등" % int(row.rank), who, "+%d" % int(row.points) if int(row.points) > 0 else "", false))
    var me_key := "p:%d" % Net.my_id
    var st: Array = s.get("standings", [])
    for c in _total_list.get_children():
        c.queue_free()
    var shown_me := false
    for i in st.size():
        var e: Dictionary = st[i]
        var mine := String(e.key) == me_key
        if i < 7 or (mine and not shown_me):
            _total_list.add_child(_row("%d위" % int(e.rank), String(e.name), "%d점" % int(e.points), mine))
            shown_me = shown_me or mine


func _row(a: String, b: String, c: String, mine: bool) -> Control:
    var h := UI.hbox(8)
    var l1 := UI.label(a, 15, UI.MUTED)
    l1.custom_minimum_size.x = 40
    h.add_child(l1)
    var l2 := UI.label(b, 16, UI.CTA if mine else UI.INK)
    l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l2.clip_text = true
    l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    h.add_child(l2)
    h.add_child(UI.label(c, 16, UI.INK))
    return h


func _on_ready_pressed() -> void:
    var s: Dictionary = game.series()
    if String(s.get("phase", "")) == "final":
        game.leave_to_menu()
        return
    var me_ready: bool = (s.get("ready", []) as Array).has(Net.my_id)
    Net.round_ready(not me_ready)
    Sfx.play("ready_off" if me_ready else "ready_on")
