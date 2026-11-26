# Small Party World — 캐주얼 파티 게임 모음

여러 캐주얼 미니게임을 모아 둔 온라인 파티 게임. 대기룸에서 방장이 할 게임을 고른다.
게임은 `games/<게임id>/` 폴더 단위 모듈로 관리한다 (아래 "게임 모듈" 참고).

현재 수록 게임
- **3D 돌피하기** (`games/rock_dodge`) — 떨어지는 돌을 피하고 상대를 밀쳐 마지막까지 살아남기


## 실행
Godot 4.7.1 (서버·웹 빌더 이미지도 4.7.1 — 4.7.2는 Windows 한글 입력 버그(godot#123269)가 있어 4.7.3 출시 전까지 4.7.1 고정), Forward+ 렌더러, F5 → 접속 화면.
- **오프라인 연습**: 접속 화면의 "오프라인 연습" 버튼 (게임이 여러 개면 목록에서 선택, 봇과 대결, R 재시작, 끝나면 화면의 "다시 하기"/"메인으로" 버튼)

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
| `spw.cloudish.cloud` | 안내 페이지 — PC(Windows)는 PC 버전 다운로드, 모바일은 앱 설치로 유도 (`deploy/web-landing`) |
| `spw.cloudish.cloud/play/` | 웹 체험판 (Godot 웹 빌드). 게임 첫 화면 오른쪽 위에도 PC 버전/앱 안내 카드 |
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

### 여러 라운드 경기 (시리즈)
- 방장이 대기룸에서 **라운드 수(1~5)** 와 **라운드별 게임**(같은 게임 여러 번 가능, "랜덤" 가능)을 정한다
- 게임을 시작하면 1라운드 → 끝나면 결과 화면에서 **다음 라운드 레디** (모두 레디하거나 30초 지나면 다음 라운드 자동 시작)
- 라운드 승점: **1등 3점 · 2등 2점 · 3등 1점** (모든 게임 동일, 동점은 같은 점수). 팀 게임은 팀 순위로 팀원 모두가 같은 점수
- 마지막 라운드가 끝나면 합계 1위가 최종 우승(같으면 공동 우승) → "방으로 돌아가기"
- 결과 화면에서 "방으로 나가기"를 누르면 남은 라운드에서 빠진다
- 서버 규칙: `scripts/core/series.gd`, 결과 화면: `scripts/ui/series_panel.gd`
- 새 게임은 경기가 끝날 때 서버에서 `report_result(placements)` 를 부르기만 하면 된다 (`scripts/core/party_game.gd`)

### 팀전
- 방장이 대기룸에서 **개인전(1:1:1…) / 2팀전 / 3팀전 / 4팀전** 을 고른다. 팀을 정하면 사람들이 팀에 고르게 나뉘고, 각자 카드의 "→ 팀" 버튼으로 바꾼다 (방장은 다른 사람도 옮길 수 있음)
- 팀끼리 인원이 맞아야 시작: 봇 채우기를 끄면 팀별 사람 수가 같아야 하고, 켜면 최대 인원이 팀 수로 나누어떨어져야 하며 빈자리는 봇이 채운다
- 팀 수를 바꾸면 최대 인원이 팀 수의 배수로 자동 조정 (`Teams.fit_max`, 올림 우선·게임 최대 넘으면 내림. 예: 5명 → 2팀 6명, 4팀 8명). 대기룸 인원 칸도 팀 수 단위로만 바뀜
- 경기 도중 누가 나가면 그 캐릭터를 봇이 이어받고, 다음 라운드에도 그 자리는 봇이 채운다
- 같은 팀끼리도 밀칠 수 있다 (팀킬). 팀킬은 킬 수에 들어가지 않는다. 봇은 같은 팀을 노리지 않는다
- 팀 순위는 팀원이 마지막까지 남아 있던 시각 순. 팀원 모두가 팀 순위 점수(3/2/1)를 받는다
- 규칙: `scripts/core/teams.gd`. 새 게임이 팀전을 지원하면 module.gd 에 `supports_teams = true`

### 버전 관리·업데이트
버전은 저장소 맨 위의 `release.json` 한 곳에서 관리한다.

```json
{ "version": "0.2.0", "min_supported": "0.2.0", "pc_full_required": false, "notes": ["바뀐 점", "..."] }
```

- **새 버전 내기**: `version` 을 올리고 `notes` 를 쓴 뒤 `main` 에 푸시 → CI 가 `https://spw.cloudish.cloud/version.json` 을 갱신
  - 게임은 켤 때 이 파일을 읽어 첫 화면에 "새 버전" 카드와 업데이트 버튼을 띄운다
  - 같은 `version` 으로 다시 푸시하면 이미 받은 사람에게는 다시 내려가지 않는다 → 배포할 때마다 버전을 올릴 것
- **PC 앱**: 업데이트 버튼 → 업데이트 팩(`/download/updates/game-<버전>.pck`)을 받아 sha256·서명 확인 → 다시 시작하면 적용
  (`scripts/core/boot.gd` 가 다른 스크립트보다 먼저 팩을 불러옴)
  - Godot 버전을 바꿨거나 `project.godot`(자동 로드·설정)·내보내기 설정을 바꿨으면 `"pc_full_required": true` → 전체 zip 을 받도록 안내
  - 서명 키: GitHub Secrets `PATCH_SIGNING_KEY` (RSA 개인 키 PEM). 공개 키는 `scripts/core/updater.gd` 의 `PUBLIC_KEY`. 키가 없으면 팩을 올리지 않고 전체 zip 안내
- **Android·iOS**: 스토어 정책상 앱이 스스로 코드를 바꾸면 안 되므로 버튼은 스토어(출시 전에는 APK) 페이지를 연다
- **웹**: 새로고침
- **최소 버전** `min_supported`: 이보다 낮은 게임은 서버가 로그인을 거절하고, 첫 화면도 업데이트를 안내한다 (혼자 연습은 가능).
  모바일 스토어 심사가 끝나기 전에는 올리지 말 것
- 서버·클라이언트 통신 형식이 바뀌면 `scripts/net/net.gd` 의 `PROTOCOL_VERSION` 도 올린다

### 관리 페이지·공지 (admin/)
`https://spw.cloudish.cloud/admin/` — 구글 계정으로 로그인, 등록된 계정만 사용 가능. Node 22 + 내장 SQLite, 의존성은 `jose` 하나.

| 주소 | 쓰는 곳 |
|---|---|
| `/admin/` | 관리 페이지: 공지(공지·배너·팝업·패치 노트), **신고·제재·금칙어**, 점검 모드, 관리자 계정, 작업 기록 |
| `/api/notices?platform=pc&version=0.2.0` | 게임 첫 화면(배너 띠·"소식" 창)과 웹 `/news/` |
| `/api/status` | 게임 서버가 15초마다 읽는 점검 모드 (켜지면 새 로그인·방 만들기 거절) |
| `/internal/reports` (POST) | 게임 서버 → 신고 접수 (방의 최근 채팅 40개 첨부). **Caddy 로 노출하지 않음** (프록시를 거친 요청은 거절) |
| `/internal/moderation` | 게임 서버가 15초마다 읽는 제재(기기 ID 기준 채팅 금지·접속 차단)와 추가 금칙어 |

#### 계정·로그인 (온라인 대전 필수, 혼자 연습은 로그인 없이)
- 게임 첫 화면 "계정" 줄의 구글·Apple 버튼 → 브라우저에서 로그인 → 게임이 `/api/auth/poll` 로 기다렸다가 토큰을 받음 (`user://account.cfg`)
- 게임 서버는 접속 때 토큰(`y_auth`)을 관리 서버 `/internal/account/verify` 로 확인. **ADMIN_URL 이 없는 로컬 테스트 서버는 로그인 없이 닉네임만**
- 저장하는 것: 제공자 이름 + 제공자 사용자 번호의 해시(`ACCOUNT_PEPPER`, 없으면 DB 에 자동 생성) + 무작위 계정 번호(12자리, 정보 창에 표시). 이메일·이름은 요청도 저장도 안 함
- 계정 삭제: 게임 정보 창 → 계정 삭제 (`DELETE /api/account`)
- 제공자 등록 (값을 넣은 제공자만 버튼이 보임). GitHub > Settings > Secrets and variables > Actions 에 등록 → 배포 때 docker compose 로 전달:

| 제공자 | 콘솔에서 할 일 | 넣을 값 |
|---|---|---|
| 구글 | Google Cloud Console > 사용자 인증 정보 > 기존 OAuth 웹 클라이언트(관리 페이지용)에 **승인된 리디렉션 URI** `https://spw.cloudish.cloud/api/auth/callback/google` 추가 | 변수 `GOOGLE_CLIENT_ID`(이미 있음), 비밀 `GOOGLE_CLIENT_SECRET` |
| Apple | Apple Developer(유료) > Identifiers > **Services ID** 만들고 Sign in with Apple 켜기, Return URL `https://spw.cloudish.cloud/api/auth/callback/apple`, Keys 에서 Sign in with Apple 키(.p8) 발급 | 비밀 `APPLE_SERVICE_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`(.p8 내용) |

> iOS 앱을 낼 때 다른 소셜 로그인이 있으면 Apple 로그인도 있어야 함 (App Review 4.8)

#### 운영 단계·하루 판수·광고 (정식 출시부터 적용, 베타는 전부 끔)
- 관리 페이지 **운영 정책** 탭: 단계(베타/정식 출시), 하루 무료 판수(기본 1), 광고 1번 보상(기본 1판), 하루 광고 보상 최대(기본 5)
- 판수: 방장이 게임을 시작할 때 게임 서버가 `/internal/plays/start` 로 방 안 모든 사람의 판을 1씩 차감 (1판 = 한 번 시작한 경기, 최대 5라운드). 남은 판이 없는 사람이 있으면 시작 거절. 광고 제거 계정은 제외
- 광고: 모든 플랫폼 보상형, **모바일 앱에서만** 볼 수 있음 (PC·웹 사용자도 같은 계정이면 모바일에서 보고 판수 +1)
  - SDK: Google AdMob + Godot 플러그인 **AdMob (Poing Studios, Android·iOS)**. `scripts/core/ads.gd` 의 `REWARDED_UNIT` 에 광고 단위 ID
  - 보상은 **AdMob 서버 확인(SSV)** 으로만 지급: AdMob 콘솔 > 보상형 광고 단위 > 서버 측 확인 URL `https://spw.cloudish.cloud/api/ads/ssv`, 광고를 띄울 때 `custom_data` = 계정 번호
  - 아직 할 일: AdMob 계정·앱·광고 단위 만들기 → 플러그인 설치(에디터 AssetLib "AdMob" by Poing Studios, Android 는 Gradle 빌드 사용) → `ads.gd` 연결
- 광고 제거 결제: 스토어 결제 연동 전까지 관리 페이지 운영 정책 탭 > 계정 찾기(계정 번호) > 광고 제거 켬

#### 채팅 안전 (App Store 1.2 · 이용약관 제6조)
- **금칙어**: `scripts/core/word_filter.gd` 기본 목록 + 관리 페이지에서 추가한 단어. 서버가 채팅은 `***`로 가리고, 닉네임은 거절, 방 이름은 가림.
  띄어쓰기·숫자·기호를 끼워도 걸러냄(두 글자 단어는 띄어쓰기는 건너뛰지 않음)
- **신고**: 대기룸 다른 사람 카드의 "신고" → 서버가 방의 최근 채팅과 함께 관리 서버로 전송 → 관리 페이지 "신고" 탭. **30일 지나면 자동 삭제**
- **차단**: 카드의 "차단" → 그 사람 채팅을 내 화면에서 숨김 (기기에만 저장, `uid` = 기기 ID 해시)
- **제재**: 관리 페이지에서 채팅 금지·접속 차단 (1시간~영구). 기기 ID(`user://device.cfg`, 처음 실행 때 무작위 생성) 기준. 접속 차단은 지금 접속 중이면 바로 내보냄

- 컨테이너 `small-party-world-admin` (127.0.0.1:7780), 데이터 `/srv/small_party_world/admin/admin.sqlite`
- `ADMIN_EMAILS`(docker-compose, 기본 `cshee8508@gmail.com`): 항상 관리자. 그 밖의 관리자는 관리 페이지에서 추가·삭제
- `GOOGLE_CLIENT_ID`: Google Cloud Console 의 OAuth 웹 클라이언트 ID (승인된 자바스크립트 원본 `https://spw.cloudish.cloud`).
  GitHub > Settings > Secrets and variables > Actions > **Variables** 에 `GOOGLE_CLIENT_ID` 로 등록하면 배포 때 들어감
- Caddy: `spw.cloudish.cloud` 블록에 `/admin*`, `/api/*` → 127.0.0.1:7780 (deploy/Caddyfile.example)
- 테스트: `cd admin && npm ci && npm test`

### 자동 빌드·배포 (GitHub Actions)
`main` 에 푸시하면 `.github/workflows/build-deploy.yml` 이 돈다. (GitHub > Actions 에서 수동 실행도 가능)

| 작업 | 어디서 | 하는 일 |
|---|---|---|
| deploy | 홈서버 (셀프 호스티드 러너, 라벨 `homeserver`) | 게임 서버 재빌드·재시작 → 웹(안내 페이지·체험판·Windows zip) 빌드·배포 → 상태 확인 |
| android | GitHub 리눅스 러너 (공개 저장소라 무료) | AAB 빌드 → Google Play **내부 테스트** 트랙 업로드 + 같은 키로 서명한 APK 빌드 |
| android-apk | 홈서버 | 그 APK 를 `https://spw.cloudish.cloud/download/SmallPartyWorld-android.apk` 에 게시 (폰에서 받아 바로 설치해 보는 용도, 안내 페이지에는 링크 없음) |
| iOS | (예정) 이 Mac 을 셀프 호스티드 러너로 | Apple 개발자 계정 재결제 후 TestFlight 업로드까지 |

**1) 홈서버 러너 설치 (한 번)**
1. GitHub 저장소 > Settings > Actions > Runners > New self-hosted runner > Linux — 나오는 명령을 홈서버에서 실행
2. `./config.sh` 에서 라벨을 물으면 `homeserver` 추가
3. 서비스로 등록: `sudo ./svc.sh install && sudo ./svc.sh start`
4. 러너 사용자가 docker 를 쓸 수 있게: `sudo usermod -aG docker <러너 사용자>` (그 후 서비스 재시작)
5. 저장소 > Settings > Actions > General > "Fork pull request workflows from outside collaborators" 를
   **Require approval for all outside collaborators** 로 (공개 저장소 보안). 워크플로는 main 푸시에만 반응한다
6. 기존 수동 명령(`~/spw` 에서 `docker compose …`)과 같은 프로젝트 이름(`spw`)을 쓰므로 섞어 써도 된다

**2) Android 업로드 준비 (한 번)**
1. 업로드 키 만들기 (분실하면 앱 업데이트 불가 — 안전하게 보관):
   `keytool -genkeypair -v -keystore spw-release.keystore -alias spw -keyalg RSA -keysize 2048 -validity 10000`
