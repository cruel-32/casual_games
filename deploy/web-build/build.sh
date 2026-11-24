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
    echo "[web-build] Windows 내보내기"
    mkdir -p /tmp/web/download
    godot --headless --path /game --export-release "Windows" /tmp/web/download/SmallPartyWorld.exe >/tmp/export_win.log 2>&1 \
        || { tail -30 /tmp/export_win.log; exit 1; }
fi

echo "[web-build] /out 교체"
find /out -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -r /tmp/web/. /out/
ls -la /out
echo "[web-build] 완료 — https://spw.cloudish.cloud 새로고침"
