# Small Party World — 캐주얼 파티 게임 모음

여러 캐주얼 미니게임을 모아 둔 온라인 파티 게임. 대기룸에서 방장이 할 게임을 고른다.
게임은 `games/<게임id>/` 폴더 단위 모듈로 관리한다 (아래 "게임 모듈" 참고).

현재 수록 게임
- **3D 돌피하기** (`games/rock_dodge`) — 떨어지는 돌을 피하고 상대를 밀쳐 마지막까지 살아남기


## 실행
Godot 4.7.2 (서버·웹 빌더 이미지도 4.7.2), Forward+ 렌더러, F5 → 접속 화면.
- **오프라인 연습**: 접속 화면의 "오프라인 연습" 버튼 (게임이 여러 개면 목록에서 선택, 봇과 대결, R 재시작, 끝나면 Enter로 메인)

## 온라인 (로비/방) — 진행 단계
| 단계 | 상태 |
|---|---|
| 1. 접속 + 닉네임 | 완료 |
| 2. 로비 (방 목록·방 만들기·입장) | 완료 |
| 3. 방 (레디·설정·강퇴·방장 위임·채팅·시작) | 완료 |
| 4. 게임 동기화 (서버 판정 + 내 캐릭터 즉시 이동) | 완료 — 아래 "게임 동기화" |
| 5. 배포 (홈서버 Docker + Caddy) | 설정 파일 준비 완료 (Dockerfile, docker-compose.yml, deploy/Caddyfile.example) |

### 게임 동기화
서버가 방마다 경기를 직접 돌린다 (`Net` 아래 SubViewport, 방마다 독립 물리 공간). 아이스딩과 같은 계열의 방식:

| 항목 | 누가 정하나 | 방법 |
|---|---|---|
| 내 캐릭터 이동·점프·차징·돌진 | 내 PC | 즉시 반응. 상태를 초당 30회 서버로 전송 (서버는 속도 상한 검사) |
| 다른 캐릭터 모습 | 서버 → 모두 | 초당 20회 상태 전송, 받는 쪽은 약 0.1초 늦춰 보간 |
| 낙석·아이템·바람 생성 | 서버 | 생성 시각(서버 시계)과 궤적을 방송 → 모든 PC에서 같은 순간 같은 위치 |
| 낙석 사망·헬멧 | 서버 | 내가 보낸 "그 시각의 내 위치"로 판정 (내 화면에서 피했으면 피한 것) |
| 밀치기 | 미는 사람 PC가 맞힘을 알림 → 서버 검증 | 서버가 최근 1초 위치 기록으로 되감아 확인(최대 0.6초) 후 상대 PC에 넉백 전달 |
| 회전 기둥 | 각자 자기 캐릭터 | 각도가 경과 시간으로 정해져 모든 PC에서 같음 |
| 봇 | 서버 | 서버에서 AI·물리로 움직임 |
| 아이템 획득·사망·승패·킬 | 서버 | 결과를 방송 |

- 시계: 클라이언트가 접속 중 계속 ping → 서버 시계 추정 (`Net.server_now()`)
- 메시지 통로: 게임 모듈은 `c_game`/`s_game`(확실 전달), `c_game_u`/`s_game_u`(상태용) 을 쓴다. 내용은 모듈이 정한다
- 경기 도중 방으로 나가거나 접속이 끊기면 기권(탈락)
- 서버 디버그 로그: 환경변수 `SPW_DEBUG=1` (밀치기 승인/거부 사유 출력)
- 측정(이 개발 환경, 로컬 지연 7ms): 다른 캐릭터는 약 0.1초 늦게 보이고 그 기준 위치 오차 평균 2.5cm. 서버 CPU는 경기 1개(4명)당 코어 1개의 약 11%
- 1:1로 시작한 경기는 탈락 압박(낙석 폭증)이 없음 (원래 "2명 남음" 규칙이 시작부터 걸리던 문제 수정)

