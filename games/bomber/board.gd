extends RefCounted
## 크레이지 봄버 격자 (판정·봇이 쓰는 순수 데이터. 화면은 bomber_game.gd 가 그린다)
##   블록은 2m 정육면체. 칸마다 LAYERS 층 쌓여 있고, 모두 그 꼭대기(평평)에서 시작한다
##   바깥 테두리와 (짝수, 짝수) 칸 중 절반(엇갈리게)은 부서지지 않는 블록(기둥) — 처음엔 다른 블록과 높이가 같아 위에 설 수 있다
##   폭발로 블록이 깎여 높이가 0 이 된 칸은 구멍 → 아래 용암으로 떨어진다. 경기장 가장자리 밖으로 떨어져도 탈락

const TILE := 2.0
const BLOCK := 2.0
const LAYERS := 4
const EMPTY := 0
const PILLAR := 1
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## 아이템: 0 불꽃(폭발 범위 +1), 1 폭탄(동시에 던지는 개수 +1), 2 속도
const ITEM_FIRE := 0
const ITEM_BOMB := 1
const ITEM_SPEED := 2
const ITEM_COOL := 3            ## 던진 뒤 쿨타임 줄임

var w := 13
var h := 11
var cells := PackedByteArray()     ## EMPTY / PILLAR
var hgt := PackedByteArray()       ## 칸마다 남은 블록 수 (기둥은 쓰지 않음)
var spawns: Array[Vector2i] = []
var x0 := 0.0                      ## 칸 (0,0) 의 왼쪽 위 모서리 (월드 x, z)
var z0 := 0.0


## 인원에 맞는 크기 (정사각형, 홀수)
static func size_for(n: int) -> Vector2i:
    if n <= 3:
        return Vector2i(13, 13)
    if n <= 5:
        return Vector2i(15, 15)
    if n <= 8:
        return Vector2i(17, 17)
    return Vector2i(19, 19)


func generate(n_players: int) -> void:
    var sz := size_for(n_players)
    w = sz.x
    h = sz.y
    x0 = -w * TILE * 0.5
    z0 = -h * TILE * 0.5
    cells.resize(w * h)
    cells.fill(EMPTY)
    hgt.resize(w * h)
    hgt.fill(LAYERS)
    for y in h:
        for x in w:
            if x == 0 or y == 0 or x == w - 1 or y == h - 1 or (x % 2 == 0 and y % 2 == 0 and (x / 2 + y / 2) % 2 == 0):
                cells[idx(Vector2i(x, y))] = PILLAR
    # 출발 자리: 안쪽 테두리 한 바퀴(1번째 줄)에 고르게, (홀수, 홀수) 칸에
    var ring := _ring()
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
        spawns.append(ring[best])


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


## 부서지지 않는 칸 (또는 경기장 밖)
func pillar(c: Vector2i) -> bool:
    return not in_bounds(c) or cells[idx(c)] == PILLAR


## 블록 수 (밖은 -1, 부서지지 않는 칸은 늘 LAYERS)
func height(c: Vector2i) -> int:
    if not in_bounds(c):
        return -1
    return hgt[idx(c)]


## 서 있을 수 있는 칸 (구멍 아님)
func standable(c: Vector2i) -> bool:
    return height(c) > 0


func cell_at(p: Vector3) -> Vector2i:
    return Vector2i(int(floor((p.x - x0) / TILE)), int(floor((p.z - z0) / TILE)))


## 칸 가운데 (y = 0)
func center(c: Vector2i) -> Vector3:
    return Vector3(x0 + (c.x + 0.5) * TILE, 0.0, z0 + (c.y + 0.5) * TILE)


## 칸 꼭대기 높이 (바닥 기준 m)
func top(c: Vector2i) -> float:
    return maxf(height(c), 0) * BLOCK


## 폭발 범위: 폭탄 칸 c 를 가운데로 한 정사각형 (반경 r → (2r+1)×(2r+1) 칸, 기본 r=1 → 3×3). 높이도 위아래 r 층
func blast(c: Vector2i, r: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            var n := c + Vector2i(dx, dy)
            if in_bounds(n):
                out.append(n)
    return out


## 폭발 뒤 칸 높이: 폭발 층 L(폭탄이 놓인 칸 높이), 반경 r. 부서지는 블록이 범위(L-r ~ L+r 층) 안까지 쌓여 있으면
##   범위 안 블록이 모두 사라져 높이 L-r 이 됨 (평평한 곳이면 r 층 깎임). 더 높이 쌓인 탑·더 낮은 칸·부서지지 않는 칸은 그대로
func height_after(n: Vector2i, level: int, r: int) -> int:
    var hn := height(n)
    if pillar(n) or hn <= 0:
        return hn
    if hn > level - r and hn <= level + r:
        return maxi(level - r, 0)
    return hn


## 던진 폭탄이 떨어질 칸: from 에서 dir 쪽으로 dist m. 경기장 밖이면 앞쪽으로 당김
func throw_target(from: Vector3, dir: Vector3, dist: float) -> Vector2i:
    var d := Vector3(dir.x, 0, dir.z)
    if d.length() < 0.01:
        d = Vector3(0, 0, -1)
    d = d.normalized()
    var step := 0.5
    var t := dist
    while t > 0.0:
        var c := cell_at(from + d * t)
        if in_bounds(c):
            return c
        t -= step
    return cell_at(from)


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


## 유령이 던진 폭탄이 떨어질 칸: 유령이 선 변에서 안쪽으로 줄을 따라 서 있을 수 있는 칸을 찾음 (없으면 (-1,-1))
func ghost_target(s: float) -> Vector2i:
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
        if standable(tc):
            return tc
    return Vector2i(-1, -1)
