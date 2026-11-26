extends Node
## 봇 AI (Fighter의 자식 노드). 우선순위: 낙석 회피 > 근처 상대 밀치기 > 배회
## Fighter의 intent_* 값만 채운다.

var f: Fighter
var game: Node

var reaction := 0.4        # 경고 표시를 보고 반응하기까지 걸리는 시간
var aggression := 0.5
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _target: Fighter = null
var _target_timer := 0.0
var _desired_charge := -1.0
var _hold := 0.0
var jump_skill := 0.9          # 회전 기둥을 제때 넘을 확률
var _jump_decided := false
var _will_jump := false
var _jump_lead := 0.15


func _ready() -> void:
    f = get_parent() as Fighter
    reaction = randf_range(0.25, 0.6)
    aggression = randf_range(0.3, 0.85)
    jump_skill = randf_range(0.8, 0.97)


func _physics_process(delta: float) -> void:
    if f.dead or not game.is_playing():
        f.intent_move = Vector3.ZERO
        f.intent_charge = false
        return

    var pos := f.global_position
    var half: float = game.arena_half - 1.2
    var inward := Vector3.ZERO
    if pos.x > half: inward.x -= 1.0
    if pos.x < -half: inward.x += 1.0
    if pos.z > half: inward.z -= 1.0
    if pos.z < -half: inward.z += 1.0

    # 0) 회전 기둥 점프 (지나갈 때마다 성공 여부를 한 번 결정)
    var sw: Sweeper = game.sweeper
    if sw:
        var th := sw.time_until_hit(pos, f.velocity)
        if th > 0.6:
            _jump_decided = false
        elif not _jump_decided and th < 0.4:
            _jump_decided = true
            _will_jump = randf() < jump_skill
            _jump_lead = randf_range(0.14, 0.3)   # 발이 기둥 윗면을 넘는 데 약 0.13초 걸림
        if _will_jump and _jump_decided and th <= _jump_lead and f.is_on_floor():
            f.intent_jump = true
            _will_jump = false
        # 축 근처는 기둥이 느리게 지나가 넘을 수 없으니 벗어난다
        var r := Vector2(pos.x, pos.z).length()
        if r < 3.0:
            inward += Vector3(pos.x, 0, pos.z).normalized() * 1.5

    # 1) 낙석 회피
    var avoid := Vector3.ZERO
    var danger := false
    for r in game.rocks:
        if not is_instance_valid(r):
            continue
        var rock := r as FallingRock
        if rock.landed or rock.age < reaction:
            continue
        var to := pos - rock.target_point
        to.y = 0.0
        var dist := to.length()
        var safe := rock.danger_radius + 0.9
        if dist < safe:
            danger = true
            var away := to / dist if dist > 0.05 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
            avoid += away * (safe - dist) / maxf(rock.time_to_impact(), 0.25)
    if danger:
        f.intent_move = (avoid.normalized() + inward * 0.7).normalized()
        f.intent_face = Vector3.ZERO
        f.intent_charge = false
        _desired_charge = -1.0
        return

    # 2) 근처 아이템 줍기
    if not f.charging:
        var item: Node3D = game.nearest_item(pos, 9.0, f)
        if item:
            var to_i := item.global_position - pos
            to_i.y = 0.0
            f.intent_move = to_i.normalized()
            f.intent_face = Vector3.ZERO
            f.intent_charge = false
            return

    # 3) 공격
    _target_timer -= delta
    if _target_timer <= 0.0 or _target == null or _target.dead:
        _target = _pick_target()
        _target_timer = randf_range(2.0, 4.0)

    if _target:
        var to_t := _target.global_position - pos
        to_t.y = 0.0
        var dt := to_t.length()
        if f.charging and _desired_charge >= 0.0:
            _hold += delta
            f.intent_face = to_t
            f.intent_move = to_t.normalized() * 0.4
            f.intent_charge = _hold < _desired_charge
            return
        var max_reach := f.dash_distance_max + f.push_reach
        if f.cooldown_timer <= 0.0 and dt < max_reach + 0.3 and randf() < aggression * delta * 3.0:
            var need := dt - 1.0
            if dt < f.push_reach:
                _desired_charge = 0.05
            else:
                var c := clampf(inverse_lerp(f.dash_distance_min, f.dash_distance_max, need), 0.0, 1.0)
                _desired_charge = lerpf(f.tap_threshold, f.charge_max_time, c) + 0.05
            _hold = 0.0
            f.intent_charge = true
            f.intent_face = to_t
            f.intent_move = Vector3.ZERO
            return
        if dt > 3.0 and aggression > 0.55:
            f.intent_move = (to_t.normalized() * 0.8 + inward).limit_length(1.0)
            f.intent_face = Vector3.ZERO
            f.intent_charge = false
            return

    # 4) 배회
    _wander_timer -= delta
    var to_w := _wander_target - pos
    to_w.y = 0.0
    if _wander_timer <= 0.0 or to_w.length() < 1.5:
        _wander_target = Vector3(randf_range(-half, half), 0, randf_range(-half, half))
        _wander_timer = randf_range(2.0, 5.0)
    f.intent_move = (to_w.normalized() * 0.7 + inward).limit_length(1.0)
    f.intent_face = Vector3.ZERO
    f.intent_charge = false


func _pick_target() -> Fighter:
    var best: Fighter = null
    var best_d := 12.0
    for o: Fighter in game.fighters:
        if o == f or o.dead:
            continue
        if f.team >= 0 and o.team == f.team:
            continue            # 팀전: 같은 팀은 노리지 않음 (사람은 팀킬 가능)
        var d := o.global_position.distance_to(f.global_position) + randf_range(0.0, 3.0)
        if d < best_d:
            best_d = d
            best = o
    return best
