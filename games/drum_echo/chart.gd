extends RefCounted
## 뒷북의 달인 — 곡 진행표·진행자 리듬·박자 판정 (서버·클라이언트·오프라인 공용, 화면 없음)
##
## 시간 단위: 곡 시작(t0)부터의 초. 120 BPM, 4/4, 한 박 = 0.5초, 한 마디 = 2초
## 한 차례(turn) = [쉼 2박] 진행자 선창 N마디 [텀] 모두 따라 치기 N마디
##   텀(선창과 따라 치기 사이): 곡이 진행될수록 짧아진다 (4박 → 0박, 마지막엔 선창이 끝나자마자 바로)
## 진행자 리듬: 반주에 맞는 리듬 모음(RHYTHMS)에서 고른다. 진행할수록 어려운 리듬(8분 → 16분·당김음·피버)
## 노트: [시각 ms, 북, 끝 ms]  시각 = 선창 시작부터 ms, 북 0 = 둥(왼쪽) 1 = 딱(오른쪽), 끝 = -1 이면 한 번 치기, 아니면 피버(누르고 있다가 그 시각에 뗌)

const BPM := 120.0
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0
const STEP := BEAT / 4.0            ## 16분음표 (리듬 모음의 칸)
const INTRO_BARS := 2               ## 시작 전 반주만
const OUTRO_BARS := 1

const CALL_GAP := 2                 ## 선창 앞 쉼 (박)
const RESP_GAP_START := 4           ## 선창 → 따라 치기 텀 (박): 처음 4박 → 마지막 0박
const RESP_GAP_END := 0

## 판정 (초): 따라 치기
const PERFECT := 0.045
const GOOD := 0.09
const BAD := 0.14
const MIN_NOTE_GAP := 0.09
## 피버: 이만큼(초) 이상 누르고 있다 떼면 피버
const FEVER_HOLD_MIN := 0.3

const POINTS := {"perfect": 100, "good": 60, "bad": 20, "miss": 0, "extra": -10}
const JUDGE_NAMES := {"perfect": "PERFECT", "good": "GOOD", "bad": "BAD", "miss": "MISS", "extra": "헛침"}

## 차례: [마디 수, 차례 수] — 1마디 6번 → 2마디 6번 (약 1분)
const STAGES := [[1, 6], [2, 6]]

## 진행자 리듬 모음 (한 마디 = 16칸, 칸 = 16분음표). [칸, 북(0 둥 1 딱), 피버 길이(칸, 0 = 한 번 치기)]
##   쉬움: 4분·8분음표 위주 / 보통: 8분 당김음·3-3-2 / 어려움: 16분음표·피버 섞기
const RHYTHMS := [
    [   # 0 쉬움
        [[0, 0, 0], [4, 0, 0], [8, 0, 0], [12, 1, 0]],                 # 둥 둥 둥 딱
        [[0, 0, 0], [4, 1, 0], [8, 0, 0], [12, 1, 0]],                 # 둥 딱 둥 딱
        [[0, 0, 0], [8, 0, 0], [12, 1, 0], [14, 1, 0]],                # 둥 . 둥 딱딱
        [[0, 0, 0], [6, 0, 0], [8, 1, 0], [12, 0, 0]],                 # 둥 . 둥딱 . 둥
        [[0, 0, 4], [8, 0, 0], [12, 1, 0]],                            # 둥~ 둥 딱
        [[0, 1, 0], [2, 1, 0], [4, 0, 0], [8, 0, 0], [12, 0, 0]],      # 딱딱 둥 둥 둥
    ],
    [   # 1 보통
        [[0, 0, 0], [4, 0, 0], [6, 1, 0], [8, 0, 0], [12, 1, 0]],
        [[0, 0, 0], [2, 1, 0], [4, 0, 0], [8, 0, 0], [10, 1, 0], [12, 0, 0]],
        [[0, 0, 0], [6, 0, 0], [12, 0, 0], [14, 1, 0]],                # 3-3-2 (둥 . . 둥 . . 둥 딱)
        [[0, 0, 0], [3, 0, 0], [6, 1, 0], [8, 0, 0], [12, 1, 0]],
        [[0, 0, 8], [8, 1, 0], [10, 1, 0], [12, 0, 0]],                # 둥~~ 딱딱 둥
        [[0, 1, 0], [4, 0, 0], [6, 0, 0], [8, 1, 0], [12, 0, 0]],
        [[0, 0, 0], [4, 1, 0], [6, 1, 0], [10, 0, 0], [12, 0, 0]],
    ],
    [   # 2 어려움
        [[0, 0, 0], [2, 0, 0], [3, 1, 0], [6, 0, 0], [8, 0, 0], [11, 1, 0], [12, 0, 0], [14, 1, 0]],
        [[0, 0, 0], [3, 0, 0], [6, 0, 0], [8, 1, 0], [10, 1, 0], [11, 1, 0], [12, 0, 0]],
        [[0, 0, 0], [4, 1, 0], [5, 1, 0], [8, 0, 0], [10, 0, 0], [12, 1, 0], [13, 1, 0], [14, 0, 0]],
        [[0, 0, 4], [6, 1, 0], [7, 1, 0], [8, 0, 0], [12, 1, 3]],
        [[0, 0, 0], [1, 0, 0], [4, 1, 0], [8, 0, 0], [9, 0, 0], [12, 1, 0], [14, 0, 0]],
        [[0, 1, 0], [2, 0, 0], [4, 1, 0], [6, 0, 0], [7, 0, 0], [10, 1, 0], [12, 0, 3]],
    ],
]
## 2마디 선창의 둘째 마디 끝맺음 (대답처럼): 박 위에서 둥으로 마무리
const CADENCES := [
    [[0, 0, 0], [4, 1, 0], [8, 0, 0]],
    [[0, 0, 0], [2, 1, 0], [4, 0, 0], [8, 0, 4]],
    [[0, 1, 0], [2, 1, 0], [4, 0, 0], [6, 0, 0], [8, 0, 0]],
    [[0, 0, 0], [4, 0, 0], [6, 1, 0], [8, 0, 0], [12, 0, 0]],
]


