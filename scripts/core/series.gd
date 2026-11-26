extends RefCounted
## 여러 라운드 경기 (시리즈) 규칙 — 서버가 점수를 계산하고, 방 정보(room.series)로 모두에게 알린다
##
## - 방장이 라운드 수(1~5)와 라운드별 게임(같은 게임 여러 번 / 랜덤)을 정한다
## - 라운드 승점: 1등 3점 · 2등 2점 · 3등 1점 (모든 게임 동일). 팀 게임은 순위가 팀 단위이고 팀원 모두가 그 점수를 받는다
## - 동점(같은 순위)은 같은 점수. 모든 라운드가 끝나면 합계가 가장 높은 사람이 우승 (같으면 공동 우승)
##
## 게임 모듈은 경기가 끝나면 서버에서 PartyGame.report_result(placements) 를 부른다.
##   placements = [ {"rank": 1, "members": [{"key": "p:123", "name": "철수", "bot": false}], "team": ""}, ... ]
##   key: 사람 "p:<접속 id>", 봇 "b:<이름>" (라운드가 바뀌어도 같은 봇은 같은 이름)

const GameRegistry := preload("res://scripts/core/game_registry.gd")

const POINTS := [3, 2, 1]
const MIN_ROUNDS := 1
const MAX_ROUNDS := 5
const RANDOM := "random"
const BETWEEN_SEC := 30.0          ## 라운드 사이: 모두 레디하거나 이 시간이 지나면 다음 라운드


static func points_for_rank(rank: int) -> int:
    return POINTS[rank - 1] if rank >= 1 and rank <= POINTS.size() else 0


## 새 시리즈 (서버)
static func create(total: int, participants: Array) -> Dictionary:
    return {
        "round": 0,
        "total": clampi(total, MIN_ROUNDS, MAX_ROUNDS),
        "phase": "starting",           # playing · between · final
        "game": "",                     # 지금 라운드 게임 id
        "games": [],                    # 지금까지 한 게임 id (라운드 순)
        "participants": participants.duplicate(),
        "scores": {},                   # key -> {name, points, bot}
        "last": {},                     # 마지막 라운드 결과 {round, game, rows: [{rank, team, names, points}]}
        "ready": {},                    # pid -> true (라운드 사이 레디)
        "next_at": 0.0,                 # 서버 시각: 이때 다음 라운드 자동 시작
    }


## 라운드 결과 반영 → 마지막 라운드면 phase = final
static func apply_result(s: Dictionary, placements: Array) -> void:
    var rows := []
    for p in placements:
        var rank := int(p.get("rank", 99))
        var pts := points_for_rank(rank)
        var names := PackedStringArray()
        for m in p.get("members", []):
            var key := String(m.get("key", ""))
            if key == "":
                continue
            names.append(String(m.get("name", "?")))
            var e: Dictionary = s.scores.get(key, {"name": String(m.get("name", "?")), "points": 0, "bot": bool(m.get("bot", false))})
            e.points = int(e.points) + pts
            e.name = String(m.get("name", e.name))
            s.scores[key] = e
        rows.append({"rank": rank, "team": String(p.get("team", "")), "names": ", ".join(names), "points": pts})
    rows.sort_custom(func(a, b): return a.rank < b.rank)
    s.last = {"round": s.round, "game": s.game, "rows": rows}
    s.phase = "final" if int(s.round) >= int(s.total) else "between"
    s.ready = {}


## 합계 순위표 [{key, name, points, bot, rank}] (동점은 같은 순위)
static func standings(s: Dictionary) -> Array:
    var out := []
    for key in s.get("scores", {}):
        var e: Dictionary = s.scores[key]
        out.append({"key": key, "name": e.name, "points": int(e.points), "bot": bool(e.get("bot", false))})
    out.sort_custom(func(a, b): return a.points > b.points if a.points != b.points else a.name < b.name)
    var rank := 0
    var prev := -1
    for i in out.size():
        if out[i].points != prev:
            rank = i + 1
            prev = out[i].points
        out[i]["rank"] = rank
    return out


## 우승자 이름들 (공동 우승 포함)
static func winners(s: Dictionary) -> PackedStringArray:
    var names := PackedStringArray()
    for e in standings(s):
        if e.rank == 1 and e.points > 0:
            names.append(e.name)
    return names


## 라운드 게임 고르기. 랜덤이면 지금 인원으로 할 수 있는 게임 중 하나
static func resolve_game(choice: String, players: int, bot_fill: bool, teams: int = 0) -> String:
    if choice != RANDOM:
        return GameRegistry.get_or_default(choice).id
    var pool := []
    for m in GameRegistry.all():
        if teams >= 2 and not m.supports_teams:
            continue
        if players >= m.min_players or (bot_fill and m.supports_bots):
            pool.append(m.id)
    if pool.is_empty():
        return GameRegistry.default_id()
    return pool[randi() % pool.size()]


## 라운드 설정에 들어갈 수 있는 게임 id 인지 ("random" 포함)
static func is_valid_choice(id: String) -> bool:
    return id == RANDOM or GameRegistry.find(id) != null


## 라운드 설정으로 정해지는 최대 인원 (랜덤이면 모든 게임 기준)
static func max_players_for(round_games: Array) -> int:
    var mx := 999
    for g in round_games:
        if g == RANDOM:
            for m in GameRegistry.all():
                mx = mini(mx, m.max_players)
        else:
            mx = mini(mx, GameRegistry.get_or_default(String(g)).max_players)
    return mx


## 화면 표시용 이름
static func choice_name(id: String) -> String:
    return "랜덤" if id == RANDOM else GameRegistry.display_name(id)