2. 저장소 > Settings > Secrets and variables > Actions 에 시크릿 추가
   - `ANDROID_KEYSTORE_BASE64` = `base64 -i spw-release.keystore` 결과
   - `ANDROID_KEY_ALIAS` = `spw`, `ANDROID_KEY_PASSWORD` = 키 비밀번호
3. 첫 AAB 는 Play Console 에서 직접 올린다 (Actions 실행 결과의 `android-aab` 아티팩트 다운로드 → 앱 만들기 → 내부 테스트에 업로드).
   패키지 이름 `cloud.cloudish.spw` — **첫 업로드 후에는 바꿀 수 없음** (`export_presets.cfg` Android 프리셋)
4. 자동 업로드: Google Cloud 서비스 계정 만들기 → Play Console > 사용자 및 권한에서 그 계정에 앱 권한 부여 →
   JSON 키를 시크릿 `PLAY_SERVICE_ACCOUNT_JSON` 에 넣기
5. 앱이 처음 검토를 통과하기 전에는 Play 가 "초안(draft)" 업로드만 허용한다. 통과 후 저장소 변수(Variables)
   `PLAY_RELEASE_STATUS` = `completed` 로 바꾸면 내부 테스트에 바로 배포된다
- 시크릿이 없으면 Android 작업은 경고만 남기고 건너뛴다
- 버전 코드는 Actions 실행 번호로 자동 증가, 버전 이름은 Android 프리셋의 `version/name`
- 개인 개발자 계정(2023-11-13 이후 생성)은 정식 출시 전에 12명 이상 · 14일 연속 비공개 테스트가 필요하다

