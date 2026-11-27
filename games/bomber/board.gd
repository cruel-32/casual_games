extends RefCounted
## 연쇄폭탄마 격자 (판정·봇이 쓰는 순수 데이터. 화면은 bomber_game.gd 가 그린다)
##   칸 2m. 바깥 테두리와 (짝수, 짝수) 칸은 부서지지 않는 기둥, 나머지 빈칸에 상자를 무작위로 깐다
##   같은 씨앗값이면 모든 기기에서 같은 배치 (상자 속 아이템까지)

const TILE := 2.0
const EMPTY := 0
const PILLAR := 1
const CRATE := 2
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CRATE_DENSITY := 0.72
const ITEM_CHANCE := 0.36
## 아이템: 0 불꽃(폭발 범위 +1), 1 폭탄(동시에 놓는 개수 +1), 2 신발(속도)
const ITEM_FIRE := 0
const ITEM_BOMB := 1
const ITEM_SPEED := 2

var w := 13
var h := 11
var cells := PackedByteArray()
var crate_item := {}          ## 칸 번호 -> 아이템 (상자를 부수면 나옴)
var spawns: Array[Vector2i] = []
var x0 := 0.0                 ## 칸 (0,0) 의 왼쪽 위 모서리 (월드 x, z)
var z0 := 0.0


## 인원에 맞는 크기 (모두 홀수)
static func size_for(n: int) -> Vector2i:
    if n <= 4:
        return Vector2i(13, 11)
    if n <= 6:
        return Vector2i(15, 13)
    if n <= 8:
        return Vector2i(17, 13)
    if n <= 10:
        return Vector2i(19, 15)
    return Vector2i(21, 15)


func generate(n_players: int, seed_value: int) -> void:
    var sz := size_for(n_players)
    w = sz.x
    h = sz.y
    x0 = -w * TILE * 0.5
    z0 = -h * TILE * 0.5
    cells.resize(w * h)
    cells.fill(EMPTY)
    for y in h:
        for x in w:
            if x == 0 or y == 0 or x == w - 1 or y == h - 1 or (x % 2 == 0 and y % 2 == 0):
                cells[idx(Vector2i(x, y))] = PILLAR
    # 출발 자리: 안쪽 테두리 한 바퀴(1번째 줄)에 고르게, (홀수, 홀수) 칸에
    var ring := _ring()
    var keep := {}
    spawns.clear()
    for i in n_players:
        var want := int(floor((float(i) + 0.5) * ring.size() / n_players))
        var best := -1
        for d in ring.size():
            for sgn in [1, -1]:
                var k: int = posmod(want + d * sgn, ring.size())
                var c: Vector2i = ring[k]
                if c.x % 2 == 1 and c.y % 2 == 1 and not spawns.has(c):
                    best = k
                    break
            if best >= 0:
                break
        var sc: Vector2i = ring[best]
        spawns.append(sc)
        # 주변을 비워 처음 폭탄을 놓고 숨을 곳을 만든다 (테두리 ±2칸 + 그 안쪽 칸)
        for d in range(-2, 3):
            var rc: Vector2i = ring[posmod(best + d, ring.size())]
            keep[idx(rc)] = true
            for dir in DIRS:
                var nc: Vector2i = rc + dir
                if in_bounds(nc) and cells[idx(nc)] == EMPTY and absi(d) <= 2 and _inward(nc):
                    keep[idx(nc)] = true
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    crate_item.clear()
    for y in h:
        for x in w:
            var i := idx(Vector2i(x, y))
            if cells[i] != EMPTY or keep.has(i):
                continue
            if rng.randf() < CRATE_DENSITY:
                cells[i] = CRATE
                if rng.randf() < ITEM_CHANCE:
                    var r := rng.randf()
                    crate_item[i] = ITEM_FIRE if r < 0.38 else (ITEM_BOMB if r < 0.76 else ITEM_SPEED)


## 바깥에서 두 번째 칸이 아닌 안쪽 칸인지 (출발 자리 비울 때 테두리 줄 바로 안쪽만)
func _inward(c: Vector2i) -> bool:
    return c.x >= 1 and c.y >= 1 and c.x <= w - 2 and c.y <= h - 2


## 안쪽 테두리 칸들 (시계 방향, (1,1) 부터)
func _ring() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for x in range(1, w - 1):
        out.append(Vector2i(x, 1))
    for y in range(2, h - 1):
        out.append(Vector2i(w - 2, y))
    for x in range(w - 3, 0, -1):
        out.append(Vector2i(x, h - 2))
    for y in range(h - 3, 1, -1):
        out.append(Vector2i(1, y))
    return out


func idx(c: Vector2i) -> int:
    return c.y * w + c.x


func cell(i: int) -> Vector2i:
    return Vector2i(i % w, i / w)


