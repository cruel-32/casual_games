extends Node
## 효과음·배경음악 (오토로드 "Sfx")
##   Sfx.play("click")                    화면 전체에 들리는 소리 (UI, 내 캐릭터)
##   Sfx.play_at("hit", pos, node)        3D 위치에서 나는 소리 (멀면 작게). node: 같은 3D 월드에 있는 아무 노드
##   Sfx.bgm("menu") / Sfx.bgm("match")   배경음악 교체 (크로스페이드, 무한 반복)
##   Sfx.charge(ratio) / Sfx.charge_stop() 내 캐릭터 차징음 (비율에 따라 음이 올라감)
## 소리 파일: audio/sfx/*.wav, audio/bgm/*.ogg (tools/audio/gen_*.py 로 생성)
## 서버(헤드리스)에서는 아무것도 하지 않는다.

const SFX_DIR := "res://audio/sfx/"
const BGM_DIR := "res://audio/bgm/"
const SETTINGS_PATH := "user://settings.cfg"

## 소리별 기본 음량(dB)과 음높이 흔들림 — 자주 나는 소리는 작게, 매번 똑같지 않게 살짝 흔든다
const MIX := {
    "click": [-6.0, 0.06], "ready_on": [-4.0, 0.0], "ready_off": [-6.0, 0.0], "join": [-5.0, 0.0],
    "leave": [-7.0, 0.0], "chat": [-8.0, 0.05], "notify": [-6.0, 0.0], "error": [-6.0, 0.0],
    "count_tick": [-3.0, 0.0], "count_go": [-2.0, 0.0], "win": [-2.0, 0.0], "lose": [-3.0, 0.0],
    "whistle": [-6.0, 0.0], "jump": [-9.0, 0.06], "land": [-12.0, 0.1], "charge_full": [-4.0, 0.0],
    "push": [-6.0, 0.08], "dash": [-4.0, 0.06], "hit": [-2.0, 0.08], "swat": [-2.0, 0.06], "wall": [-4.0, 0.05],
    "bump": [-10.0, 0.12], "helmet_break": [-3.0, 0.05], "die": [-2.0, 0.0], "dizzy": [-9.0, 0.0],
    "rock_fall": [-16.0, 0.12], "rock_land": [-7.0, 0.15], "rock_break": [-5.0, 0.1], "item_spawn": [-10.0, 0.1],
    "pickup": [-4.0, 0.03], "pickup_helmet": [-4.0, 0.0], "pickup_charge": [-4.0, 0.0],
    "pickup_cooldown": [-4.0, 0.0], "pickup_glove": [-4.0, 0.0], "shield_on": [-4.0, 0.0],
    "shield_off": [-6.0, 0.0], "ready_ping": [-12.0, 0.0], "wind": [-10.0, 0.08],
    # 크레이지 봄버맨 (tools/audio/gen_bomber.py)
    "bomb_place": [-8.0, 0.06], "boom": [-3.0, 0.08], "kick": [-6.0, 0.06], "crate_break": [-8.0, 0.1], "ghost_throw": [-8.0, 0.05],
    # 캐릭터 목소리 (tools/audio/gen_voice.py) — 음높이는 캐릭터마다 다르게 Fighter.voice_pitch()
    "voice_push": [-5.0, 0.04], "voice_hit": [-3.0, 0.04], "voice_die": [-2.0, 0.03], "voice_jump": [-9.0, 0.05],
    "voice_pickup": [-5.0, 0.04], "voice_win": [-4.0, 0.03], "voice_laugh": [-5.0, 0.04], "voice_surprise": [-4.0, 0.04],
}
const BGM_DB := {"menu": -11.0, "match": -13.0}

var enabled := true          # 끄면 효과음·배경음악 모두 음소거
var _on := false             # 서버·헤드리스면 false
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _bgm_old: AudioStreamPlayer
var _bgm_name := ""
var _charge: AudioStreamPlayer
var _last_play := {}         # 같은 소리가 한 프레임에 여러 번 겹치지 않게


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _on = DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--server")
    if OS.get_environment("SPW_SFX_TEST") != "":
        _on = true          # 개발용: 헤드리스 테스트에서도 소리 코드를 실행
    if not _on:
        return
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) == OK:
        enabled = bool(cfg.get_value("client", "sound", true))
    # 버스는 default_bus_layout.tres 에 미리 정의 (웹은 실행 중에 만든 버스로 소리를 보내면 안 들림)
    for bus in ["Music", "Sfx"]:
        if AudioServer.get_bus_index(bus) == -1:
            AudioServer.add_bus()
            var i := AudioServer.bus_count - 1
            AudioServer.set_bus_name(i, bus)
            AudioServer.set_bus_send(i, "Master")
    _apply_mute()
    for i in 12:
        var p := AudioStreamPlayer.new()
        p.bus = "Sfx"
        add_child(p)
        _pool.append(p)
    _charge = AudioStreamPlayer.new()
    _charge.bus = "Sfx"
    var loop := _stream("charge_loop") as AudioStreamWAV
    if loop:
        loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
        loop.loop_begin = 0
        loop.loop_end = int(loop.get_length() * loop.mix_rate)
    _charge.stream = loop
    _charge.volume_db = -14.0
    add_child(_charge)
    # 모든 버튼에 클릭음 (새로 생기는 버튼까지 자동)
    get_tree().node_added.connect(_on_node_added)