### 통신
WebSocket. 서버는 컨테이너 안에서 평문 `ws://:7777`, 외부는 Caddy가 `wss://spwsv.cloudish.cloud`(443)로 받아 전달.
접속 화면의 기본 주소는 `wss://spwsv.cloudish.cloud` (`net.gd` `DEFAULT_SERVER`).

### 서버 목록 (접속 화면)
접속 화면에는 서버 **이름만** 보이고 주소는 노출하지 않습니다. 목록은 `scripts/net/net.gd` 의 `SERVER_LIST` 에서 관리:
```gdscript
const SERVER_LIST := [
    {"name": "서버 1", "url": DEFAULT_SERVER},
    # {"name": "서버 2", "url": "wss://다른서버주소"},
]
```
에디터 실행·디버그 빌드에서만 "로컬 테스트 (이 PC)" 항목과 "이 PC에서 서버 열고 접속" 버튼이 보이고, 릴리스·웹 빌드에서는 숨겨집니다.

### 도메인
| 도메인 | 용도 |
|---|---|
| `spwsv.cloudish.cloud` | 게임 서버(중계 서버). 게임 접속(wss) + 브라우저로 열면 서버 상태 페이지 |
| `spw.cloudish.cloud` | 웹 게임 플레이 페이지 (Godot 웹 빌드 파일 제공) |
주소 칸 입력 규칙: 도메인 → `wss://도메인`, IP/localhost → `ws://IP:포트`(기본 7777), `ws://`·`wss://`는 그대로.

### 홈서버 배포 (Ubuntu + Docker Compose + Caddy)
1. 이 프로젝트 폴더를 홈서버로 복사 (git 또는 scp)
2. 프로젝트 폴더에서 빌드·실행
   ```bash
   docker compose up -d --build
   docker compose logs -f              # "[server] 대기 중 — 포트 7777" 확인
   curl http://127.0.0.1:7778/health   # "ok" 가 나오면 서버 정상
   docker ps                           # STATUS 에 (healthy) 표시
   ```
3. Caddy 설정 추가 — `deploy/Caddyfile.example` 참고
   - Caddy를 Ubuntu에 직접 설치: `reverse_proxy 127.0.0.1:7777` (compose 기본값 그대로)
   - Caddy도 Docker: compose의 `ports` 대신 Caddy와 같은 네트워크에 연결하고 `reverse_proxy small-party-world-server:7777`
   - 반영: `sudo systemctl reload caddy` 또는 `docker exec <caddy> caddy reload --config /etc/caddy/Caddyfile`
4. 브라우저로 `https://spwsv.cloudish.cloud` 열기 → **서버 상태 페이지**(접속자·방 목록)가 보이면 Caddy 연결 정상
5. 게임 클라이언트에서 기본 주소(`wss://spwsv.cloudish.cloud`)로 접속
   웹 게임 페이지(`spw.cloudish.cloud`)는 웹 빌드 전까지 `deploy/web-placeholder/index.html`을 `/srv/small_party_world/web/`에 넣어 두기
6. 업데이트: 코드 변경 후 `docker compose up -d --build`

### 서버가 예전 버전일 때 (접속 후 무한 로딩·상태 페이지가 casual_games)
상태 페이지(`https://spwsv.cloudish.cloud`)의 이름·Godot 버전·프로토콜 버전으로 서버 버전을 확인할 수 있다.
정상: `Small Party World` · `Godot 4.7.2` · `프로토콜 v3` (`net.gd` `PROTOCOL_VERSION`)
```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'   # 7777/7778 을 쥔 컨테이너 확인
docker rm -f <예전 컨테이너 이름>        # 예전 casual_games 서버가 남아 있으면 제거
cd <홈서버의 spw 폴더>                   # 최신 코드로 갱신(git pull 또는 복사) 후
docker compose up -d --build
curl -s http://127.0.0.1:7778/status.json   # "game":"Small Party World", "godot":"4.7.2…", "protocol":3
docker compose --profile build run --rm web-build   # 웹 게임도 같은 버전으로
```
클라이언트와 서버의 프로토콜 버전이 다르면 로그인 단계에서 안내 문구가 뜨고, 서버가 아예 예전 형식이면 6초 뒤 "응답 없음"으로 끝난다.