**3) Google Play 스토어 출시 순서**
1. Play Console > 앱 만들기 — 앱 이름, 기본 언어(한국어), 게임, 무료
2. 대시보드 "앱 설정" 항목 채우기
   - 개인정보처리방침 URL (모든 앱 필수, 앱 안에도 링크 필요)
   - 앱 액세스(로그인 없음), 광고 여부, 콘텐츠 등급 설문, 타겟 연령층, 데이터 보안 양식(닉네임·접속 정보 처리 방식)
   - 스토어 등록정보: 짧은 설명, 자세한 설명, 아이콘 512×512, 그래픽 이미지 1024×500, 휴대전화 스크린샷 2장 이상
3. 테스트 > 내부 테스트 > 새 버전 > Actions 의 `android-aab` 를 업로드 (첫 업로드는 수동).
   이때 Play 앱 서명을 사용 — Google 이 배포 서명 키를 관리하고, 우리 키는 "업로드 키"가 된다
4. (개인 계정) 비공개 테스트 트랙에 12명 이상 테스터를 14일 연속 참여시킨 뒤 > 프로덕션 액세스 신청
5. 프로덕션 > 새 버전 만들기 > 검토 제출 → 승인되면 공개. 이후 업데이트는 Actions 가 올린 빌드를
   내부 테스트에서 확인한 뒤 Play Console 에서 "버전 승격"으로 비공개/프로덕션에 올린다
