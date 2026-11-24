# Small Party World — 웹 빌더 (Godot 헤드리스 + 내보내기 템플릿)
# 사용: docker compose --profile build run --rm web-build
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip zip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip
# 내보내기 템플릿 (약 1.3GB, 이미지 빌드 시 한 번만 받음)
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -O /tmp/t.tpz \
    && unzip -q /tmp/t.tpz -d /tmp/t \
    && mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
    && mv /tmp/t/templates/* /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ \
    && rm -rf /tmp/t /tmp/t.tpz

COPY build.sh /usr/local/bin/build-web
RUN chmod +x /usr/local/bin/build-web
WORKDIR /game
CMD ["build-web"]
