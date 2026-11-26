extends RefCounted
## 뒷북의 달인 — 곡 진행표·박자 판정 (서버·클라이언트·오프라인 공용, 화면 없음)
##
## 시간 단위: 곡 시작(t0)부터의 초. 120 BPM, 4/4, 한 박 = 0.5초, 한 마디 = 2초
## 한 차례(turn) = [쉼] 공격 N마디 [쉼] 따라 치기 N마디
##   쉼(텀): 컴퓨터가 정해 준 둥·딱 개수를 보고 준비하는 시간. 곡이 진행될수록 짧아진다 (8박 → 4박)
## 박자는 공격자 마음대로 (칸에 맞추지 않음). 반주 박에 맞으면 공격 점수 전부, 엇박(반 박)이면 절반, 그 밖은 0
## 노트: [시각 ms, 북, 끝 ms]  시각 = 공격 시작부터 ms, 북 0 = 둥(왼쪽) 1 = 딱(오른쪽), 끝 = -1 이면 한 번 치기, 아니면 피버(누르고 있다가 그 시각에 뗌)
## 개수 지정(spec): {"l": 둥 개수, "r": 딱 개수} — 피버 하나는 그 북 2개(누름·뗌)로 센다

const BPM := 120.0
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0
const SLOTS_PER_BAR := 8
const SLOT := BAR / SLOTS_PER_BAR
const INTRO_BARS := 2               ## 시작 전 반주만 (카운트)
const OUTRO_BARS := 1

## 쉼(박 수): 첫 차례 GAP_START → 마지막 차례 GAP_END 로 점점 짧아짐
const GAP_START := 8
const GAP_END := 4

## 판정 (초): 따라 치기
const PERFECT := 0.045
const GOOD := 0.09
const BAD := 0.14
## 공격: 반주 박(또는 엇박)에서 얼마나 가까운지로 점수
const ATTACK_PERFECT := 0.04
const ATTACK_GOOD := 0.075
const ATTACK_BAD := 0.11
const MIN_NOTE_GAP := 0.09          ## 같은 북을 이보다 빨리 연달아 치면 한 번으로 (따라 치기에서 구분이 안 되므로)
const MAX_NOTES_PER_BAR := 10

## 피버: 이만큼(초) 이상 누르고 있다 떼면 피버
const FEVER_HOLD_MIN := 0.3

const POINTS := {"perfect": 100, "good": 60, "bad": 20, "miss": 0, "wild": -50, "extra": -10}
## 공격 점수: 반주 박에 맞으면 그대로, 엇박이면 절반, 박도 엇박도 아니면 0 (따라 치기보다 작게)
const ATTACK_POINTS := {"perfect": 50, "good": 30, "bad": 10}
## 지정한 개수보다 많거나 적으면 1개당 감점 (피버 1개 = 2개)
const COUNT_PENALTY := 40
const JUDGE_NAMES := {"perfect": "PERFECT", "good": "GOOD", "bad": "BAD", "miss": "MISS", "extra": "헛침",
        "off_perfect": "엇박 PERFECT", "off_good": "엇박 GOOD", "off_bad": "엇박 BAD", "free": "자유 박자"}

## 곡 길이는 팀 수와 상관없이 거의 같다: 단계별 차례 수 [공격 마디 수, 차례 수]
##   팀마다 똑같이 돌아가며 공격하고, 남는 차례(팀 수로 나누어떨어지지 않는 만큼, 최대 2번)는 진행자가 랜덤 리듬으로 공격
##   예) 2팀: 1마디 ×4(팀 2바퀴) → 2마디 ×3(팀 1바퀴 + 진행자 1) → 4마디 ×2(팀 1바퀴)
##   개인전은 모든 차례를 진행자가 공격
const STAGES := [[1, 4], [2, 3], [4, 2]]
const HOST_MAX_EXTRA := 2