func in_bounds(c: Vector2i) -> bool:
    return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func kind(c: Vector2i) -> int:
    return cells[idx(c)] if in_bounds(c) else PILLAR


func solid(c: Vector2i) -> bool:
    return kind(c) != EMPTY


func cell_at(p: Vector3) -> Vector2i:
    return Vector2i(int(floor((p.x - x0) / TILE)), int(floor((p.z - z0) / TILE)))


## 칸 가운데 (y = 0)
func center(c: Vector2i) -> Vector3:
    return Vector3(x0 + (c.x + 0.5) * TILE, 0.0, z0 + (c.y + 0.5) * TILE)


## 폭발이 번지는 칸 (연쇄는 제외 — 게임이 따로 처리). blocked(c) 가 true 면 그 칸까지 번지고 멈춤 (폭탄·아이템)
##   돌려줌: [불길 칸들, 맞은 상자 칸들]
func blast(c: Vector2i, power: int, blocked: Callable = Callable()) -> Array:
    var fire: Array[Vector2i] = [c]
    var crates: Array[Vector2i] = []
    for dir in DIRS:
        for k in range(1, power + 1):
            var n: Vector2i = c + dir * k
            var kd := kind(n)
            if kd == PILLAR:
                break
            fire.append(n)
            if kd == CRATE:
                crates.append(n)
                break
            if blocked.is_valid() and blocked.call(n):
                break
    return [fire, crates]


## 유령 길 (경기장 바깥 사각형) 반폭
func ghost_half() -> Vector2:
    return Vector2(w * TILE * 0.5 + 1.6, h * TILE * 0.5 + 1.6)


func ghost_len() -> float:
    var g := ghost_half()
    return g.x * 4.0 + g.y * 4.0


## 유령 길 위치 s → 월드 (y = 0). 위쪽 변(-z)에서 +x 로 시작해 시계 방향
func ghost_pos(s: float) -> Vector3:
    var g := ghost_half()
    s = fposmod(s, ghost_len())
    if s < g.x * 2.0:
        return Vector3(-g.x + s, 0, -g.y)
    s -= g.x * 2.0
    if s < g.y * 2.0:
        return Vector3(g.x, 0, -g.y + s)
    s -= g.y * 2.0
    if s < g.x * 2.0:
        return Vector3(g.x - s, 0, g.y)
    s -= g.x * 2.0
    return Vector3(-g.x, 0, g.y - s)


## 진행 방향 (단위 벡터)
func ghost_tangent(s: float) -> Vector3:
    var g := ghost_half()
    s = fposmod(s, ghost_len())
    if s < g.x * 2.0:
        return Vector3(1, 0, 0)
    if s < g.x * 2.0 + g.y * 2.0:
        return Vector3(0, 0, 1)
    if s < g.x * 4.0 + g.y * 2.0:
        return Vector3(-1, 0, 0)
    return Vector3(0, 0, -1)


## 월드 위치 → 가장 가까운 유령 길 위치 s
func ghost_project(p: Vector3) -> float:
    var g := ghost_half()
    var x := clampf(p.x, -g.x, g.x)
    var z := clampf(p.z, -g.y, g.y)
    var d_top := absf(z + g.y)
    var d_right := absf(g.x - x)
    var d_bottom := absf(g.y - z)
    var d_left := absf(x + g.x)
    var m := minf(minf(d_top, d_right), minf(d_bottom, d_left))
    if m == d_top:
        return x + g.x
    if m == d_right:
        return g.x * 2.0 + (z + g.y)
    if m == d_bottom:
        return g.x * 2.0 + g.y * 2.0 + (g.x - x)
    return g.x * 4.0 + g.y * 2.0 + (g.y - z)


## 유령이 던진 폭탄이 떨어질 칸: 유령이 선 변에서 안쪽으로 줄을 따라 빈칸을 찾음 (없으면 (-1,-1))
##   free(c) = 폭탄을 놓을 수 있는 칸인가
func ghost_target(s: float, free: Callable) -> Vector2i:
    var p := ghost_pos(s)
    var t := ghost_tangent(s)
    var c := cell_at(p)
    var inward := Vector2i(int(round(-t.z)), int(round(t.x)))   # 시계 방향 진행의 오른쪽 = 안쪽
    var line := Vector2i(clampi(c.x, 1, w - 2), clampi(c.y, 1, h - 2))
    var start := line
    if inward.y == 1:
        start = Vector2i(line.x, 0)
    elif inward.y == -1:
        start = Vector2i(line.x, h - 1)
    elif inward.x == 1:
        start = Vector2i(0, line.y)
    else:
        start = Vector2i(w - 1, line.y)
    for depth in [3, 2, 4, 1, 5]:
        var tc: Vector2i = start + inward * depth
        if in_bounds(tc) and not solid(tc) and free.call(tc):
            return tc
    return Vector2i(-1, -1)
