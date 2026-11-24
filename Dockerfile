# casual_games 전용 서버 (Godot 헤드리스)
# 빌드: docker compose build   /  실행: docker compose up -d
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.5.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /game
COPY . /game
# 리소스 임포트(.godot 캐시 생성)를 빌드 시점에 미리 해 둔다
RUN godot --headless --path /game --import >/dev/null 2>&1 || true

ENV GAME_PORT=7777
EXPOSE 7777
CMD ["sh", "-c", "exec godot --headless --path /game -- --server --port ${GAME_PORT}"]
