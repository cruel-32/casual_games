# Open Field Prototype (Godot 4)

야숨 스타일 그래픽을 목표로 한 3D 3인칭 프로토타입.

## 실행
Godot 4.3 이상(4.5.1에서 검증), **Forward+ 렌더러**로 실행 (F5).
볼류메트릭 안개·SSAO는 Forward+에서만 켜집니다.

## 조작
WASD 이동 · 마우스 시점 · Space 점프 · Shift 달리기 · 휠 줌 · Esc 마우스 해제

## 그래픽 구성
| 요소 | 파일 |
|---|---|
| 툰 라이팅(2단계 음영·푸른 그림자·림 라이트) 공용 | `shaders/toon_light.gdshaderinc` |
| 단색 오브젝트 툰 머티리얼 | `shaders/toon.gdshader`, `scripts/toon.gd` |
| 지형 색(풀 얼룩·경사 바위·고지대 눈) | `shaders/terrain.gdshader` |
| 바람 풀(돌풍·흔들림·플레이어 주변 눕힘·거리 페이드) | `shaders/grass.gdshader`, `scripts/grass.gd` |
| 하늘(그라데이션·태양·흐르는 구름) | `shaders/sky.gdshader` |
| 대기 원근 안개·글로우·색 보정·조명 | `scripts/main.gd` `_build_environment()` |
| 절차적 높이맵 지형 + 충돌 | `scripts/terrain.gd` |

## 조절 포인트
- 풀 밀도/범위: Main 노드의 `grass_density`(기본 2.5), `grass_radius`. 사양이 낮으면 density 1.0
- 나무/바위 수: `tree_count`, `rock_count`
- 지형 모양: `terrain.gd`의 `_height_fn()`, `noise_seed`
- 나무·바위·유적·캐릭터는 기본 도형으로 만든 **임시 에셋**. 3·4단계에서 실제 모델로 교체 예정