6. 출시 후 `deploy/web-landing/links.json` 의 `android` 에 스토어 주소(`https://play.google.com/store/apps/details?id=cloud.cloudish.spw`)를 넣고 푸시

**주의: 서버와 앱 버전.** 서버·웹은 푸시 즉시 바뀌지만 스토어 앱은 심사·업데이트가 늦다.
`net.gd` `PROTOCOL_VERSION` 을 올리는 변경은 이미 설치된 앱의 접속을 막으므로, 앱 출시 후에는 호환 유지 또는 강제 업데이트 안내가 필요하다.

### 서버가 예전 버전일 때 (접속 후 무한 로딩·상태 페이지가 casual_games)
상태 페이지(`https://spwsv.cloudish.cloud`)의 이름·Godot 버전·프로토콜 버전으로 서버 버전을 확인할 수 있다.
정상: `Small Party World` · `Godot 4.7.1` · `프로토콜 v4` (`net.gd` `PROTOCOL_VERSION`)
```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'   # 7777/7778 을 쥔 컨테이너 확인
docker rm -f <예전 컨테이너 이름>        # 예전 casual_games 서버가 남아 있으면 제거
cd <홈서버의 spw 폴더>                   # 최신 코드로 갱신(git pull 또는 복사) 후
docker compose up -d --build
curl -s http://127.0.0.1:7778/status.json   # "game":"Small Party World", "godot":"4.7.1…", "protocol":4
docker compose --profile build run --rm web-build   # 웹 게임도 같은 버전으로
```
클라이언트와 서버의 프로토콜 버전이 다르면 로그인 단계에서 안내 문구가 뜨고, 서버가 아예 예전 형식이면 6초 뒤 "응답 없음"으로 끝난다.