### 빌드·배포
| 대상 | 방법 | 결과 |
|---|---|---|
| **웹** (spw.cloudish.cloud) | 홈서버 프로젝트 폴더에서 `docker compose --profile build run --rm web-build` | `/srv/small_party_world/web/` 교체 → 브라우저 새로고침 |
| (위 명령에 Windows 포함) | 기본으로 함께 만듦. 웹만: `-e BUILD_WINDOWS=0` | `https://spw.cloudish.cloud/download/SmallPartyWorld-windows.zip` (exe + pck, 압축 풀고 실행) |
| 게임 서버 | `docker compose up -d --build` | 컨테이너 재시작 |
| PC에서 직접 | 에디터 **프로젝트 → 내보내기** (Web / Windows / Linux 프리셋 준비됨, 결과는 `build/`) | 템플릿 필요: 에디터 → 내보내기 템플릿 관리 → 다운로드 |

웹 빌더 이미지는 첫 빌드 때 Godot와 내보내기 템플릿(약 1.3GB)을 받아 두고, 이후엔 재사용합니다.
업데이트 흐름: 코드 수정 → `git push` → 홈서버에서 `git pull` → 서버 `docker compose up -d --build` + 웹 `docker compose --profile build run --rm web-build`.

### 모바일 (휴대폰·태블릿 웹)
- 휴대폰·태블릿(안드로이드/iOS 웹, iPad, 모바일 앱)에서만 터치 컨트롤이 켜짐 (터치스크린 노트북은 마우스 조작 유지)
  - 왼쪽 화면: 이동 스틱 (누른 자리에 생김) · 오른쪽 화면 드래그: 시점 · 오른쪽 아래: 점프 / 밀치기(길게: 차징, 버튼 둘레에 차징·쿨타임 표시)
  - 결과 화면: 방으로 돌아가기 / 다시 하기 / 메인으로 버튼
- 입력 칸을 누르면 휴대폰 키보드가 열림 (웹 내보내기 옵션 `html/experimental_virtual_keyboard`)
- 세로 화면이면 "가로로 돌려 주세요" 안내
- 구현: `scripts/ui/touch_controls.gd`, `scripts/ui/rotate_hint.gd`, `Fighter.touch_device()`

웹 빌드 참고
- 웹은 Compatibility(WebGL2) 렌더러로 실행 (볼류메트릭 안개·SSAO 없음), 풀 밀도는 자동으로 낮춤
- 단일 스레드 빌드라 COOP/COEP 헤더 불필요
- 엔진 파일(index.wasm)이 약 40MB → Caddy `encode zstd gzip` 으로 전송 시 약 10MB
- 한글 글꼴: `fonts/Pretendard-SemiBold.otf` 포함 (SIL OFL 1.1, `fonts/Pretendard-LICENSE.txt`). 웹에는 시스템 글꼴이 없어서 포함하지 않으면 한글이 □로 깨짐

### 이름·도메인 변경 반영 (기존 casual_games 서버에서 옮기기)
```bash
# 1) 기존 서버 내리기 (기존 casual_games 폴더에서) — 7777 포트를 비워야 새 서버가 뜸
docker compose down
# 2) 새 폴더(spw)에서 올리기
docker compose up -d --build
curl http://127.0.0.1:7778/health          # ok
# 3) 웹 페이지 임시 파일
sudo mkdir -p /srv/small_party_world/web
sudo cp deploy/web-placeholder/index.html /srv/small_party_world/web/
# 4) Caddyfile: 기존 spw.cloudish.cloud 블록을 deploy/Caddyfile.example 의 두 블록으로 교체 후 reload
```
DNS에 `spwsv.cloudish.cloud` 레코드가 없다면(와일드카드 미사용) 먼저 추가해야 Caddy가 인증서를 받을 수 있습니다.

