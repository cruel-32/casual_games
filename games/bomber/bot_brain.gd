extends Node
## 봇 (연쇄폭탄마): 격자 위에서 생각한다
##   1. 지금 칸이 곧 터질 자리면 → 안전한 칸으로 도망
##   2. 여기서 터뜨리면 상자·상대가 맞고, 놓은 뒤 도망칠 길이 있으면 → 폭탄 놓고 도망
##   3. 가까운 아이템 → 줍기
##   4. 상자·상대를 노릴 자리로 이동
## 생각은 0.2~0.4초마다 (반응이 사람처럼 조금 늦음). Fighter 의 intent_* 만 채운다 (서버·혼자 연습에서만 돈다)

const Board := preload("res://games/bomber/board.gd")

var f: Fighter
var game: Node

var skill := 0.6              ## 0~1: 높을수록 빨리 생각하고 폭탄을 잘 놓음
var speed_mult := 0.9
var _think := 0.0
var _path: Array[Vector2i] = []


func _ready() -> void:
    f = get_parent() as Fighter
    skill = randf_range(0.35, 0.9)
    speed_mult = randf_range(0.8, 0.95)
    _think = randf_range(0.3, 1.6)          # 시작하자마자 다 같이 폭탄을 놓지 않게


func _physics_process(delta: float) -> void:
    f.intent_jump = false
    f.intent_charge = false
    if f.dead or not game.is_playing():
        f.intent_move = Vector3.ZERO
        return
    _think -= delta
    if _think <= 0.0:
        _think = randf_range(0.18, 0.34) * (1.35 - skill * 0.5)
        _decide()
    _follow()


func _board() -> Board:
    return game.board


func _step_time() -> float:
    return Board.TILE / maxf(f.move_speed * speed_mult, 1.0)


## 칸별로 불길이 닿기까지 남은 시간 (0 = 지금 타는 중). extra: 여기에 폭탄을 놓는다고 가정
func _danger(extra_cell: int = -1, extra_power: int = 0) -> Dictionary:
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
        list.append([game.bomb_cell(bm, now), int(bm.power), maxf(float(bm.t) - now, 0.0)])
    if extra_cell >= 0:
        list.append([extra_cell, extra_power, game.FUSE])
    var bomb_cells := {}
    for e in list:
        bomb_cells[int(e[0])] = true
    var blocked := func(c: Vector2i) -> bool:
        var i := b.idx(c)
        return bomb_cells.has(i) or game.items.has(i)
    for _pass in 2:
        for e in list:
            var res: Array = b.blast(b.cell(int(e[0])), int(e[1]), blocked)
            for c: Vector2i in res[0]:
                var i := b.idx(c)
                d[i] = minf(float(d.get(i, INF)), float(e[2]))
        for e in list:
            var i := int(e[0])
            if d.has(i) and float(d[i]) < float(e[2]):
                e[2] = d[i]              # 연쇄: 먼저 터지는 불길에 닿으면 같이 터짐
    return d


func _passable(c: Vector2i, start: Vector2i) -> bool:
    var b := _board()
    if not b.in_bounds(c) or b.solid(c):
        return false
    if c == start:
        return true
    return game.bomb_at(b.idx(c)) < 0


## 너비 우선 탐색: goal(c) 를 만족하는 가장 가까운 칸까지의 길 (출발 칸 제외). 못 찾으면 빈 배열
##   가는 길에 불길이 지나가는 칸은 피함 (도착 시각과 불길 시각이 겹치면)
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
            if prev.has(ni) or not _passable(n, start):
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


## 여기서 터뜨리면 상자나 상대가 맞는가
func _worth_bombing(c: Vector2i) -> bool:
    var b := _board()
    var power: int = game.stat(f.slot, 1)
    var res: Array = b.blast(c, power, func(n: Vector2i) -> bool: return game.bomb_at(b.idx(n)) >= 0)
    if not (res[1] as Array).is_empty():
        return true
    for o: Fighter in game.fighters:
        if o == f or o.dead or (f.team >= 0 and o.team == f.team):
            continue
        if (res[0] as Array).has(b.cell_at(o.global_position)):
            return true
    return false


func _decide() -> void:
    var b := _board()
    var c := b.cell_at(f.global_position)
    var ci := b.idx(c)
    var danger := _danger()
    if danger.has(ci):
        _path = _bfs(c, func(n: Vector2i) -> bool: return not danger.has(b.idx(n)), danger)
        if _path.is_empty():
            # 안전한 길이 없음: 시각은 무시하고 불길 없는 칸으로, 그것도 없으면 가장 늦게 터지는 칸으로
            _path = _bfs(c, func(n: Vector2i) -> bool: return not danger.has(b.idx(n)), {})
        if _path.is_empty():
            var best := float(danger[ci])
            _path = _bfs(c, func(n: Vector2i) -> bool: return float(danger.get(b.idx(n), INF)) > best + 0.4, {}, 8)
        return
    # 폭탄 놓기: 맞을 게 있고, 놓은 뒤 도망칠 곳이 있으면
    if game.active_bombs_of(f.slot) < game.stat(f.slot, 0) and game.can_place_at(ci) \
            and _worth_bombing(c) and randf() < 0.45 + skill * 0.5:
        var d2 := _danger(ci, game.stat(f.slot, 1))
        var esc := _bfs(c, func(n: Vector2i) -> bool: return not d2.has(b.idx(n)) and not _crowded(n), d2, 12)
        if not esc.is_empty() and esc.size() * _step_time() < game.FUSE - 0.6:
            f.intent_jump = true
            _path = esc
            _think = 0.35                 # 놓자마자 생각을 바꾸지 않게
            return
    # 아이템
    var p := _bfs(c, func(n: Vector2i) -> bool: return game.items.has(b.idx(n)), danger, 8)
    if not p.is_empty():
        _path = p
        return
    # 노릴 자리
    p = _bfs(c, func(n: Vector2i) -> bool: return not danger.has(b.idx(n)) and _worth_bombing(n), danger, 16)
    if not p.is_empty():
        _path = p
        return
    # 상대 쪽으로 (상자가 다 없어졌을 때)
    var target := _nearest_enemy()
    if target:
        var tc := b.cell_at(target.global_position)
        p = _bfs(c, func(n: Vector2i) -> bool: return absi(n.x - tc.x) + absi(n.y - tc.y) <= 2 and not danger.has(b.idx(n)), danger, 30)
        _path = p


## 다른 사람이 가까운 칸 (거기로 숨었다가 그 사람 폭탄에 갇히기 쉬움)
func _crowded(c: Vector2i) -> bool:
    var b := _board()
    for o: Fighter in game.fighters:
        if o == f or o.dead:
            continue
        var oc := b.cell_at(o.global_position)
        if absi(oc.x - c.x) + absi(oc.y - c.y) <= 1:
            return true
    return false


func _nearest_enemy() -> Fighter:
    var best: Fighter = null
    var bd := INF
    for o: Fighter in game.fighters:
        if o == f or o.dead or (f.team >= 0 and o.team == f.team):
            continue
        var d := o.global_position.distance_squared_to(f.global_position)
        if d < bd:
            bd = d
            best = o
    return best


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
    if _path.is_empty():
        target = b.center(b.cell_at(pos))     # 칸 가운데에 서 있기
    else:
        target = b.center(_path[0])
    var to := Vector3(target.x - pos.x, 0, target.z - pos.z)
    if to.length() < 0.15:
        f.intent_move = Vector3.ZERO
        return
    f.intent_face = Vector3.ZERO
    f.intent_move = to.normalized() * speed_mult * clampf(to.length() * 2.0, 0.35, 1.0)