### 빌드·배포
| 대상 | 방법 | 결과 |
|---|---|---|
| **웹** (spw.cloudish.cloud) | 홈서버 프로젝트 폴더에서 `docker compose --profile build run --rm web-build` | `/srv/small_party_world/web/` 교체 → 브라우저 새로고침 |
| (위 명령에 Windows 포함) | 기본으로 함께 만듦. 웹만: `-e BUILD_WINDOWS=0` | `https://spw.cloudish.cloud/download/SmallPartyWorld-windows.zip` (exe + pck, 압축 풀고 실행) |
| 다운로드·앱 주소 | `deploy/web-landing/links.json` 수정 후 위 명령 다시 실행 | `windows` / `android` / `ios` — 앱 주소가 비어 있으면 "앱 준비 중" 표시 |
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
| WASD | 이동 — 캐릭터는 이동 방향을 바라봄 (밀치기도 바라보는 방향으로). 돌진·밀치기 직후 정지 중과 경직 중엔 방향이 안 바뀜 |
| 마우스 | 카메라만 회전 (방향키는 카메라 기준) |
| Space | 점프 |
| 좌클릭 / E 짧게 | 제자리 밀치기 (쿨타임 0.3초) |
| 좌클릭 / E 길게 | 차징 — 이동 감속 + 바닥 화살표(길이 = 돌진 거리). 떼면 바라보는 방향으로 돌진하며 밀쳐냄. 차징 중엔 발밑에 주황→빨강 고리(모두에게 보임). 돌진 화살표는 나에게만 보임 **점프해도 유지, 공중에서도 밀치기·차징 가능** (공중에서 맞아도 땅에서 맞은 것과 같은 넉백) |
| R | 재시작 |
| Esc | 마우스 해제 (클릭으로 복귀) |

