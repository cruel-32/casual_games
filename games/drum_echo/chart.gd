extends RefCounted
## 뒷북의 달인 — 곡 진행표·박자 판정 (서버·클라이언트·오프라인 공용, 화면 없음)
##
## 시간 단위: 곡 시작(t0)부터의 초. 120 BPM, 4/4, 한 박 = 0.5초, 한 마디 = 2초, 반 박(8분음표) 칸(slot) = 0.25초
## 한 차례(turn) = [쉼] 공격 N마디 [쉼] 따라 치기 N마디
##   쉼(텀): 컴퓨터가 정해 준 마디 수·노트 수를 보고 준비하는 시간. 곡이 진행될수록 짧아진다 (4박 → 1박)
## 노트: [칸, 북, 끝 칸]  칸 = 0 ~ N*8-1, 북 0 = 둥(왼쪽) 1 = 딱(오른쪽), 끝 칸 = -1 이면 한 번 치기, 아니면 피버(누르고 있다가 끝 칸에서 뗌)
## 노트 수 지정(spec): {"on": 정박 수, "off": 엇박 수, "fever": 피버 수} — 피버 하나는 노트 2개(누름·뗌)로 센다

const BPM := 120.0
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0
const SLOTS_PER_BAR := 8
const SLOT := BAR / SLOTS_PER_BAR
const INTRO_BARS := 2               ## 시작 전 반주만 (카운트)
const OUTRO_BARS := 1

## 쉼(박 수): 첫 차례 GAP_START → 마지막 차례 GAP_END 로 점점 짧아짐
const GAP_START := 4
const GAP_END := 1

## 판정 (초): 따라 치기
const PERFECT := 0.045
const GOOD := 0.09
const BAD := 0.14
## 공격: 칸에서 이 이상 벗어나면 '엉뚱한 박자' (감점 후 가까운 칸으로 보정)
const ATTACK_PERFECT := 0.04
const ATTACK_GOOD := 0.075
const ATTACK_BAD := 0.10
const MAX_NOTES_PER_BAR := 8        ## 공격 한 마디에 넣을 수 있는 노트 (칸 수만큼. 개수는 지정 수로 감점)

## 피버: 이만큼(초) 이상 누르고 있다 떼면 피버. 가장 짧은 피버 = 2칸(한 박)
const FEVER_HOLD_MIN := 0.3
const FEVER_MIN_SLOTS := 2

const POINTS := {"perfect": 100, "good": 60, "bad": 20, "miss": 0, "wild": -50, "extra": -10}
## 공격 점수는 따라 치기보다 작게 (노트를 많이 넣을수록 유리해지지 않게) — 엉뚱한 박자는 감점
const ATTACK_POINTS := {"perfect": 50, "good": 30, "bad": 10, "wild": -50}
## 지정한 노트 수보다 많거나 적으면 노트 1개당 감점 (피버 1개 = 2개)
const COUNT_PENALTY := 40
const JUDGE_NAMES := {"perfect": "PERFECT", "good": "GOOD", "bad": "BAD", "miss": "MISS", "wild": "엉뚱!", "extra": "헛침"}

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


## 공격 시작 시각 + 칸 → 곡 시간
static func slot_time(turn: Dictionary, slot: int, response: bool) -> float:
    return float(turn.response_t if response else turn.attack_t) + slot * SLOT


static func is_fever(n: Array) -> bool:
    return n.size() > 2 and int(n[2]) >= 0


## 노트 수 (피버 = 2)
static func units(notes: Array) -> int:
    var u := 0
    for n in notes:
        u += 2 if is_fever(n) else 1
    return u


static func spec_units(spec: Dictionary) -> int:
    return int(spec.get("on", 0)) + int(spec.get("off", 0)) + 2 * int(spec.get("fever", 0))


## 노트 목록 → {on, off, fever}
static func count_of(notes: Array) -> Dictionary:
    var c := {"on": 0, "off": 0, "fever": 0}
    for n in notes:
        if is_fever(n):
            c.fever += 1
        elif int(n[0]) % 2 == 0:
            c.on += 1
        else:
            c.off += 1
    return c