### 상태 페이지 / 헬스체크 (포트 7778)
| 경로 | 내용 |
|---|---|
| `/` | 서버 상태 화면 (접속 수, 로그인 수, 방 목록, 가동 시간, 10초마다 새로고침) |
| `/health` | `ok` (Docker 헬스체크용) |
| `/status.json` | 같은 정보를 JSON으로 |

게임 접속 포트(7777)는 WebSocket 전용이라 브라우저로 열면 아무것도 안 뜨는 것이 정상입니다.

### 로컬 테스트 서버
- 명령줄: `godot --headless --path <프로젝트 폴더> -- --server --port 7777`
- 또는 접속 화면의 **"이 PC에서 서버 열고 접속 (테스트)"** 버튼 (헤드리스 서버 프로세스를 띄움, 창을 닫으면 종료)

### 한 PC에서 여러 명 테스트
에디터 메뉴 **디버그 → 실행 인스턴스 사용자 지정(Customize Run Instances)** 에서 인스턴스 수를 2~3으로 → F5.
첫 창에서 "이 PC에서 서버 열고 접속", 나머지 창은 주소 칸에 `127.0.0.1:7777`을 넣고 "접속하기".
(홈서버에 배포한 뒤에는 모두 기본 주소로 접속하면 됩니다.)

### 규칙
- 닉네임 2~12자 (한글/영문/숫자/_-.), 중복 불가
- 방: 이름 최대 20자, 게임 선택, 최대 인원(게임별 범위, 돌피하기 2~12명, 현재 인원보다 적게 줄일 수 없음), 빈 자리 봇 채우기
- 방장은 대기룸에서 게임을 바꿀 수 있음 (바꾸면 레디 초기화, 인원 상한·봇 지원 여부는 게임 설정을 따름)
- 방장은 레디 불필요. 다른 참가자가 모두 레디해야 시작 가능.
  봇 채우기가 꺼져 있으면 게임별 최소 인원 필요 (`module.gd` `min_players`)
- 방장이 나가면 가장 먼저 들어온 사람이 방장, 마지막 사람이 나가면 방 삭제
- 게임 후 모두 방으로 돌아오면 다시 대기 상태(레디 초기화)

---

# 3D 돌피하기 (`games/rock_dodge`)

## 조작
| 입력 | 동작 |
|---|---|
| WASD | 이동 |
| 마우스 | 시점 (캐릭터가 카메라 방향을 바라봄) |
| Space | 점프 |
| 좌클릭 / E 짧게 | 제자리 밀치기 (쿨타임 0.3초) |
| 좌클릭 / E 길게 | 차징 — 이동 감속 + 바닥 화살표(길이 = 돌진 거리). 떼면 돌진하며 밀쳐냄. **점프하면 취소(쿨타임 없음), 공중에서는 밀치기 불가** |
| R | 재시작 |
| Esc | 마우스 해제 (클릭으로 복귀) |

## 규칙
- **낙석**: 바닥의 원이 착지 지점과 위험 범위. 노랑 → 빨강으로 차오르고 직전에 깜빡임. 닿으면 즉사
- **낙석 위치**: 아레나 전체에 균등 랜덤 (`rock_dodge_game.gd` `target_player_ratio`로 캐릭터 조준 비율 조절 가능)
- **바람**: 5~9초마다 풍향·풍속이 바뀜. 돌은 생성 순간의 바람을 받아 사선 직선으로 떨어짐
  (우상단 나침반 = 카메라 기준 풍향, 풀과 바람 입자도 같은 방향으로 움직임)
