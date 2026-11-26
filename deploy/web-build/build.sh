#!/bin/sh
# /game (프로젝트 소스) 를 웹으로 내보내 /out (Caddy가 제공하는 폴더) 에 배포
#   /            안내 페이지 (deploy/web-landing) — PC는 Windows 다운로드, 모바일은 앱 설치로 유도
#   /play/       웹 체험판 (Godot 웹 빌드)
#   /download/   Windows zip
#   /links.json  다운로드·앱 스토어 주소 (deploy/web-landing/links.json 을 고쳐서 다시 빌드)
#   /version.json 업데이트 정보 (저장소의 release.json + PC 업데이트 팩 해시·서명) → 게임이 읽음
#   /download/updates/game-<버전>.pck  PC 업데이트 팩 (서명 키 PATCH_SIGNING_KEY 가 있을 때만)
# Windows 실행 파일(zip)도 /out/download/ 에 함께 넣음 (건너뛰려면 BUILD_WINDOWS=0)
set -e
# 컨테이너는 root 로 돌아서 /game 에 만든 파일(.godot 임포트 캐시 등)이 root 소유가 된다.
# 그러면 GitHub Actions runner(일반 사용자)가 다음 체크아웃 때 지우지 못하므로,
# 끝날 때(실패해도) /game 폴더 주인에게 소유권을 돌려준다.
trap 'chown -R "$(stat -c %u:%g /game)" /game 2>/dev/null || true' EXIT
echo "[web-build] 시작 (Windows zip: ${BUILD_WINDOWS:-1})"
[ "${BUILD_WINDOWS:-1}" != "1" ] || command -v zip >/dev/null || { echo "[web-build] 실패: zip 없음 → docker compose build web-build 로 빌더 이미지를 다시 만드세요"; exit 1; }
echo "[web-build] 리소스 임포트"
godot --headless --path /game --import >/dev/null 2>&1 || true
godot --headless --path /game --import >/dev/null 2>&1

echo "[web-build] 웹 내보내기"
rm -rf /tmp/web && mkdir -p /tmp/web/play
godot --headless --path /game --export-release "Web" /tmp/web/play/index.html >/tmp/export.log 2>&1 \
    || { tail -30 /tmp/export.log; exit 1; }
test -f /tmp/web/play/index.wasm || { echo "[web-build] 실패: index.wasm 없음"; tail -30 /tmp/export.log; exit 1; }

echo "[web-build] 안내 페이지"
L=/game/deploy/web-landing
mkdir -p /tmp/web/assets
cp "$L/index.html" "$L/links.json" /tmp/web/
cp /game/fonts/Jua-Regular.ttf /game/ui/portraits/slot_*.png /tmp/web/assets/
cp /game/icons/icon.png /tmp/web/assets/icon.png
# 게임 소개 페이지 (/about/)
mkdir -p /tmp/web/about
cp "$L/about/index.html" "$L"/about/*.jpg /tmp/web/about/

if [ "${BUILD_WINDOWS:-1}" = "1" ]; then
    # 실행 파일(.exe)과 게임 데이터(.pck)가 따로 나온다 (백신 오탐을 줄이려고 pck를 exe에 합치지 않음)
    # → 둘이 같은 폴더에 있어야 실행되므로 zip 하나로 묶어 배포
    echo "[web-build] Windows 내보내기"
    rm -rf /tmp/win && mkdir -p /tmp/win/SmallPartyWorld /tmp/web/download
    godot --headless --path /game --export-release "Windows" /tmp/win/SmallPartyWorld/SmallPartyWorld.exe >/tmp/export_win.log 2>&1 \
        || { tail -30 /tmp/export_win.log; exit 1; }
    test -f /tmp/win/SmallPartyWorld/SmallPartyWorld.pck || { echo "[web-build] 실패: .pck 없음"; exit 1; }
    printf '%s\r\n' "Small Party World (Windows)" "" \
        "1. 이 zip 파일의 압축을 모두 푼다 (zip 안에서 바로 실행하지 말 것)" \
        "2. SmallPartyWorld.exe 를 실행한다" \
        "   SmallPartyWorld.pck 는 게임 데이터 — exe 와 같은 폴더에 있어야 한다" \
        > /tmp/win/SmallPartyWorld/README.txt
    (cd /tmp/win && zip -qr /tmp/web/download/SmallPartyWorld-windows.zip SmallPartyWorld)
    ls -la /tmp/web/download
fi

# 업데이트 정보: release.json 의 버전으로 PC 업데이트 팩(= Windows 게임 데이터 .pck)을 올리고 version.json 생성
VER=$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' /game/release.json | head -1)
echo "[web-build] version.json (버전 $VER)"
PCK_ARGS=""
if [ -f /tmp/win/SmallPartyWorld/SmallPartyWorld.pck ]; then
    mkdir -p /tmp/web/download/updates
    cp /tmp/win/SmallPartyWorld/SmallPartyWorld.pck "/tmp/web/download/updates/game-$VER.pck"
    PCK_ARGS="--pck /tmp/web/download/updates/game-$VER.pck --pck-url /download/updates/game-$VER.pck"
fi
KEY_ARGS=""
if [ -n "$PATCH_SIGNING_KEY" ]; then
    (umask 077; printf '%s\n' "$PATCH_SIGNING_KEY" > /tmp/patch_key.pem)
    KEY_ARGS="--key /tmp/patch_key.pem"
fi
# shellcheck disable=SC2086
godot --headless --path /game -s tools/make_manifest.gd -- $PCK_ARGS $KEY_ARGS \
    --links "$L/links.json" --out /tmp/web/version.json
rm -f /tmp/patch_key.pem
# 서명이 없으면 업데이트 팩은 쓰이지 않으므로 올리지 않음
grep -q '"sig": ""' /tmp/web/version.json && rm -rf /tmp/web/download/updates || true

echo "[web-build] /out 교체"
# 폰 테스트용 APK 는 Android 작업이 따로 올리므로, 웹만 다시 배포할 때 지워지지 않게 옮겨 둔다
if ls /out/download/*.apk >/dev/null 2>&1; then
    mkdir -p /tmp/web/download && cp /out/download/*.apk /tmp/web/download/
fi
find /out -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -r /tmp/web/. /out/
ls -la /out
echo "[web-build] 완료 — https://spw.cloudish.cloud (안내) / https://spw.cloudish.cloud/play/ (웹 체험판)"