## 진행표: [{bars, gap, rgap, attack_t, response_t}] — attack_t = 선창 시작, response_t = 따라 치기 시작
static func build_turns(_teams: int = 0) -> Array:
    var plan := []
    for st in STAGES:
        for k in int(st[1]):
            plan.append(int(st[0]))
    var turns := []
    var t := INTRO_BARS * BAR
    for k in plan.size():
        var n: int = plan[k]
        var u := float(k) / float(maxi(plan.size() - 1, 1))
        var rgap := int(round(lerpf(RESP_GAP_START, RESP_GAP_END, u)))
        var a := t + CALL_GAP * BEAT
        var r := a + n * BAR + rgap * BEAT
        turns.append({"attack_team": -1, "bars": n, "gap": CALL_GAP, "rgap": rgap, "attack_t": a, "response_t": r, "host": true})
        t = r + n * BAR
    return turns


static func end_time(turns: Array) -> float:
    if turns.is_empty():
        return (INTRO_BARS + OUTRO_BARS) * BAR
    var last: Dictionary = turns.back()
    return response_end(last) + OUTRO_BARS * BAR


static func attack_end(turn: Dictionary) -> float:
    return float(turn.attack_t) + int(turn.bars) * BAR


static func response_end(turn: Dictionary) -> float:
    return float(turn.response_t) + int(turn.bars) * BAR


## 쉼 시작 (선창 앞)
static func ready_t(turn: Dictionary) -> float:
    return float(turn.attack_t) - int(turn.gap) * BEAT


## 노트 시각 (선창이면 선창 시작 기준, 따라 치기면 따라 치기 시작 기준)
static func note_time(turn: Dictionary, n: Array, response: bool) -> float:
    return float(turn.response_t if response else turn.attack_t) + int(n[0]) / 1000.0


static func note_end_time(turn: Dictionary, n: Array, response: bool) -> float:
    return float(turn.response_t if response else turn.attack_t) + int(n[2]) / 1000.0


static func is_fever(n: Array) -> bool:
    return n.size() > 2 and int(n[2]) >= 0


## 판정할 노트 수 (피버 = 누름·뗌 2개)
static func units(notes: Array) -> int:
    var u := 0
    for n in notes:
        u += 2 if is_fever(n) else 1
    return u


## 진행자 리듬: difficulty(0~1)에 맞는 난이도 묶음에서 고른다. 2마디면 둘째 마디는 끝맺음 리듬
static func host_pattern(bars: int, difficulty: float, seed_value: int) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    # 난이도: 앞쪽은 쉬움, 중간은 쉬움·보통, 뒤쪽은 보통·어려움
    var level := 0
    if difficulty >= 0.75:
        level = 2 if rng.randf() < 0.6 else 1
    elif difficulty >= 0.4:
        level = 1 if rng.randf() < 0.7 else 0
    elif difficulty >= 0.15:
        level = 1 if rng.randf() < 0.3 else 0
    var notes := []
    for b in bars:
        var bar_rhythm: Array
        if bars >= 2 and b == bars - 1 and rng.randf() < 0.6:
            bar_rhythm = CADENCES[rng.randi_range(0, CADENCES.size() - 1)]
        else:
            var pool: Array = RHYTHMS[level]
            bar_rhythm = pool[rng.randi_range(0, pool.size() - 1)]
        var base_ms := int(b * BAR * 1000.0)
        for st in bar_rhythm:
            var ms := base_ms + int(round(int(st[0]) * STEP * 1000.0))
            var e := -1 if int(st[2]) <= 0 else ms + int(round(int(st[2]) * STEP * 1000.0))
            notes.append([ms, int(st[1]), e])
    return notes


## 따라 치기 판정 (누름): 아직 안 맞힌 노트(한 번 치기·피버 시작) 중 같은 북·가장 가까운 것 → [노트 번호, 판정, 어긋난 초(+ = 늦음)]
## notes: [[ms, lane, end], ...], taken: 맞힌 노트 번호 Dictionary (피버 끝은 -(번호+1))
static func judge_response(turn: Dictionary, notes: Array, taken: Dictionary, lane: int, t: float) -> Array:
    var best := -1
    var best_off := 1e9
    for i in notes.size():
        if taken.has(i) or int(notes[i][1]) != lane:
            continue
        var off := t - note_time(turn, notes[i], true)
        if absf(off) < absf(best_off):
            best_off = off
            best = i
    if best < 0 or absf(best_off) > BAD:
        return [-1, "extra", 0.0]
    return [best, timing_judge(absf(best_off)), best_off]


static func timing_judge(off: float) -> String:
    return "perfect" if off <= PERFECT else ("good" if off <= GOOD else ("bad" if off <= BAD else "miss"))


## 따라 치기 판정 (피버 뗌): 끝 시각과 비교. 너무 일찍·늦게 떼면 MISS
static func judge_release(turn: Dictionary, note: Array, t: float) -> String:
    return timing_judge(absf(t - note_end_time(turn, note, true)))


## 봇이 따라 치기: 노트마다 판정을 무작위로 (실력 skill 0~1). count = 노트 수 (피버 = 2)
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
