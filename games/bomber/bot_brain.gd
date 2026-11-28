extends Node
## 봇 (크레이지 봄버): 블록 탑 격자 위에서 생각한다
##   1. 지금 칸이 곧 터질 자리면 → 안전한 칸으로 도망 (구멍은 피하고, 2층까지는 점프로 오름)
##   2. 던질 폭탄이 있고 상대가 4.5~11m 안이면 → 상대 쪽으로 몸을 돌리고, 거리만큼 눌렀다가 던짐 (내가 맞을 자리는 안 던짐)
##   3. 가까운 아이템 줍기
##   4. 상대에게서 2~4칸(던질 수 있는 거리) 떨어진 자리로 이동
## 생각은 0.2~0.4초마다. Fighter 의 intent_* 만 채운다 (서버·혼자 연습에서만 돈다)

const Board := preload("res://games/bomber/board.gd")

var f: Fighter
var game: Node

var skill := 0.6
var speed_mult := 0.9
var _think := 0.0
var _path: Array[Vector2i] = []
var _aim_dir := Vector3.ZERO      ## 던지려는 방향 (0 이면 던지는 중 아님)
var _aim_time := 0.0              ## 눌러야 하는 시간
var _aim_timeout := 0.0


func _ready() -> void:
    f = get_parent() as Fighter
    skill = randf_range(0.35, 0.9)
    speed_mult = randf_range(0.8, 0.95)
    _think = randf_range(0.4, 1.6)


func _physics_process(delta: float) -> void:
    f.intent_jump = false
    if f.dead or not game.is_playing():
        f.intent_move = Vector3.ZERO
        f.intent_charge = false
        _aim_dir = Vector3.ZERO
        return
    if _aim_dir != Vector3.ZERO:
        _do_aim(delta)
        return
    f.intent_charge = false
    f.intent_face = Vector3.ZERO
    _think -= delta
    if _think <= 0.0:
        _think = randf_range(0.18, 0.34) * (1.35 - skill * 0.5)
        _decide()
    _follow()


func _board() -> Board:
    return game.board


func _step_time() -> float:
    return Board.TILE / maxf(f.move_speed * speed_mult, 1.0)


## 던지기: 먼저 몸을 돌리고, 다 돌면 필요한 만큼 눌렀다 뗀다. 그사이 내 칸이 위험해지면 취소
func _do_aim(delta: float) -> void:
    f.intent_move = Vector3.ZERO
    f.intent_face = _aim_dir
    _aim_timeout -= delta
    var b := _board()
    var danger := _danger()
    if danger.has(b.idx(b.cell_at(f.global_position))) or _aim_timeout <= 0.0:
        f.intent_charge = false
        _aim_dir = Vector3.ZERO
        _think = 0.0
        return
    if not f.charging:
        f.intent_charge = f.facing().dot(_aim_dir) > 0.97
        return
    f.intent_charge = f.charge_time < _aim_time
    if not f.intent_charge:
        _aim_dir = Vector3.ZERO
        _think = randf_range(0.1, 0.3)


## 칸별로 불길이 닿기까지 남은 시간 (0 = 지금 타는 중)
func _danger() -> Dictionary:
    var b := _board()
    var now: float = game.net_now()
    var d := {}
    for fl in game.flames:
        if now < float(fl.t1):
            for i in fl.cells:
                d[int(i)] = 0.0
    var list: Array = []
    for id in game.bombs:
        var bm: Dictionary = game.bombs[id]
        list.append([int(bm.cell), int(bm.power), maxf(float(bm.t) - now, 0.0)])
    for _pass in 2:
        for e in list:
            for c: Vector2i in b.blast(b.cell(int(e[0])), int(e[1])):
                var i := b.idx(c)
                d[i] = minf(float(d.get(i, INF)), float(e[2]))
        for e in list:
            var i := int(e[0])
            if d.has(i) and float(d[i]) < float(e[2]):
                e[2] = d[i]              # 연쇄: 먼저 터지는 불길에 닿으면 같이 터짐
    return d


## 옆 칸으로 갈 수 있나: 서 있을 수 있고, 2층 넘게 높지 않음 (점프 약 4.3m)
func _can_step(from: Vector2i, to: Vector2i) -> bool:
    var b := _board()
    if not b.standable(to):
        return false
    return b.height(to) - b.height(from) <= 2


func _bfs(start: Vector2i, goal: Callable, danger: Dictionary, max_depth: int = 30) -> Array[Vector2i]:
    var b := _board()
    var st := _step_time()
    var prev := {b.idx(start): -1}
    var depth := {b.idx(start): 0}
    var queue: Array[Vector2i] = [start]
    var head := 0
    while head < queue.size():
        var c: Vector2i = queue[head]
        head += 1
        var dc: int = depth[b.idx(c)]
        if c != start and goal.call(c):
            var path: Array[Vector2i] = []
            var k := b.idx(c)
            while k != b.idx(start):
                path.push_front(b.cell(k))
                k = prev[k]
            return path
        if dc >= max_depth:
            continue
        for dir in Board.DIRS:
            var n: Vector2i = c + dir
            var ni := b.idx(n)
            if prev.has(ni) or not _can_step(c, n):
                continue
            var arrive := (dc + 1) * st
            if danger.has(ni):
                var dt := float(danger[ni])
                if dt < arrive + 0.35 and dt + game.FLAME_TIME + 0.15 > arrive - 0.25:
                    continue
            prev[ni] = b.idx(c)
            depth[ni] = dc + 1
            queue.append(n)
    return []


