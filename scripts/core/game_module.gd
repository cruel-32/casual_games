extends RefCounted
## 게임 모듈 정보 (각 게임 폴더의 module.gd 가 상속)
##
## 새 게임 추가 방법
##   1. games/<게임id>/ 폴더 생성
##   2. 게임 스크립트: PartyGame 을 상속 (scripts/core/party_game.gd)
##   3. games/<게임id>/module.gd: 이 파일을 상속해 _init() 에서 정보 채우기
##   4. scripts/core/game_registry.gd 의 MODULES 에 module.gd 한 줄 추가
##   5. 경기가 끝나면 서버에서 report_result(placements) 로 순위를 알린다 (PartyGame.report_result)
##      → 라운드 승점(1등 3·2등 2·3등 1)과 여러 라운드 합계는 scripts/core/series.gd 가 처리
##      팀 게임은 한 순위 항목에 팀원 전부를 넣는다
##
## 서버(로비)도 이 정보를 읽으므로, 이 파일과 module.gd 에서는 게임 스크립트를 preload 하지 않는다
## (게임 스크립트는 경기를 시작할 때 create_game() 에서 불러온다).

var id := ""                    # 고유 ID (방 설정·네트워크에 저장되는 값, 바꾸지 말 것)
var display_name := ""          # 화면 표시 이름
var description := ""           # 방 화면에 보여줄 한 줄 설명
var min_players := 2            # 봇 채우기 없이 시작하려면 필요한 최소 인원
var max_players := 12
var supports_bots := true       # 빈 자리 봇 채우기 가능 여부
var supports_teams := false     # 팀전(2~4팀) 지원 여부 — 팀 순위로 report_result 해야 함
var game_script_path := ""      # PartyGame 을 상속한 게임 스크립트 경로
var thumbnail_path := ""        # 메뉴의 게임 카드 이미지 (16:9 권장, 없으면 색 카드)
var accent := Color(0.2, 0.55, 0.95)   # 게임 카드 강조 색


## 썸네일 텍스처 (없으면 null). 서버(헤드리스)에서도 안전
func thumbnail() -> Texture2D:
    if thumbnail_path == "" or not ResourceLoader.exists(thumbnail_path):
        return null
    return load(thumbnail_path)


func create_game() -> Node3D:
    var game: Node3D = load(game_script_path).new()
    game.set("module_id", id)
    return game