## 진행표: [{attack_team, bars, gap, attack_t, response_t, host}] — attack_team -1 = 진행자 (모두가 따라 침)
##   gap: 공격 앞·따라 치기 앞 쉼(박 수)
static func build_turns(teams: int) -> Array:
    var order_all := []                 # [팀, 마디]
    for st in STAGES:
        var n := int(st[0])
        var count := int(st[1])
        if teams >= 2:
            var rounds := maxi(1, count / teams)
            for r in rounds:
                for t in teams:
                    order_all.append([t, n])
            for k in clampi(count - rounds * teams, 0, HOST_MAX_EXTRA):
                order_all.append([-1, n])
        else:
            for k in count:
                order_all.append([-1, n])
    var turns := []
    var t := INTRO_BARS * BAR
    var total := order_all.size()
    for k in total:
        var team := int(order_all[k][0])
        var n := int(order_all[k][1])
        var gap := gap_beats(k, total)
        var a := t + gap * BEAT
        var r := a + n * BAR + gap * BEAT
        turns.append({"attack_team": team, "bars": n, "gap": gap, "attack_t": a, "response_t": r, "host": team < 0})
        t = r + n * BAR
    return turns


static func gap_beats(k: int, total: int) -> int:
    var u := float(k) / float(maxi(total - 1, 1))
    return int(round(lerpf(GAP_START, GAP_END, u)))


static func end_time(turns: Array) -> float:
    if turns.is_empty():
        return (INTRO_BARS + OUTRO_BARS) * BAR
    var last: Dictionary = turns.back()
    return float(last.response_t) + int(last.bars) * BAR + OUTRO_BARS * BAR


static func attack_end(turn: Dictionary) -> float:
    return float(turn.attack_t) + int(turn.bars) * BAR


static func response_end(turn: Dictionary) -> float:
    return float(turn.response_t) + int(turn.bars) * BAR


## 쉼 시작 (공격 앞)
static func ready_t(turn: Dictionary) -> float:
    return float(turn.attack_t) - int(turn.gap) * BEAT


## 노트 시각 (공격이면 공격 시작 기준, 따라 치기면 따라 치기 시작 기준)
static func note_time(turn: Dictionary, n: Array, response: bool) -> float:
    return float(turn.response_t if response else turn.attack_t) + int(n[0]) / 1000.0


static func note_end_time(turn: Dictionary, n: Array, response: bool) -> float:
    return float(turn.response_t if response else turn.attack_t) + int(n[2]) / 1000.0


static func is_fever(n: Array) -> bool:
    return n.size() > 2 and int(n[2]) >= 0


## 북별 개수 (피버 = 2)
static func count_of(notes: Array) -> Dictionary:
    var c := {"l": 0, "r": 0}
    for n in notes:
        var k := "l" if int(n[1]) == 0 else "r"
        c[k] += 2 if is_fever(n) else 1
    return c


## 판정할 노트 수 (피버 = 2)
static func units(notes: Array) -> int:
    var c := count_of(notes)
    return c.l + c.r


static func spec_units(spec: Dictionary) -> int:
    return int(spec.get("l", 0)) + int(spec.get("r", 0))


## 지정 수와 다른 만큼
static func count_diff(notes: Array, spec: Dictionary) -> int:
    var c := count_of(notes)
    return absi(c.l - int(spec.l)) + absi(c.r - int(spec.r))


static func spec_text(spec: Dictionary) -> String:
    return "둥 %d번 · 딱 %d번" % [int(spec.get("l", 0)), int(spec.get("r", 0))]


## 컴퓨터가 정해 주는 개수: 진행할수록 조금씩 많게 (difficulty 0~1)
static func make_spec(bars: int, difficulty: float, seed_value: int) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var per_bar := 3.0 + difficulty * 1.5
    var total := clampi(int(round(per_bar * bars + rng.randf_range(-0.5, 0.5))), 2, bars * 6)
    var l := clampi(int(round(total * rng.randf_range(0.35, 0.65))), 1, total - 1)
    return {"l": l, "r": total - l}


## 공격 박자 점수: 시각(공격 시작부터 초) → [판정 키, 점수]
##   반주 박에 가까우면 perfect/good/bad 그대로, 엇박(반 박)에 가까우면 off_* 절반, 둘 다 아니면 free 0
static func attack_score(rel: float) -> Array:
    var d_on := absf(rel - round(rel / BEAT) * BEAT)
    var j := _attack_judge(d_on)
    if j != "":
        return [j, int(ATTACK_POINTS[j])]
    var off := rel - BEAT * 0.5
    var d_off := absf(off - round(off / BEAT) * BEAT)
    j = _attack_judge(d_off)
    if j != "":
        return ["off_" + j, int(ATTACK_POINTS[j]) / 2]
    return ["free", 0]


