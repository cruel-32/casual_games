#!/bin/sh
# /game (프로젝트 소스) 를 웹으로 내보내 /out (Caddy가 제공하는 폴더) 에 배포
# BUILD_WINDOWS=1 이면 Windows 실행 파일도 /out/download/ 에 함께 넣음
set -e
echo "[web-build] 리소스 임포트"
godot --headless --path /game --import >/dev/null 2>&1 || true
godot --headless --path /game --import >/dev/null 2>&1

echo "[web-build] 웹 내보내기"
rm -rf /tmp/web && mkdir -p /tmp/web
godot --headless --path /game --export-release "Web" /tmp/web/index.html >/tmp/export.log 2>&1 \
    || { tail -30 /tmp/export.log; exit 1; }
test -f /tmp/web/index.wasm || { echo "[web-build] 실패: index.wasm 없음"; tail -30 /tmp/export.log; exit 1; }

if [ "${BUILD_WINDOWS:-0}" = "1" ]; then
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

echo "[web-build] /out 교체"
find /out -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -r /tmp/web/. /out/
ls -la /out
echo "[web-build] 완료 — https://spw.cloudish.cloud 새로고침"
