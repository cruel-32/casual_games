extends Node
## 봇 (무궁화 꽃이 피었습니다): 외치는 동안 결승선 쪽으로 걷듯 달리고, 술래가 돌아볼 때 멈춘다
##   사람보다 느리게 (speed 0.5~0.75), 출발도 굼뜨고, 겁 많은 봇은 외침이 끝나기 전에 미리 멈춘다
##   멈추는 반응은 사람처럼 들쭉날쭉 — 가끔 늦어서 걸린다 (slow_chance)
##   공격적인 봇은 외침이 끝나 갈 때 바로 옆 상대를 툭 밀어 빨간불까지 미끄러지게 한다
## Fighter 의 intent_* 만 채운다 (서버·혼자 연습에서만 돈다)

var f: Fighter
var game: Node

var speed := 0.65              ## 달리는 세기 (0~1, 사람은 1)
var caution := 0.3             ## 외침이 끝나기 전에 미리 멈추는 정도 (0~1)
var slow_chance := 0.1         ## 빨간불에 늦게 멈출 확률 (한 번마다)
var aggression := 0.3
var _lane_x := 0.0
var _cycle := -1
var _stop_at := INF            ## 이번 주기에 멈출 시각 (서버 시계)
var _go_at := INF              ## 다음 초록불에 출발할 시각
var _push_hold := 0
var _push_cool := 0.0


func _ready() -> void:
    f = get_parent() as Fighter
    speed = randf_range(0.5, 0.75)
    caution = randf_range(0.0, 0.6)
    slow_chance = randf_range(0.04, 0.14)
    aggression = randf_range(0.0, 0.7)
    var lim: float = float(game.half_w) - 1.0
    _lane_x = clampf(f.global_position.x + randf_range(-1.5, 1.5), -lim, lim)


func _physics_process(delta: float) -> void:
    f.intent_jump = false
    if _push_hold > 0:
        _push_hold -= 1
        f.intent_charge = _push_hold > 0       # 짧게 눌렀다 떼기 = 제자리 밀기
        f.intent_move = Vector3.ZERO
        return
    f.intent_charge = false
    if f.dead or not game.is_playing() or game.is_finished(f):
        f.intent_move = Vector3.ZERO
        return
    _push_cool = maxf(_push_cool - delta, 0.0)
    var now: float = game.net_now()
    var c: Dictionary = game.cycle
    if c.is_empty():
        f.intent_move = Vector3.ZERO
        return
    if int(c.idx) != _cycle:
        # 새 외침: 출발 반응 + 이번에 멈출 시각을 정한다
        _cycle = int(c.idx)
        _go_at = float(c.t) + randf_range(0.15, 0.6)
        var rs: float = float(c.t) + float(c.green)
        if randf() < slow_chance:
            _stop_at = rs + randf_range(0.2, 0.5)        # 늦음 → 걸림 (GRACE 0.2 + 멈추는 데 걸리는 시간)
        elif randf() < caution:
            _stop_at = rs - randf_range(0.4, 1.2)        # 겁이 나서 미리 멈춤
        else:
            _stop_at = rs - randf_range(0.05, 0.3)       # '다'를 듣고 멈춤
    var go := now >= _go_at and now < _stop_at
    if not go:
        f.intent_move = Vector3.ZERO
        return
    f.intent_face = Vector3.ZERO
    var to_x := clampf((_lane_x - f.global_position.x) * 0.3, -0.4, 0.4)
    f.intent_move = Vector3(to_x, 0, -1.0).normalized() * speed
    # 외침 끝 무렵 바로 옆 상대를 툭 민다
    var ph: Array = game.phase_at(now)
    if aggression > 0.3 and _push_cool <= 0.0 and String(ph[0]) == "green" and float(ph[1]) > 0.75 \
            and f.cooldown_timer <= 0.0 and randf() < aggression * delta * 4.0:
        var target := _near_rival()
        if target:
            var to := target.global_position - f.global_position
            to.y = 0.0
            f.intent_face = to
            f.intent_charge = true
            _push_hold = 3
            _push_cool = 4.0


func _near_rival() -> Fighter:
    for o: Fighter in game.fighters:
        if o == f or o.dead or game.is_finished(o):
            continue
        if f.team >= 0 and o.team == f.team:
            continue
        var to := o.global_position - f.global_position
        to.y = 0.0
        if to.length() < 1.8 and f.facing().dot(to.normalized()) > -0.2:
            return o
    return null