## 규칙
- **낙석**: 바닥의 원이 착지 지점과 위험 범위. 노랑 → 빨강으로 차오르고 직전에 깜빡임. 닿으면 즉사
- **시작 보호**: 경기 시작 후 5초 동안은 캐릭터 주변(3m + 돌 반지름)에 낙석이 떨어지지 않음
- **낙석 위치**: 아레나 전체에 균등 랜덤 (`rock_dodge_game.gd` `target_player_ratio`로 캐릭터 조준 비율 조절 가능)
- **바람**: 5~9초마다 풍향·풍속이 바뀜. 돌은 생성 순간의 바람을 받아 사선 직선으로 떨어짐
  (우상단 나침반 = 카메라 기준 풍향, 풀과 바람 입자도 같은 방향으로 움직임)
- **밀치기**: 맞은 쪽은 넉백 + 경직(조작 불가). 밀려나는 거리는 탭·차징 모두 풀차징과 같고, 차징할수록 돌진 거리·경직·쿨타임 증가
  - 탭: 제자리 밀기(0.3초간 정지, 사거리 2.5m), 넉백 9, 경직 0.25초, 쿨 0.3초
  - 차징: 돌진 1.9~6.8m, 넉백 12~20, 경직 0.8~1.5초, 쿨 0.6~1.8초. 돌진 후 제자리 정지: 맞히면 0.25~0.45초, **헛치면 0.4~0.7초**
  - 경직 상한 1.5초 (글러브·벽꽝 포함). 경직이 풀린 뒤 0.5초는 다시 경직되지 않음 (넉백만 받음)
  - 풀차징(1.2초, 차징 가속 아이템으로 단축): 가장 멀리 돌진. 무적은 없음 (무적은 무적 아이템으로만)
- **회전 기둥**: 중앙 축을 중심으로 바닥에 누운 기둥(양쪽 팔)이 시계침처럼 회전. 점프로 넘어야 함.
  - 벽처럼 단단해서 어느 방향에서도 걸어서 통과 불가
  - 회전 진행 방향 쪽에서 닿으면 강하게 밀림(넉백 17·경직 1.5초). 뒤쪽에서 닿으면 그냥 막힘
  - 밀려 날아가다 기둥에 부딪히면 아레나 벽과 똑같이 벽꽝(경직 1.5배)
  - 회전 속도는 난이도에 따라 0.35→0.6 rad/s
- **몸 충돌**: 캐릭터끼리 부딪히면 살짝 튕김
- **벽꽝**: 밀려서 벽(아레나 벽·회전 기둥)에 부딪히면 경직 1.5배
- **당구 연쇄**: 밀려 날아가던 캐릭터가 다른 캐릭터와 부딪히면 그 캐릭터도 날아감
- **맞밀치기**: 마주 보고 동시에 밀면 둘 다 크게 튕김 (무적 상태면 일방적으로 이김)
- **킬 크레딧**: 내가 민 상대(연쇄 포함)가 3초 안에 낙석에 맞으면 내 킬
- **관전**: 탈락하면 1초 뒤 나를 떨어뜨린 사람(없으면 다른 생존자) 시점으로 바뀜. 화면 아래 ◀ ▶ 버튼(키보드 ← →)으로 다른 생존자 시점 선택. 경기가 끝나면 결과 화면 버튼(방으로 돌아가기 / 다시 하기 · 메인으로)

## 아이템 (2~3.5초마다 아레나에 등장, 최대 5개, 15초 후 소멸)
인원이 줄수록 등장 간격이 늘어남(2명 남으면 2배). 2명 남으면 무적 아이템은 나오지 않음.

