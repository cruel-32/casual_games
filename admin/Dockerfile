# Small Party World 관리 서버 (공지·점검 모드·관리자 계정) — spw.cloudish.cloud/admin/, /api/
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY server.mjs accounts.mjs ./
COPY public ./public
ENV PORT=7780 DATA_DIR=/data NODE_ENV=production
VOLUME /data
EXPOSE 7780
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- "http://127.0.0.1:${PORT}/api/health" || exit 1
CMD ["node", "--disable-warning=ExperimentalWarning", "server.mjs"]