## 지정 수와 다른 만큼 (노트 단위, 피버 = 2)
static func count_diff(notes: Array, spec: Dictionary) -> int:
    var c := count_of(notes)
    return absi(c.on - int(spec.on)) + absi(c.off - int(spec.off)) + 2 * absi(c.fever - int(spec.fever))


static func spec_text(spec: Dictionary) -> String:
    var parts := []
    if int(spec.get("on", 0)) > 0:
        parts.append("정박 %d" % int(spec.on))
    if int(spec.get("off", 0)) > 0:
        parts.append("엇박 %d" % int(spec.off))
    if int(spec.get("fever", 0)) > 0:
        parts.append("피버 %d" % int(spec.fever))
    return " · ".join(parts) + "  (노트 %d개)" % spec_units(spec)


## 컴퓨터가 정해 주는 노트 수: 진행할수록 조금씩 많고 어렵게 (difficulty 0~1)
static func make_spec(bars: int, difficulty: float, seed_value: int) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var fever := 0
    var fever_chance := 0.35 + difficulty * 0.5
    for b in bars:
        if b % 2 == 0 and rng.randf() < fever_chance:
            fever += 1
    if bars >= 2 and fever == 0 and difficulty > 0.3:
        fever = 1
    var per_bar := 3.0 + difficulty * 1.6           # 한 마디 노트 수 (피버 = 2)
    var total := clampi(int(round(per_bar * bars + rng.randf_range(-0.5, 0.5))), 2, bars * 6)
    var rest := maxi(total - fever * 2, 1)
    var off := clampi(int(round(rest * clampf(0.1 + difficulty * 0.35, 0.0, 0.45))), 0, bars * 3)
    if difficulty < 0.15:
        off = 0
    var on := maxi(rest - off, 1)
    on = mini(on, bars * 4)
    return {"on": on, "off": off, "fever": fever}


## 빈자리 찾기 도우미: 칸 slot·북 lane 에 노트를 둘 수 있나
##   한 칸에는 한 노트 (피버 시작 포함), 피버가 누르고 있는 북의 [시작, 끝] 칸에는 같은 북을 못 침
static func _free(notes: Array, slot: int, lane: int, end_slot: int = -1) -> bool:
    for n in notes:
        var ns := int(n[0])
        var nl := int(n[1])
        var ne := int(n[2]) if is_fever(n) else -1
        if ns == slot:
            return false                                    # 한 칸에는 한 노트
        if ne >= 0 and nl == lane and slot >= ns and slot <= ne:
            return false                                    # 그 북은 피버로 누르고 있는 중
        if end_slot >= 0 and nl == lane and ns >= slot and ns <= end_slot:
            return false                                    # 새 피버가 누를 동안 같은 북 노트
        if end_slot >= 0 and ne >= 0 and nl == lane and not (end_slot < ns or slot > ne):
            return false                                    # 같은 북 피버끼리 겹침
    return true