| 아이템 | 효과 |
|---|---|
| 헬멧 | 낙석 1회 방어, 최대 2개 중첩 (안전모: 노랑 1개 / 빨강+흰 띠+2단 돔 2개) |
| 차징 가속 | 풀차징까지 걸리는 시간 단축 (1개당 차징 속도 +25%). 경기 끝까지 유지, 최대 3개 중첩 |
| 쿨타임 감소 | 밀치기 쿨타임 단축 (쿨타임 = 기본 ÷ (1 + 0.2×개수)). 경기 끝까지 유지, 최대 3개 중첩 |
| 글러브 | 내 밀치기가 강해짐: 1개당 넉백 +7%, 상대 경직 +15%. 양손에 빨간 권투 장갑(개수만큼 커짐). 경기 끝까지 유지, 최대 3개 중첩 |
| 무적 5초 / 무적 10초 | 낙석·밀치기 모두 무시. 금색 보호막 + 회전 고리, 끝나기 1.5초 전부터 깜빡임 |
- **탈락 압박**: 남은 인원이 줄수록 낙석 빈도·동시 낙하 수· 2명 남으면 빈도 3.5배 (`rock_dodge_game.gd` `last_two_rate_mult`)
- **난이도**: 시작부터 초당 약 5.5개 낙석(인원 감소 전 기준), 90초에 걸쳐 초당 약 11개까지 빈도·크기·속도·풍속 증가, 이후 30초마다 빈도가 더 늘어나는 서든데스

## 수치 조정 위치
- 밀치기·이동: `scripts/character/fighter.gd` 상단 `@export`
- 아레나 크기·봇 수·난이도·바람·아이템: `games/rock_dodge/rock_dodge_game.gd` 상단 `@export`
- 회전 기둥: `games/rock_dodge/sweeper.gd` 상단
- 봇 반응 속도·공격성: `games/rock_dodge/bot_brain.gd` `_ready()`

---

# 뒷북의 달인 (`games/drum_echo`)
공격팀 한 명이 북으로 리듬을 치면, 나머지 팀이 다음 마디에 똑같이 따라 치는 리듬 대결 (리듬 천국 같은 파티 리듬 게임).

## 조작
| 입력 | 동작 |
|---|---|
| Space (F 도 됨, 화면 왼쪽 큰 버튼) | 둥 (왼쪽 큰 주황 북). 피버는 누르고 있다가 떼기 |
| Enter (J 도 됨, 화면 오른쪽 큰 버튼) | 딱 (오른쪽 작은 보라 북) |
| 오른쪽 위 − / + | 박자 보정 (±10ms, 기기에 저장). 소리가 늦는 기기(블루투스 이어폰)용 |

## 규칙 (`games/drum_echo/chart.gd`)
- 반주 120 BPM (한 박 0.5초, 한 마디 2초). 시작 전 2마디 카운트
- **차례**: [쉼] 공격 N마디 [쉼] 따라 치기 N마디. 단계 `STAGES` = 1마디 4차례 → 2마디 3차례 → 4마디 2차례
  - 팀마다 똑같이 돌아가며 공격하고, 팀 수로 나누어떨어지지 않고 남는 차례(최대 2번, `HOST_MAX_EXTRA`)는 **가면 쓴 진행자**가 랜덤 리듬으로 공격 (모두가 따라 침)
  - 예) 2팀: 1마디 ×4 → 2마디 ×2 + 진행자 1 → 4마디 ×2 / 3팀: 1마디 ×3 + 진행자 1 → 2마디 ×3 → 4마디 ×3 / 4팀: 진행자 없음
  - **쉼(텀)**: 공격 앞·따라 치기 앞에 각각 `gap`박. 첫 차례 8박 → 마지막 차례 4박으로 점점 짧아짐 (`GAP_START`·`GAP_END`). 쉼의 마지막 3박에 '띵' 카운트
  - 2팀 한 곡 약 2분 14초
- **개수 지정**: 차례마다 컴퓨터가 둥·딱 개수만 정해 쉼 동안 크게 보여 줌 (`make_spec`, 진행할수록 많아짐). 예: "1마디 · 둥 2번 · 딱 1번"
  - **피버** = 0.3초(`FEVER_HOLD_MIN`) 넘게 누르고 있다가 떼는 노트. 그 북 2개로 셈
  - 공격자 화면에는 친 개수가 실시간으로 (둥 2/3 · 딱 1/1 완료)
  - 많거나 적으면 다른 만큼 1개당 −40 (`COUNT_PENALTY`). 상대에게는 컴퓨터가 개수를 맞춘 노트가 감 (`fit_pattern`: 친 노트는 자리를 옮기지 않고, 넘치면 뒤에서부터 빼고 모자라면 빈 박에 채움). 아무것도 안 치면 전부 컴퓨터가 채움
