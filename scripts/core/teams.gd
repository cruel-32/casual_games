extends RefCounted
## 팀전 규칙 (대기룸·서버·게임 공통)
##   방 설정 teams: 0 = 개인전(1:1:1…), 2·3·4 = 그 수만큼 팀으로 나눠 싸움
##   - 팀끼리 인원이 맞아야 시작 (봇 채우기를 켜면 빈자리는 봇이 채워 인원을 맞춤)
##   - 경기 도중 누가 나가면 그 자리는 봇이 이어받는다 (다음 라운드에도 봇이 채움)
##   - 같은 팀끼리도 밀칠 수 있다 (팀킬 가능)

const MAX_TEAMS := 4
const MODES := [0, 2, 3, 4]
const NAMES := ["레드팀", "블루팀", "그린팀", "옐로팀"]
const SHORT := ["레드", "블루", "그린", "옐로"]
const COLORS: Array[Color] = [
    Color(0.90, 0.22, 0.27), Color(0.24, 0.47, 0.78), Color(0.30, 0.66, 0.30), Color(1.0, 0.74, 0.05),
]


static func team_name(i: int) -> String:
    return NAMES[i] if i >= 0 and i < NAMES.size() else ""


static func color(i: int) -> Color:
    return COLORS[i] if i >= 0 and i < COLORS.size() else Color.WHITE


## 최대 인원을 팀 수의 배수로 맞춤 (2팀 → 2·4·6…, 3팀 → 3·6·9…). up: 배수가 아니면 올림 우선
## members(지금 인원)보다 적게는 줄이지 않는다. 배수로 못 맞추면 원래 값
static func fit_max(want: int, teams: int, members: int, cap: int, up: bool = true) -> int:
    var lo := maxi(2, members)
    var m := clampi(want, lo, cap)
    if teams < 2 or m % teams == 0:
        return m
    var hi_v := m + (teams - m % teams)
    var lo_v := m - m % teams
    if up and hi_v <= cap:
        return hi_v
    if lo_v >= lo and lo_v >= teams:
        return lo_v
    if hi_v <= cap:
        return hi_v
    return m


static func mode_name(teams: int) -> String:
    return "개인전" if teams <= 1 else "%d팀전" % teams


## 팀별 사람 수 (members: 방 정보의 members, 각 항목에 team)
static func counts(members: Array, teams: int) -> Array:
    var c := []
    c.resize(teams)
    c.fill(0)
    for m in members:
        var t := int(m.get("team", 0))
        if t >= 0 and t < teams:
            c[t] += 1
    return c


## 한 팀의 인원 (봇 채우기면 최대 인원 / 팀 수, 아니면 사람 수가 가장 많은 팀 기준)
static func team_size(room: Dictionary) -> int:
    var teams := int(room.get("teams", 0))
    if teams < 2:
        return 0
    if bool(room.get("bot_fill", false)):
        return int(room.get("max", 0)) / teams
    var mx := 0
    for n in counts(room.get("members", []), teams):
        mx = maxi(mx, n)
    return mx


## 시작할 수 없는 이유 ("" = 시작 가능)
static func block_reason(room: Dictionary) -> String:
    var teams := int(room.get("teams", 0))
    if teams < 2:
        return ""
    var c := counts(room.get("members", []), teams)
    if bool(room.get("bot_fill", false)):
        var mx := int(room.get("max", 0))
        if mx % teams != 0:
            return "최대 인원(%d명)이 %d팀으로 똑같이 나누어지지 않아요" % [mx, teams]
        var size := mx / teams
        for i in teams:
            if c[i] > size:
                return "%s 인원이 너무 많아요 (팀당 %d명)" % [team_name(i), size]
        return ""
    for i in teams:
        if c[i] != c[0] or c[i] == 0:
            return "팀 인원이 같아야 시작할 수 있어요 (%s)" % " : ".join(PackedStringArray(c.map(func(n): return str(n))))
    return ""


## 사람이 가장 적은 팀 (새로 들어온 사람 배정용)
static func smallest(members: Array, teams: int) -> int:
    var c := counts(members, teams)
    var best := 0
    for i in teams:
        if c[i] < c[best]:
            best = i
    return best