## 지정 수에 딱 맞는 패턴 (컴퓨터·봇 공격, 보정에도 씀). base 의 노트를 최대한 살리고 넘치면 빼고 모자라면 채운다
static func fit_pattern(base: Array, bars: int, spec: Dictionary, seed_value: int) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var last := bars * SLOTS_PER_BAR
    var fevers := []
    var ons := []
    var offs := []
    for n in base:
        var nn := [int(n[0]), int(n[1]), int(n[2]) if n.size() > 2 else -1]
        if is_fever(nn):
            fevers.append(nn)
        elif nn[0] % 2 == 0:
            ons.append(nn)
        else:
            offs.append(nn)
    # 넘치면 뒤에서부터 뺀다 (공격자가 마지막에 덤으로 친 것부터)
    while fevers.size() > int(spec.fever):
        fevers.pop_back()
    while ons.size() > int(spec.on):
        ons.remove_at(rng.randi_range(0, ons.size() - 1))
    while offs.size() > int(spec.off):
        offs.remove_at(rng.randi_range(0, offs.size() - 1))
    var notes: Array = fevers + ons + offs
    # 모자라면 채운다: 피버 먼저 (자리가 많이 필요)
    var guard := 0
    while count_of(notes).fever < int(spec.fever) and guard < 200:
        guard += 1
        var len := FEVER_MIN_SLOTS * rng.randi_range(1, 2)
        var s := rng.randi_range(0, (last - len - 1) / 2) * 2
        var ln := rng.randi_range(0, 1)
        if s + len <= last - 1 and _free(notes, s, ln, s + len):
            notes.append([s, ln, s + len])
    guard = 0
    while count_of(notes).on < int(spec.on) and guard < 300:
        guard += 1
        var s := rng.randi_range(0, last / 2 - 1) * 2
        var ln := 0 if rng.randf() < 0.6 else 1
        if _free(notes, s, ln):
            notes.append([s, ln, -1])
        elif _free(notes, s, 1 - ln):
            notes.append([s, 1 - ln, -1])
    guard = 0
    while count_of(notes).off < int(spec.off) and guard < 300:
        guard += 1
        var s := rng.randi_range(0, last / 2 - 1) * 2 + 1
        var ln := 1 if rng.randf() < 0.6 else 0
        if _free(notes, s, ln):
            notes.append([s, ln, -1])
        elif _free(notes, s, 1 - ln):
            notes.append([s, 1 - ln, -1])
    notes.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
    return notes


## 컴퓨터(또는 봇·진행자) 공격 패턴: 지정 수 그대로
static func computer_pattern(bars: int, spec: Dictionary, seed_value: int) -> Array:
    return fit_pattern([], bars, spec, seed_value)


## 공격 입력(곡 시간) → [칸, 판정] (칸이 범위 밖이면 -1)
static func quantize_attack(turn: Dictionary, t: float) -> Array:
    var rel := t - float(turn.attack_t)
    var slot := roundi(rel / SLOT)
    if slot < 0 or slot >= int(turn.bars) * SLOTS_PER_BAR:
        return [-1, ""]
    return [slot, attack_judge(absf(rel - slot * SLOT))]


static func attack_judge(off: float) -> String:
    return "perfect" if off <= ATTACK_PERFECT else ("good" if off <= ATTACK_GOOD else ("bad" if off <= ATTACK_BAD else "wild"))


## 공격 중 뗌: 누른 칸 start, 누른 시각 t_press, 뗀 시각 t → [끝 칸(-1 = 피버 아님), 판정]
static func quantize_release(turn: Dictionary, start: int, t_press: float, t: float) -> Array:
    if t - t_press < FEVER_HOLD_MIN:
        return [-1, ""]
    var rel := t - float(turn.attack_t)
    var e := clampi(roundi(rel / SLOT), start + FEVER_MIN_SLOTS, int(turn.bars) * SLOTS_PER_BAR)
    return [e, attack_judge(absf(rel - e * SLOT))]


## 따라 치기 판정 (누름): 아직 안 맞힌 노트(한 번 치기·피버 시작) 중 같은 북·가장 가까운 것 → [노트 번호, 판정] (없으면 [-1, "extra"])
## notes: [[slot, lane, end], ...], taken: 맞힌 노트 번호 Dictionary (피버 끝은 -(번호+1))
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
    return [best, timing_judge(best_off)]


static func timing_judge(off: float) -> String:
    return "perfect" if off <= PERFECT else ("good" if off <= GOOD else ("bad" if off <= BAD else "miss"))


## 따라 치기 판정 (피버 뗌): 끝 칸 시각과 비교. 너무 일찍 떼거나 너무 늦게 떼면 MISS
static func judge_release(turn: Dictionary, note: Array, t: float) -> String:
    return timing_judge(absf(t - slot_time(turn, int(note[2]), true)))


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