- **밀치기**: 맞은 쪽은 넉백 + 경직(조작 불가). 밀려나는 거리는 탭·차징 모두 풀차징과 같고, 차징할수록 돌진 거리·경직·쿨타임 증가
  - 탭: 제자리 밀기(0.3초간 정지), 넉백 17(풀차징과 같음), 경직 0.45초, 쿨 0.3초
  - 차징: 돌진 1~3.5m 후 0.25~0.45초 제자리 정지, 넉백 17, 경직 0.8~1.8초, 쿨 0.6~1.8초
  - 풀차징(1.2초): 무적 1초 (낙석·밀치기 모두 무시)
- **회전 기둥**: 중앙 축을 중심으로 바닥에 누운 기둥(양쪽 팔)이 시계침처럼 회전. 점프로 넘어야 함.
  - 벽처럼 단단해서 어느 방향에서도 걸어서 통과 불가
  - 회전 진행 방향 쪽에서 닿으면 풀차징 밀치기와 같은 효과(넉백 17·경직 1.8초). 뒤쪽에서 닿으면 그냥 막힘
  - 밀려 날아가다 기둥에 부딪히면 아레나 벽과 똑같이 벽꽝(경직 1.5배)
  - 회전 속도는 난이도에 따라 0.35→0.6 rad/s
- **몸 충돌**: 캐릭터끼리 부딪히면 살짝 튕김
- **벽꽝**: 밀려서 벽(아레나 벽·회전 기둥)에 부딪히면 경직 1.5배
- **당구 연쇄**: 밀려 날아가던 캐릭터가 다른 캐릭터와 부딪히면 그 캐릭터도 날아감
- **맞밀치기**: 마주 보고 동시에 밀면 둘 다 크게 튕김 (풀차징 무적 상태면 일방적으로 이김)
- **킬 크레딧**: 내가 민 상대(연쇄 포함)가 3초 안에 낙석에 맞으면 내 킬

## 아이템 (2~3.5초마다 아레나에 등장, 최대 5개, 15초 후 소멸)
인원이 줄수록 등장 간격이 늘어남(2명 남으면 2배). 2명 남으면 무적 아이템은 나오지 않음.

| 아이템 | 효과 |
|---|---|
| 헬멧 | 낙석 1회 방어, 최대 2개 중첩 (안전모: 노랑 1개 / 빨강+흰 띠+2단 돔 2개) |
| 깃털 | 15초간 공중 점프 1회 추가 (등에 날개) |
| 무거운 신발 | 8초간 밀치기·연쇄·충돌에 안 밀림, 민 쪽이 튕겨남 |
| 무적 5초 / 무적 10초 | 낙석·밀치기 모두 무시 |
- **탈락 압박**: 남은 인원이 줄수록 낙석 빈도·동시 낙하 수· 2명 남으면 빈도 3.5배 (`rock_dodge_game.gd` `last_two_rate_mult`)
- **난이도**: 시작부터 초당 약 5.5개 낙석(인원 감소 전 기준), 90초에 걸쳐 초당 약 11개까지 빈도·크기·속도·풍속 증가, 이후 30초마다 빈도가 더 늘어나는 서든데스

## 수치 조정 위치
- 밀치기·이동: `scripts/character/fighter.gd` 상단 `@export`
- 아레나 크기·봇 수·난이도·바람·아이템: `games/rock_dodge/rock_dodge_game.gd` 상단 `@export`
- 회전 기둥: `games/rock_dodge/sweeper.gd` 상단
- 봇 반응 속도·공격성: `games/rock_dodge/bot_brain.gd` `_ready()`

---

# 게임 모듈