func set_enabled(on: bool) -> void:
    enabled = on
    if _on:
        _apply_mute()
    var cfg := ConfigFile.new()
    cfg.load(SETTINGS_PATH)
    cfg.set_value("client", "sound", on)
    cfg.save(SETTINGS_PATH)


func _apply_mute() -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not enabled)


func _stream(sound: String) -> AudioStream:
    if _streams.has(sound):
        return _streams[sound]
    var path := SFX_DIR + sound + ".wav"
    var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
    if s == null:
        push_warning("[Sfx] 소리 없음: " + sound)
    _streams[sound] = s
    return s


func _recent(sound: String) -> bool:
    var now := Time.get_ticks_msec()
    if now - int(_last_play.get(sound, -1000)) < 35:
        return true
    _last_play[sound] = now
    return false


## 위치 없는 소리 (UI, 내 캐릭터 행동, 안내음)
func play(sound: String, db: float = 0.0, pitch: float = 1.0) -> void:
    if not _on or _recent(sound):
        return
    var s := _stream(sound)
    if s == null:
        return
    var p: AudioStreamPlayer = null
    for c in _pool:
        if not c.playing:
            p = c
            break
    if p == null:
        p = _pool[0]
        _pool.push_back(_pool.pop_front())
    var mix := _mix(sound)
    p.stream = s
    p.volume_db = mix[0] + db
    p.pitch_scale = pitch * (1.0 + randf_range(-mix[1], mix[1]))
    p.play()


## [음량 dB, 음높이 흔들림]. 목소리는 파일마다가 아니라 종류마다 (voice_hit_2_3 → voice_hit)
func _mix(sound: String) -> Array:
    if MIX.has(sound):
        return MIX[sound]
    if sound.begins_with("voice_"):
        return MIX.get("voice_" + sound.get_slice("_", 1), [-4.0, 0.03])
    return [0.0, 0.0]


## 3D 위치 소리. near 가 같은 월드의 노드여야 한다 (그 노드의 Viewport 에 붙인다)
func play_at(sound: String, pos: Vector3, near: Node, db: float = 0.0, pitch: float = 1.0) -> void:
    if not _on or near == null or not near.is_inside_tree():
        return
    var s := _stream(sound)
    if s == null:
        return
    var mix := _mix(sound)
    var p := AudioStreamPlayer3D.new()
    p.bus = "Sfx"
    p.stream = s
    p.volume_db = mix[0] + db + 4.0
    p.pitch_scale = pitch * (1.0 + randf_range(-mix[1], mix[1]))
    p.unit_size = 9.0               # 이 거리 안에서는 거의 원래 크기
    p.max_distance = 70.0
    p.attenuation_filter_cutoff_hz = 9000.0
    p.panning_strength = 0.6
    p.top_level = true
    p.finished.connect(p.queue_free)
    near.get_viewport().add_child(p)
    p.global_position = pos
    p.play()


## 배경음악 교체 (같은 곡이면 그대로). name = "" 이면 끄기
func bgm(track: String, fade: float = 0.8) -> void:
    if not _on or track == _bgm_name:
        return
    _bgm_name = track
    if _bgm_old:
        _bgm_old.queue_free()
    _bgm_old = _bgm
    if _bgm_old:
        var tw := create_tween()
        tw.tween_property(_bgm_old, "volume_db", -60.0, fade)
        tw.tween_callback(_bgm_old.queue_free)
        _bgm_old = null
    _bgm = null
    if track == "":
        return
    var path := BGM_DIR + track + ".ogg"
    if not ResourceLoader.exists(path):
        push_warning("[Sfx] 배경음악 없음: " + track)
        return
    var st: AudioStream = load(path)
    if st is AudioStreamOggVorbis:
        (st as AudioStreamOggVorbis).loop = true
    _bgm = AudioStreamPlayer.new()
    _bgm.bus = "Music"
    _bgm.stream = st
    var target: float = BGM_DB.get(track, -12.0)
    _bgm.volume_db = -60.0
    add_child(_bgm)
    _bgm.play()
    create_tween().tween_property(_bgm, "volume_db", target, fade)


## 배경음악을 잠깐 작게 (승리·패배 효과음이 잘 들리게)
func duck(seconds: float = 2.5) -> void:
    if not _on or _bgm == null:
        return
    var target: float = BGM_DB.get(_bgm_name, -12.0)
    var tw := create_tween()
    tw.tween_property(_bgm, "volume_db", target - 14.0, 0.15)
    tw.tween_interval(seconds)
    tw.tween_property(_bgm, "volume_db", target, 1.0)


## 내 캐릭터 차징음: ratio 0~1 에 따라 음이 올라간다
func charge(ratio: float) -> void:
    if not _on:
        return
    _charge.pitch_scale = 0.8 + ratio * 0.9
    if not _charge.playing:
        _charge.play()


func charge_stop() -> void:
    if _on and _charge.playing:
        _charge.stop()


func _on_node_added(n: Node) -> void:
    if n is BaseButton:
        var b := n as BaseButton
        b.pressed.connect(_on_button_pressed.bind(b))


## 버튼 딸깍. 메타 no_click 이 있는 버튼은 소리 없음 (리듬 게임 북 버튼 등)
func _on_button_pressed(b: BaseButton) -> void:
    if not b.has_meta(&"no_click"):
        play("click")
