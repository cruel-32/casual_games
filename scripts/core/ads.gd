extends Node
## 보상형 광고 (자동 로드 "Ads") — 정식 출시 단계에서만, 광고 제거 계정이 아닐 때만.
## 광고를 끝까지 보면 AdMob 이 관리 서버(/api/ads/ssv)에 서명된 확인을 보내고, 서버가 그 계정의 오늘 판수를 늘린다.
## (게임이 "봤다"고 알리는 방식이 아니라서 조작할 수 없음. custom_data = 계정 번호)
##
## 광고 SDK: Google AdMob — Godot 플러그인 "AdMob" (Poing Studios, Android·iOS). PC·웹은 광고 없음
##   설치 순서는 README "광고 (AdMob)" 참고. 플러그인이 없으면 available() 이 false 라 버튼이 안 보인다.

signal reward_done(ok: bool, message: String)

## 관리 서버와 AdMob 콘솔에서 만든 보상형 광고 단위 ID (정식 출시 전에 채움)
const REWARDED_UNIT := {
    "android": "",      # 예: ca-app-pub-xxxxxxxx/yyyyyyyy
    "ios": "",
}

var _plugin: Object = null


func _ready() -> void:
    for name in ["PoingGodotAdMob", "PoingGodotAdMobRewardedAd"]:
        if Engine.has_singleton(name):
            _plugin = Engine.get_singleton(name)
            break


func _unit() -> String:
    return String(REWARDED_UNIT.get("ios" if OS.has_feature("ios") else "android", ""))


## 지금 이 기기에서 보상형 광고를 보여 줄 수 있나
func available() -> bool:
    return _plugin != null and _unit() != "" and OS.has_feature("mobile")


## 보상형 광고 보여 주기. 끝나면 reward_done. 판수는 서버 확인 후 Account.refresh() 로 반영
func show_rewarded() -> void:
    if not available():
        reward_done.emit(false, "광고는 모바일 앱에서 볼 수 있어요. 본 판수는 같은 계정이면 PC·웹에서도 쓸 수 있어요")
        return
    # 플러그인 연결은 AdMob 계정·광고 단위가 생기면 여기서 완성한다 (README 참고)
    reward_done.emit(false, "광고를 준비 중이에요")