- **공격자**: 공격팀 사람 중 무작위 한 명 (같은 사람 연속 방지). 봇만 있는 팀이면 봇(컴퓨터 패턴). **개인전은 진행자가 공격**하고 모두가 따라 침
- **공격 박자**: 박자는 마음대로 (칸에 맞추지 않고 친 시각 그대로 상대에게 감, ms 단위). 점수(`attack_score`): 반주 박에서 ±40ms PERFECT 50 · ±75ms GOOD 30 · ±110ms BAD 10, 엇박(반 박)이면 그 절반, 둘 다 아니면 0. 같은 북을 0.09초 안에 연달아 치면 한 번으로
- **따라 치기 판정**: 같은 북·같은 타이밍 ±45ms PERFECT 100 · ±90ms GOOD 60 · ±140ms BAD 20 · 못 치면 MISS 0 · 노트 없는 곳을 치면 '헛침' −10. 피버는 누름과 끝 시각에 뗌을 각각 판정 (너무 일찍·늦게 떼면 MISS)
- **승패**: 곡이 끝나면 팀원 점수 합계(개인전은 개인 점수)로 순위 → 라운드 승점
- 판정은 서버가 한다 (클라이언트는 친 시각을 보내고 화면엔 예상 판정을 바로 표시)
- 시계: 노트 길·박자 점·판정 모두 '귀에 들리는 반주 시각'(`heard_time` = 화면 시계 − 소리 출력 지연 − 박자 보정) 하나로 맞춤
  - 화면 시계는 실제로 흐른 시간만큼 매끄럽게 가고 반주 재생 위치와의 차이는 약 1초에 걸쳐 줄임 (재생 위치는 오디오 버퍼 단위로 들쭉날쭉해서 바로 따라가면 노트가 순간이동함). 0.3초 넘게 어긋나면 반주를 다시 맞춤
  - 판정은 각자 PC에서 잰 시각으로 한다 (클라이언트가 친 시각을 보내고 서버는 같은 계산만 함 → 네트워크 지연은 판정에 영향 없음)
  - **자동 박자 보정**: 따라 치기 한 차례가 끝날 때마다 내가 맞힌 노트가 한쪽으로 쏠려 있으면(중앙값 15ms 넘게) 그 70%만큼 보정을 옮기고 기기에 저장. 보정은 초당 50ms씩 천천히 적용되어 노트가 튀지 않음. 수동 −/+ 도 그대로
- 노트 길: 공격 노트는 실제로 들린 뒤에야 판정선에서 나타남 (진행자·봇 리듬을 미리 볼 수 없음). 반 박마다 눈금
- 화면: 팀마다 팀 색 발판·깃발, 북은 주황(둥)·보라(딱). 카메라가 공격 중엔 공격팀(진행자), 따라 치기 중엔 따라 치는 팀들을 비추고, 잡은 뒤에도 음악방송처럼 천천히 좌우로 돌고·다가가고·오르내림
- 소리: 남이 친 공격은 박자 칸에 맞춰 울림. 따라 치는 소리는 내가 따라 칠 땐 우리 팀만, 우리 팀이 공격했을 땐 따라 치는 첫 팀만 들림 (`audible_team`). 피버는 누르는 동안 '드르륵'
- 성능: 이 게임은 무대만 보므로 그림자 범위 28m·2단, 무대에서 30m 밖 풀 숨김, 작은 부품 그림자 끔, 북 재질 공유, PC는 VSync mailbox (입력 지연 감소, 나가면 원래대로)
- 진행자: `scripts/world/masked_host.gd` (가면·검은 옷, 가리키기·박수·끄덕임). 돌피하기에서는 링 밖 네 방향 단상에서 생존자를 지켜보고 탈락자를 가리킴
- 소리 파일: `tools/audio/gen_drum.py` → `audio/drum/` (둥·딱·신호·놓침·반주 groove.ogg)

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
