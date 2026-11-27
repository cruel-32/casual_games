extends RefCounted
## 뒷북의 달인 — 곡 진행표·진행자 리듬·박자 판정 (서버·클라이언트·오프라인 공용, 화면 없음)
##
## 곡: tools/music/song_*.py 로 만든 완성곡. 반주(backing.ogg)에 북 파트까지 들어 있고(진행자가 치는 모습), 그 북 파트가 곧 노트(song.gd)
##   선창·따라 치기는 없다: 진행자가 치는 바로 그 자리에서 모두가 함께 친다
## 시간 단위: 곡 시작(반주 0초)부터의 초. 4/4. BPM 은 곡마다 다름 (차례마다 beat·bar 초를 실어 둔다)
## 노트: [시각 ms, 북, 끝 ms]  시각 = 차례(북 마디 묶음) 시작부터 ms, 북 0 = 둥(왼쪽) 1 = 딱(오른쪽), 끝 = -1 이면 한 번 치기, 아니면 피버

## 곡 목록. 곡마다 반주와 노트 (tools/music/song_<id>.py 로 만듦). 경기마다 서버가 하나를 골라 "start" 로 알린다
const SONGS := {
    "funk": {"data": preload("res://audio/drum/songs/funk/song.gd"), "backing": preload("res://audio/drum/songs/funk/backing.ogg")},
    "rock": {"data": preload("res://audio/drum/songs/rock/song.gd"), "backing": preload("res://audio/drum/songs/rock/backing.ogg")},
    "hiphop": {"data": preload("res://audio/drum/songs/hiphop/song.gd"), "backing": preload("res://audio/drum/songs/hiphop/backing.ogg")},
    "disco": {"data": preload("res://audio/drum/songs/disco/song.gd"), "backing": preload("res://audio/drum/songs/disco/backing.ogg")},
    "gugak": {"data": preload("res://audio/drum/songs/gugak/song.gd"), "backing": preload("res://audio/drum/songs/gugak/backing.ogg")},
    "chip": {"data": preload("res://audio/drum/songs/chip/song.gd"), "backing": preload("res://audio/drum/songs/chip/backing.ogg")},
    "lofi": {"data": preload("res://audio/drum/songs/lofi/song.gd"), "backing": preload("res://audio/drum/songs/lofi/backing.ogg")},
    "reggae": {"data": preload("res://audio/drum/songs/reggae/song.gd"), "backing": preload("res://audio/drum/songs/reggae/backing.ogg")},
    "march": {"data": preload("res://audio/drum/songs/march/song.gd"), "backing": preload("res://audio/drum/songs/march/backing.ogg")},
    "trot": {"data": preload("res://audio/drum/songs/trot/song.gd"), "backing": preload("res://audio/drum/songs/trot/backing.ogg")},
    "bossa": {"data": preload("res://audio/drum/songs/bossa/song.gd"), "backing": preload("res://audio/drum/songs/bossa/backing.ogg")},
    "house": {"data": preload("res://audio/drum/songs/house/song.gd"), "backing": preload("res://audio/drum/songs/house/backing.ogg")},
    "kpop": {"data": preload("res://audio/drum/songs/kpop/song.gd"), "backing": preload("res://audio/drum/songs/kpop/backing.ogg")},
    "salsa": {"data": preload("res://audio/drum/songs/salsa/song.gd"), "backing": preload("res://audio/drum/songs/salsa/backing.ogg")},
    "afro": {"data": preload("res://audio/drum/songs/afro/song.gd"), "backing": preload("res://audio/drum/songs/afro/backing.ogg")},
    "country": {"data": preload("res://audio/drum/songs/country/song.gd"), "backing": preload("res://audio/drum/songs/country/backing.ogg")},
    "metal": {"data": preload("res://audio/drum/songs/metal/song.gd"), "backing": preload("res://audio/drum/songs/metal/backing.ogg")},
    "dnb": {"data": preload("res://audio/drum/songs/dnb/song.gd"), "backing": preload("res://audio/drum/songs/dnb/backing.ogg")},
}
const DEFAULT_SONG := "funk"
const TAIL := 1.5                   ## 곡이 끝나고 결과까지

## 판정 (초)
const PERFECT := 0.045
const GOOD := 0.09
const BAD := 0.14
const MIN_NOTE_GAP := 0.09
## 피버: 이만큼(초) 이상 누르고 있다 떼면 피버
const FEVER_HOLD_MIN := 0.3

const POINTS := {"perfect": 100, "good": 60, "bad": 20, "miss": 0, "extra": -10}
const JUDGE_NAMES := {"perfect": "PERFECT", "good": "GOOD", "bad": "BAD", "miss": "MISS", "extra": "헛침"}

static func song_data(id: String = DEFAULT_SONG) -> Dictionary:
    return SONGS.get(id, SONGS[DEFAULT_SONG]).data.DATA


static func song_backing(id: String = DEFAULT_SONG) -> AudioStream:
    return SONGS.get(id, SONGS[DEFAULT_SONG]).backing