static func _attack_judge(d: float) -> String:
    return "perfect" if d <= ATTACK_PERFECT else ("good" if d <= ATTACK_GOOD else ("bad" if d <= ATTACK_BAD else ""))


## 같은 북에 시각 ms 근처(MIN_NOTE_GAP) 노트가 있나 (피버로 누르고 있는 구간 포함)
static func lane_busy(notes: Array, ms: int, lane: int, end_ms: int = -1, skip: int = -1) -> bool:
    var gap := int(MIN_NOTE_GAP * 1000.0)
    var a := ms
    var b := ms if end_ms < 0 else end_ms
    for i in notes.size():
        if i == skip:
            continue
        var n: Array = notes[i]
        if int(n[1]) != lane:
            continue
        var na := int(n[0])
        var nb := int(n[2]) if is_fever(n) else na
        if a <= nb + gap and b >= na - gap:
            return true
    return false


## 지정 수에 딱 맞게: base 의 노트는 자리를 옮기지 않는다 (넘치면 빼고, 모자라면 빈 박에 채움)
static func fit_pattern(base: Array, bars: int, spec: Dictionary, seed_value: int) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var notes := []
    for n in base:
        notes.append([int(n[0]), int(n[1]), int(n[2]) if n.size() > 2 else -1])
    var total_ms := bars * int(BAR * 1000.0)
    for lane in 2:
        var key := "l" if lane == 0 else "r"
        var want := int(spec[key])
        # 넘침: 한 번 치기를 뒤에서부터 빼고, 그래도 넘치면 피버를 한 번 치기로
        var guard := 0
        while int(count_of(notes)[key]) > want and guard < 100:
            guard += 1
            var idx := -1
            for i in range(notes.size() - 1, -1, -1):
                if int(notes[i][1]) == lane and not is_fever(notes[i]):
                    idx = i
                    break
            if idx >= 0:
                notes.remove_at(idx)
                continue
            for i in range(notes.size() - 1, -1, -1):
                if int(notes[i][1]) == lane and is_fever(notes[i]):
                    notes[i][2] = -1
                    break
        # 모자람: 빈 정박(없으면 엇박)에 한 번 치기
        guard = 0
        while int(count_of(notes)[key]) < want and guard < 400:
            guard += 1
            var step := 0.5 if guard < 200 else 0.25
            var k := rng.randi_range(0, int(bars * 4 / step) - 1)
            var ms := int(round(k * step * BEAT * 1000.0))
            if ms < total_ms - 100 and not lane_busy(notes, ms, lane):
                notes.append([ms, lane, -1])
    notes.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
    return notes


## 컴퓨터(봇·진행자) 공격 패턴: 정박 위주 + 가끔 엇박·피버, 개수는 지정 수 그대로
static func computer_pattern(bars: int, spec: Dictionary, seed_value: int, difficulty: float = 0.5) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var notes := []
    var beat_ms := int(BEAT * 1000.0)
    var total_ms := bars * int(BAR * 1000.0)
    # 피버: 2개 이상 남는 북에 가끔 (한 박 또는 두 박 길이)
    for lane in 2:
        var key := "l" if lane == 0 else "r"
        if int(spec[key]) >= 3 and rng.randf() < 0.3 + difficulty * 0.4:
            var len := beat_ms * rng.randi_range(1, 2)
            var start := rng.randi_range(0, bars * 4 - 3) * beat_ms
            if start + len < total_ms - 100 and not lane_busy(notes, start, lane, start + len):
                notes.append([start, lane, start + len])
    # 나머지 한 번 치기: 정박 먼저, 어려워질수록 엇박도
    for lane in 2:
        var key := "l" if lane == 0 else "r"
        var guard := 0
        while int(count_of(notes)[key]) < int(spec[key]) and guard < 400:
            guard += 1
            var offbeat := rng.randf() < difficulty * 0.35
            var k := rng.randi_range(0, bars * 4 - 1)
            var ms := k * beat_ms + (beat_ms / 2 if offbeat else 0)
            if ms < total_ms - 100 and not lane_busy(notes, ms, lane) and not _same_time(notes, ms):
                notes.append([ms, lane, -1])
    return fit_pattern(notes, bars, spec, seed_value + 1)


static func _same_time(notes: Array, ms: int) -> bool:
    for n in notes:
        if absi(int(n[0]) - ms) < 60:
            return true
    return false


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