func _enemies() -> Array[Fighter]:
    var out: Array[Fighter] = []
    for o: Fighter in game.fighters:
        if o != f and not o.dead and (f.team < 0 or o.team != f.team):
            out.append(o)
    return out


func _decide() -> void:
    var b := _board()
    var c := b.cell_at(f.global_position)
    var ci := b.idx(c)
    var danger := _danger()
    if danger.has(ci):
        _path = _bfs(c, func(n: Vector2i) -> bool: return not danger.has(b.idx(n)), danger)
        if _path.is_empty():
            _path = _bfs(c, func(n: Vector2i) -> bool: return not danger.has(b.idx(n)), {})
        return
    # 던지기
    if game.active_bombs_of(f.slot) < game.stat(f.slot, 0) and randf() < 0.35 + skill * 0.5:
        var best: Fighter = null
        var bd := INF
        for o in _enemies():
            var to := o.global_position - f.global_position
            to.y = 0.0
            var d := to.length()
            if d >= 4.5 and d <= game.THROW_MAX and d < bd:
                bd = d
                best = o
        if best:
            var tc := b.cell_at(best.global_position)
            var mine: Array[Vector2i] = b.blast(tc, game.stat(f.slot, 1))
            if not mine.has(c):
                var to := best.global_position - f.global_position
                to.y = 0.0
                # 조금 빗나가게 (실력이 낮을수록)
                var dist := to.length() + randf_range(-1.2, 1.2) * (1.0 - skill)
                _aim_dir = to.normalized().rotated(Vector3.UP, randf_range(-0.12, 0.12) * (1.0 - skill))
                var r := clampf((dist - game.THROW_MIN) / (game.THROW_MAX - game.THROW_MIN), 0.0, 1.0)
                _aim_time = f.tap_threshold + 0.02 + r * (f.charge_full_time() - f.tap_threshold)
                _aim_timeout = 2.5
                _path.clear()
                return
    # 발밑에 놓기 (탭): 상대가 내 폭발 범위 안이고, 놓은 뒤 도망칠 곳이 있으면
    if game.active_bombs_of(f.slot) < game.stat(f.slot, 0) and randf() < 0.3 + skill * 0.5:
        var pw: int = game.stat(f.slot, 1)
        var near := false
        for o in _enemies():
            var oc := b.cell_at(o.global_position)
            if absi(oc.x - c.x) <= pw and absi(oc.y - c.y) <= pw:
                near = true
                break
        if near:
            var d2 := _danger()
            for n: Vector2i in b.blast(c, pw):
                d2[b.idx(n)] = minf(float(d2.get(b.idx(n), INF)), game.LAND_FUSE)
            var esc := _bfs(c, func(n: Vector2i) -> bool: return not d2.has(b.idx(n)), d2, 8)
            if not esc.is_empty() and esc.size() * _step_time() < game.LAND_FUSE - 0.5:
                _aim_dir = f.facing()
                _aim_time = 0.04             # 탭 (tap_threshold 보다 짧게)
                _aim_timeout = 1.0
                _path = esc
                return
    # 아이템
    var p := _bfs(c, func(n: Vector2i) -> bool: return game.items.has(b.idx(n)), danger, 6)
    if not p.is_empty():
        _path = p
        return
    # 상대와 알맞은 거리로
    var target: Fighter = null
    var bd2 := INF
    for o in _enemies():
        var d := o.global_position.distance_squared_to(f.global_position)
        if d < bd2:
            bd2 = d
            target = o
    if target:
        var tc := b.cell_at(target.global_position)
        var md := absi(tc.x - c.x) + absi(tc.y - c.y)
        # 던질 수 있는 거리(대각선 포함 약 4.5~11m)에 서 있기: 가로·세로 칸 차이가 각각 4칸 이내, 합이 2~5
        var dx := absi(tc.x - c.x)
        var dy := absi(tc.y - c.y)
        if md >= 2 and md <= 5 and dx <= 4 and dy <= 4 and randf() < 0.8:
            _path.clear()
            return
        _path = _bfs(c, func(n: Vector2i) -> bool:
            var m := absi(n.x - tc.x) + absi(n.y - tc.y)
            return m >= 2 and m <= 4 and absi(n.x - tc.x) <= 3 and absi(n.y - tc.y) <= 3 and not danger.has(b.idx(n)), danger, 24)


func _follow() -> void:
    var b := _board()
    var pos := f.global_position
    while not _path.is_empty():
        var ctr := b.center(_path[0])
        if Vector2(ctr.x - pos.x, ctr.z - pos.z).length() < 0.3:
            _path.pop_front()
        else:
            break
    var target: Vector3
    var here := b.cell_at(pos)
    if _path.is_empty():
        target = b.center(here)
    else:
        target = b.center(_path[0])
        # 다음 칸이 높으면 가까이 가서 점프
        var up: float = b.top(_path[0]) - (pos.y - float(game.floor_y))
        if up > 0.3 and f.is_on_floor() and Vector2(target.x - pos.x, target.z - pos.z).length() < 2.2:
            f.intent_jump = true
    var to := Vector3(target.x - pos.x, 0, target.z - pos.z)
    if to.length() < 0.15:
        f.intent_move = Vector3.ZERO
        return
    f.intent_move = to.normalized() * speed_mult * clampf(to.length() * 2.0, 0.35, 1.0)