static func song_title(id: String = DEFAULT_SONG) -> String:
    return String(song_data(id).title)


## 한 박 (초)
static func beat_of(id: String = DEFAULT_SONG) -> float:
    return 60.0 / float(song_data(id).bpm)


## 난이도 1(쉬움) ~ 5(어려움)
static func song_level(id: String = DEFAULT_SONG) -> int:
    return int(song_data(id).get("level", 3))


const LEVEL_NAMES := ["", "쉬움", "보통", "조금 어려움", "어려움", "매우 어려움"]


## "난이도 4/5 어려움" (별 글자는 작게 보면 꽉 찬 별·빈 별 구분이 어려워 글자로)
static func level_text(id: String = DEFAULT_SONG) -> String:
    var lv := clampi(song_level(id), 1, 5)
    return "난이도 %d/5 %s" % [lv, LEVEL_NAMES[lv]]


## 곡 고르기: 최근에 나온 곡(exclude)은 빼고 무작위
static func pick_song(rng: RandomNumberGenerator, exclude: Array = []) -> String:
    var ids: Array = SONGS.keys()
    var fresh := ids.filter(func(x): return not exclude.has(x))
    if fresh.is_empty():
        fresh = ids
    return String(fresh[rng.randi_range(0, fresh.size() - 1)])


## 진행표: 곡 노트에서 [{bars, gap, start, notes, beat, bar}] — start = 차례(북 마디 최대 4개) 시작 초
##   gap = 앞 차례가 끝난 뒤 '준비' 안내를 띄울 박 수 (최대 4박, 이어지면 0)
static func build_turns(_teams: int = 0, id: String = DEFAULT_SONG) -> Array:
    var data := song_data(id)
    var beat := 60.0 / float(data.bpm)
    var bar := beat * 4.0
    var turns := []
    var prev_end := 0.0
    for td in data.turns:
        var a := float(td.start)
        var n := int(td.bars)
        var notes := []
        for nn in td.notes:
            notes.append([int(nn[0]), int(nn[1]), int(nn[2])])
        turns.append({"bars": n, "gap": clampi(int(round((a - prev_end) / beat)), 0, 4), "start": a, "notes": notes,
                "beat": beat, "bar": bar})
        prev_end = a + n * bar
    return turns


static func end_time(_turns: Array = [], id: String = DEFAULT_SONG) -> float:
    return float(song_data(id).length) + TAIL


static func turn_end(turn: Dictionary) -> float:
    return float(turn.start) + int(turn.bars) * float(turn.bar)


## 준비 안내 시작 (차례 앞)
static func ready_t(turn: Dictionary) -> float:
    return float(turn.start) - int(turn.gap) * float(turn.beat)


## 노트 시각 (진행자·플레이어 같은 자리)
static func note_time(turn: Dictionary, n: Array) -> float:
    return float(turn.start) + int(n[0]) / 1000.0


static func note_end_time(turn: Dictionary, n: Array) -> float:
    return float(turn.start) + int(n[2]) / 1000.0


static func is_fever(n: Array) -> bool:
    return n.size() > 2 and int(n[2]) >= 0


## 판정할 노트 수 (피버 = 누름·뗌 2개)
static func units(notes: Array) -> int:
    var u := 0
    for n in notes:
        u += 2 if is_fever(n) else 1
    return u


## 판정 (누름): 아직 안 맞힌 노트(한 번 치기·피버 시작) 중 같은 북·가장 가까운 것 → [노트 번호, 판정, 어긋난 초(+ = 늦음)]
## notes: [[ms, lane, end], ...], taken: 맞힌 노트 번호 Dictionary (피버 끝은 -(번호+1))
static func judge_response(turn: Dictionary, notes: Array, taken: Dictionary, lane: int, t: float) -> Array:
    var best := -1
    var best_off := 1e9
    for i in notes.size():
        if taken.has(i) or int(notes[i][1]) != lane:
            continue
        var off := t - note_time(turn, notes[i])
        if absf(off) < absf(best_off):
            best_off = off
            best = i
    if best < 0 or absf(best_off) > BAD:
        return [-1, "extra", 0.0]
    return [best, timing_judge(absf(best_off)), best_off]


static func timing_judge(off: float) -> String:
    return "perfect" if off <= PERFECT else ("good" if off <= GOOD else ("bad" if off <= BAD else "miss"))


## 판정 (피버 뗌): 끝 시각과 비교. 너무 일찍·늦게 떼면 MISS
static func judge_release(turn: Dictionary, note: Array, t: float) -> String:
    return timing_judge(absf(t - note_end_time(turn, note)))


## 봇: 노트마다 판정을 무작위로 (실력 skill 0~1). count = 노트 수 (피버 = 2)
static func bot_judgements(count: int, skill: float, seed_value: int) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var out := []
    for i in count:
        var r := rng.randf()
        var p := 0.25 + skill * 0.35
        var g := p + 0.3
        var b := g + 0.15
        out.append("perfect" if r < p else ("good" if r < g else ("bad" if r < b else "miss")))
    return out
