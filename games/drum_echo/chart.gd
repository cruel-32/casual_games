extends RefCounted
## 뒷북의 달인 — 곡 진행표·박자 판정 (서버·클라이언트·오프라인 공용, 화면 없음)
##
## 시간 단위: 곡 시작(t0)부터의 초. 120 BPM, 4/4, 한 마디 = 2초, 8분음표 칸(slot) = 0.25초
## 한 차례(turn) = 공격 N마디 + 따라 치기 N마디. 공격 노트는 칸 번호(0 ~ N*8-1)와 북(0 = 둥 왼쪽, 1 = 딱 오른쪽)

const BPM := 120.0
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0
const SLOTS_PER_BAR := 8
const SLOT := BAR / SLOTS_PER_BAR
const INTRO_BARS := 2               ## 시작 전 반주만 (카운트)
const OUTRO_BARS := 1

## 판정 (초): 따라 치기
const PERFECT := 0.045
const GOOD := 0.09
const BAD := 0.14
## 공격: 칸에서 이 이상 벗어나면 '엉뚱한 박자' (감점 후 가까운 칸으로 보정)
const ATTACK_PERFECT := 0.04
const ATTACK_GOOD := 0.075
const ATTACK_BAD := 0.10
const MAX_NOTES_PER_BAR := 6        ## 공격 한 마디에 넣을 수 있는 노트 수 (넘치면 무시)

const POINTS := {"perfect": 100, "good": 60, "bad": 20, "miss": 0, "wild": -50, "extra": -10}
## 공격 점수는 따라 치기보다 작게 (노트를 많이 넣을수록 유리해지지 않게) — 엉뚱한 박자는 감점
const ATTACK_POINTS := {"perfect": 50, "good": 30, "bad": 10, "wild": -50}
const JUDGE_NAMES := {"perfect": "PERFECT", "good": "GOOD", "bad": "BAD", "miss": "MISS", "wild": "엉뚱!", "extra": "헛침"}

## 곡 길이는 팀 수와 상관없이 거의 같다: 단계별 차례 수 [공격 마디 수, 차례 수]
##   팀마다 똑같이 돌아가며 공격하고, 남는 차례(팀 수로 나누어떨어지지 않는 만큼, 최대 2번)는 진행자가 랜덤 리듬으로 공격
##   예) 2팀: 1마디 ×4(팀 2바퀴) → 2마디 ×3(팀 1바퀴 + 진행자 1) → 4마디 ×2(팀 1바퀴)
##   개인전은 모든 차례를 진행자가 공격
const STAGES := [[1, 4], [2, 3], [4, 2]]
const HOST_MAX_EXTRA := 2


## 진행표: [{attack_team, bars, attack_bar, response_bar, host}] — attack_team -1 = 진행자 (모두가 따라 침)
static func build_turns(teams: int) -> Array:
    var turns := []
    var bar := INTRO_BARS
    for st in STAGES:
        var n := int(st[0])
        var count := int(st[1])
        var order := []
        if teams >= 2:
            var rounds := maxi(1, count / teams)
            for r in rounds:
                order.append_array(range(teams))
            for k in clampi(count - rounds * teams, 0, HOST_MAX_EXTRA):
                order.append(-1)
        else:
            for k in count:
                order.append(-1)
        for t in order:
            turns.append({"attack_team": t, "bars": n, "attack_bar": bar, "response_bar": bar + n, "host": t < 0})
            bar += n * 2
    return turns


static func total_bars(turns: Array) -> int:
    if turns.is_empty():
        return INTRO_BARS + OUTRO_BARS
    var last: Dictionary = turns.back()
    return int(last.response_bar) + int(last.bars) + OUTRO_BARS


static func bar_time(bar: float) -> float:
    return bar * BAR


## 공격 시작 시각 + 칸 → 곡 시간
static func slot_time(turn: Dictionary, slot: int, response: bool) -> float:
    return bar_time(int(turn.response_bar if response else turn.attack_bar)) + slot * SLOT


## 공격 입력(곡 시간) → [칸, 판정] (칸이 범위 밖이면 -1)
static func quantize_attack(turn: Dictionary, t: float) -> Array:
    var rel := t - bar_time(int(turn.attack_bar))
    var slot := roundi(rel / SLOT)
    if slot < 0 or slot >= int(turn.bars) * SLOTS_PER_BAR:
        return [-1, ""]
    var off := absf(rel - slot * SLOT)
    var j := "perfect" if off <= ATTACK_PERFECT else ("good" if off <= ATTACK_GOOD else ("bad" if off <= ATTACK_BAD else "wild"))
    return [slot, j]


## 따라 치기 판정: 아직 안 맞힌 노트 중 같은 북·가장 가까운 것 → [노트 번호, 판정] (없으면 [-1, "extra"])
## notes: [[slot, lane], ...], taken: 맞힌 노트 번호 Dictionary
static func judge_response(turn: Dictionary, notes: Array, taken: Dictionary, lane: int, t: float) -> Array:
    var best := -1
    var best_off := 1e9
    for i in notes.size():
        if taken.has(i) or int(notes[i][1]) != lane:
            continue
        var off := absf(t - slot_time(turn, int(notes[i][0]), true))
        if off < best_off:
            best_off = off
            best = i
    if best < 0 or best_off > BAD:
        return [-1, "extra"]
    return [best, "perfect" if best_off <= PERFECT else ("good" if best_off <= GOOD else "bad")]


## 컴퓨터(또는 봇) 공격 패턴: 진행할수록 조금씩 어렵게. seed 가 같으면 같은 패턴
static func computer_pattern(bars: int, difficulty: float, seed_value: int) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var notes := []
    for b in bars:
        var per := clampi(rng.randi_range(3, 4) + int(difficulty * 2.0), 2, MAX_NOTES_PER_BAR)
        var slots := []
        # 정박(0,2,4,6)을 먼저, 어려워질수록 엇박(1,3,5,7)도
        var pool := [0, 2, 4, 6]
        pool.shuffle()
        var off_pool := [1, 3, 5, 7]
        off_pool.shuffle()
        var off_count := int(round(per * clampf(difficulty * 0.6, 0.0, 0.5)))
        for k in per - off_count:
            if k < pool.size():
                slots.append(pool[k])
        for k in off_count:
            slots.append(off_pool[k])
        slots.sort()
        for s in slots:
            notes.append([b * SLOTS_PER_BAR + int(s), rng.randi_range(0, 1)])
    return notes


## 봇이 따라 치기: 노트마다 판정을 무작위로 (실력 skill 0~1)
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