## 구조
```
scenes/app.tscn            메뉴 (시작 씬)
scenes/match.tscn          게임 판 — 월드(하늘·지형·풀)를 만들고 선택된 게임 모듈을 "Game" 노드로 붙임
scripts/core/
  party_game.gd            모든 게임의 공통 베이스 (class_name PartyGame)
                           상태(카운트다운/진행/종료), 참가 캐릭터 목록, 팝업 글자, 터치 UI, 메뉴 복귀·재시작,
                           온라인 역할(net_role: OFFLINE/CLIENT/SERVER)과 메시지 보내기
  fighter_sync.gd          캐릭터 상태 인코딩(12 float)·보간 도우미 (온라인 공용)
  game_module.gd           게임 모듈 설명(id, 표시 이름, 설명, 최소/최대 인원, 봇 지원, 게임 스크립트 경로)
  game_registry.gd         등록된 게임 목록 — 메뉴·로비·대기룸·서버가 여기서 게임을 찾음
scripts/world/             공용 월드: world.gd(match.tscn 스크립트), terrain, grass, toon, procedural
scripts/character/         공용 캐릭터: fighter.gd (이동·점프·밀치기·넉백·아이템 효과·2등신 외형)
scripts/net/net.gd         오토로드 Net: 로그인·로비·방(게임 선택 포함)·게임 시작
scripts/ui/                메뉴 UI, 터치 컨트롤, 세로 화면 안내
games/rock_dodge/          3D 돌피하기 모듈
  module.gd                모듈 설명
  rock_dodge_game.gd       게임 규칙 (extends PartyGame)
  rock.gd sweeper.gd item.gd bot_brain.gd hud.gd warning.gdshader
```

## 새 게임 추가 방법
1. `games/<id>/` 폴더를 만든다.
2. 게임 스크립트 작성: `extends PartyGame`. `_ready()`에서 아레나·캐릭터를 만들고
   `state` 를 `State.COUNTDOWN → PLAYING → ENDED` 로 진행한다. HUD를 만들 때 `add_common_ui(layer)`를 부르면 터치 UI가 붙는다.
   `online_match`(Net.match_config)에 방 정보·참가자·봇 수가 들어 있다.
   온라인 대응: 같은 스크립트가 서버(`is_server()`)와 클라이언트(`is_client()`)에서 돈다.
   서버는 `on_client_message(pid, msg)`, 클라이언트는 `Net.game_message` 로 메시지를 받는다 (돌피하기 모듈 참고).
3. `games/<id>/module.gd` 작성 (`extends "res://scripts/core/game_module.gd"`, `_init()`에서 id·이름·설명·인원·`game_script_path` 지정).
   **게임 스크립트를 preload 하지 말 것** — 레지스트리는 오토로드(Net)보다 먼저 컴파일되므로 경로 문자열만 둔다.
4. `scripts/core/game_registry.gd` 의 `MODULES` 에 `preload("res://games/<id>/module.gd")` 한 줄 추가.

이것만으로 접속 화면(오프라인 연습 목록), 방 만들기, 대기룸 게임 선택, 서버 검증·상태 페이지에 새 게임이 나타난다.

## 파일 구조 (그 밖)
| 파일 | 역할 |
|---|---|
| `scripts/ui/ui_kit.gd` | 메뉴 카툰풍 테마 (두꺼운 외곽선·그림자 버튼, 로고, 배지, 이미지 카드) |
| `fonts/BlackHanSans-Regular.ttf` | 제목·버튼 글꼴 (SIL OFL, 라이선스 동봉) |
| `ui/portraits/slot_N.png` | 대기룸 캐릭터 초상화 (슬롯 색 = 게임 안 색, `Fighter.SLOT_COLORS`) |
| `games/<id>/thumbnail.png` | 게임 카드 이미지 (`module.gd` `thumbnail_path`) |
| `tools/render_assets.gd`, `tools/render_thumbnail.gd` | 위 이미지 다시 만들기 (개발용, 빌드에서 제외) — `godot --rendering-method gl_compatibility --resolution 256x256 --path . -s tools/render_assets.gd` |
| `export_presets.cfg` | 내보내기 프리셋 (Web, Windows, Linux) |
| `deploy/web-build/` | 홈서버용 웹 빌더 (Dockerfile, build.sh) |
| `shaders/arena_wall.gdshader` | 반투명 경계 벽 (가까이 가면 진해짐) |
| 그 외 셰이더 | 툰 라이팅, 지형, 풀, 하늘 |
