// Small Party World 관리 서버
//   https://spw.cloudish.cloud/admin/      관리 페이지 (구글 로그인, 등록된 계정만)
//   https://spw.cloudish.cloud/api/notices 게임·웹이 읽는 공지 (공개)
//   http://<컨테이너>:7780/api/status       게임 서버가 읽는 점검 모드 (공개)
//   http://<컨테이너>:7780/internal/...     게임 서버 전용 (신고 접수, 제재·금칙어 목록). Caddy 로 노출하지 않음
//
// 환경 변수
//   PORT              기본 7780
//   DATA_DIR          SQLite 파일 위치 (기본 ./data)
//   GOOGLE_CLIENT_ID  구글 OAuth 웹 클라이언트 ID (없으면 로그인 불가)
//   ADMIN_EMAILS      항상 관리자로 등록되는 구글 계정 (쉼표로 구분). 관리 페이지에서 지울 수 없음
//
// 외부 의존성은 jose(구글 ID 토큰 검증) 하나. DB 는 Node 내장 node:sqlite.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { migrate as migrateAccounts, makeAccounts } from "./accounts.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SESSION_DAYS = 7;
const COOKIE = "spw_admin";
const KINDS = ["banner", "notice", "patch", "popup"];
const PLATFORMS = ["pc", "android", "ios", "web"];
const MAX_BODY = 64 * 1024;
const REPORT_KEEP_DAYS = 30;            // 신고(채팅 기록 포함) 보관 기간 — 개인정보처리방침과 같아야 함
const REPORT_REASONS = ["abuse", "spam", "nickname", "cheat", "other"];
const SANCTION_KINDS = ["mute", "ban"];

// ---------------------------------------------------------------- DB
export function openDb(file) {
    if (file !== ":memory:") fs.mkdirSync(path.dirname(file), { recursive: true });
    const db = new DatabaseSync(file);
    db.exec(`
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS admins (
            email TEXT PRIMARY KEY,
            added_by TEXT NOT NULL,
            added_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sessions (
            token_hash TEXT PRIMARY KEY,
            email TEXT NOT NULL,
            expires_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS notices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            platforms TEXT NOT NULL DEFAULT '',
            min_version TEXT NOT NULL DEFAULT '',
            max_version TEXT NOT NULL DEFAULT '',
            starts_at TEXT NOT NULL DEFAULT '',
            ends_at TEXT NOT NULL DEFAULT '',
            pinned INTEGER NOT NULL DEFAULT 0,
            published INTEGER NOT NULL DEFAULT 1,
            created_by TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'open',
            reporter_nick TEXT NOT NULL,
            reporter_device TEXT NOT NULL DEFAULT '',
            target_nick TEXT NOT NULL,
            target_device TEXT NOT NULL DEFAULT '',
            room TEXT NOT NULL DEFAULT '',
            reason TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            chat TEXT NOT NULL DEFAULT '[]',
            handled_by TEXT NOT NULL DEFAULT '',
            handled_at TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS sanctions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device TEXT NOT NULL,
            nick TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL,
            reason TEXT NOT NULL DEFAULT '',
            until TEXT NOT NULL DEFAULT '',
            report_id INTEGER,
            created_by TEXT NOT NULL,
            created_at TEXT NOT NULL,
            revoked_at TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS words (
            word TEXT PRIMARY KEY,
            added_by TEXT NOT NULL,
            added_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at TEXT NOT NULL,
            email TEXT NOT NULL,
            action TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT ''
        );
    `);
    migrateAccounts(db);
    return db;
}

const nowIso = () => new Date().toISOString();
const sha256 = (s) => crypto.createHash("sha256").update(s).digest("hex");
const normEmail = (e) => String(e || "").trim().toLowerCase();

// 버전 비교 "1.2.10" vs "1.2.9" → 1 / 0 / -1 (게임의 Boot.compare 와 같은 규칙)
export function compareVersion(a, b) {
    const pa = String(a).split("."), pb = String(b).split(".");
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const x = parseInt(pa[i] || "0", 10) || 0, y = parseInt(pb[i] || "0", 10) || 0;
        if (x !== y) return x > y ? 1 : -1;
    }
    return 0;
}

// ---------------------------------------------------------------- 앱
// verifyGoogle(credential) → { email, email_verified, name, picture } (테스트에서 바꿔 끼움)
export function createApp({ db, clientId, ownerEmails = [], verifyGoogle, secureCookie = true, env = {}, providers, fetchImpl, ssvKeys }) {
    const owners = new Set(ownerEmails.map(normEmail).filter(Boolean));
    const customVerifier = !!verifyGoogle;
    for (const e of owners) {
        db.prepare("INSERT OR IGNORE INTO admins (email, added_by, added_at) VALUES (?, 'ADMIN_EMAILS', ?)").run(e, nowIso());
    }
    if (!verifyGoogle) {
        const jwks = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));
        verifyGoogle = async (credential) => {
            const { payload } = await jwtVerify(credential, jwks, {
                issuer: ["https://accounts.google.com", "accounts.google.com"],
                audience: clientId,
            });
            return payload;
        };
    }

    const audit = (email, action, detail = "") =>
        db.prepare("INSERT INTO audit (at, email, action, detail) VALUES (?, ?, ?, ?)").run(nowIso(), email, action, String(detail).slice(0, 500));

    const getSetting = (key, fallback) => {
        const row = db.prepare("SELECT value FROM settings WHERE key = ?").get(key);
        return row ? JSON.parse(row.value) : fallback;
    };
    const setSetting = (key, value) =>
        db.prepare("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(key, JSON.stringify(value));

    const accounts = makeAccounts({ db, env: { GOOGLE_CLIENT_ID: clientId, ...env }, getSetting, setSetting, audit, providers, fetchImpl, ssvKeys });
    const helpers = { json, readJson, readForm };

    const isAdmin = (email) => !!db.prepare("SELECT 1 FROM admins WHERE email = ?").get(email);

    function sessionEmail(req) {
        const token = parseCookies(req.headers.cookie || "")[COOKIE];
        if (!token) return null;
        const row = db.prepare("SELECT email, expires_at FROM sessions WHERE token_hash = ?").get(sha256(token));
        if (!row || row.expires_at < Date.now()) return null;
        // 관리자 목록에서 빠지면 세션도 바로 무효
        return isAdmin(row.email) ? row.email : null;
    }

    function maintenance() {
        return getSetting("maintenance", { on: false, message: "" });
    }

    function activeNotices(platform, version) {
        const now = nowIso();
        const rows = db.prepare(`
            SELECT id, kind, title, body, platforms, min_version, max_version, starts_at, ends_at, pinned, updated_at
            FROM notices WHERE published = 1
            AND (starts_at = '' OR starts_at <= ?) AND (ends_at = '' OR ends_at > ?)
            ORDER BY pinned DESC, updated_at DESC LIMIT 50`).all(now, now);
        return rows.filter((n) => {
            const plats = n.platforms ? n.platforms.split(",") : [];
            if (platform && plats.length && !plats.includes(platform)) return false;
            if (version && n.min_version && compareVersion(version, n.min_version) < 0) return false;
            if (version && n.max_version && compareVersion(version, n.max_version) > 0) return false;
            return true;
        }).map((n) => ({
            id: n.id, kind: n.kind, title: n.title, body: n.body, pinned: !!n.pinned,
            starts_at: n.starts_at, ends_at: n.ends_at, updated_at: n.updated_at,
        }));
    }

    // 신고는 30일이 지나면 채팅 기록과 함께 지운다
    function purgeOld(now = Date.now()) {
        const cut = new Date(now - REPORT_KEEP_DAYS * 864e5).toISOString();
        return Number(db.prepare("DELETE FROM reports WHERE created_at < ?").run(cut).changes);
    }

    function activeSanctions() {
        const now = nowIso();
        return db.prepare(`SELECT id, device, account, nick, kind, reason, until FROM sanctions
            WHERE revoked_at = '' AND (until = '' OR until > ?) ORDER BY id`).all(now);
    }

    const str = (v, n) => String(v == null ? "" : v).slice(0, n);
    const device = (v) => (/^[A-Za-z0-9_-]{8,64}$/.test(String(v || "")) ? String(v) : "");
    const account = (v) => (/^[0-9A-F]{12}$/.test(String(v || "")) ? String(v) : "");

    function cleanNotice(b) {
        const kind = KINDS.includes(b.kind) ? b.kind : null;
        const title = String(b.title || "").trim().slice(0, 80);
        if (!kind) throw new HttpError(400, "종류가 올바르지 않아요");
        if (!title) throw new HttpError(400, "제목을 입력해 주세요");
        const plats = (Array.isArray(b.platforms) ? b.platforms : []).filter((p) => PLATFORMS.includes(p));
        const ver = (v) => (/^\d+(\.\d+){0,2}$/.test(String(v || "").trim()) ? String(v).trim() : "");
        const time = (t) => {
            if (!t) return "";
            const d = new Date(t);
            if (isNaN(d)) throw new HttpError(400, "날짜가 올바르지 않아요");
            return d.toISOString();
        };
        return {
            kind, title,
            body: String(b.body || "").slice(0, 4000),
            platforms: plats.join(","),
            min_version: ver(b.min_version), max_version: ver(b.max_version),
            starts_at: time(b.starts_at), ends_at: time(b.ends_at),
            pinned: b.pinned ? 1 : 0, published: b.published === false ? 0 : 1,
        };
    }

    // ---- 라우팅
    async function handle(req, res) {
        const url = new URL(req.url, "http://x");
        const p = url.pathname;
        const m = req.method;

        // 계정·로그인·판수 (accounts.mjs)
        if (p.startsWith("/api/") && await accounts.handlePublic(req, res, url, helpers)) return;

        // 공개 API (게임·웹)
        if (p === "/api/notices" && m === "GET") {
            const platform = PLATFORMS.includes(url.searchParams.get("platform")) ? url.searchParams.get("platform") : "";
            return json(res, 200, { maintenance: maintenance(), notices: activeNotices(platform, url.searchParams.get("version") || "") }, true);
        }
        if (p === "/api/status" && m === "GET") {
            return json(res, 200, { maintenance: maintenance() }, true);
        }
        if (p === "/api/health") return json(res, 200, { ok: true });

        // 게임 서버 전용 (같은 도커 네트워크·호스트에서만). 리버스 프록시를 거친 요청은 거절
        if (p.startsWith("/internal/")) {
            if (req.headers["x-forwarded-for"] || req.headers["x-forwarded-host"]) return json(res, 404, { error: "없는 주소예요" });
            if (await accounts.handleInternal(req, res, url, helpers)) return;
            if (p === "/internal/moderation" && m === "GET") {
                return json(res, 200, {
                    sanctions: activeSanctions().map((x) => ({ device: x.device, account: x.account, kind: x.kind, until: x.until, reason: x.reason })),
                    words: db.prepare("SELECT word FROM words ORDER BY word").all().map((w) => w.word),
                });
            }
            if (p === "/internal/reports" && m === "POST") {
                const b = await readJson(req);
                const reason = REPORT_REASONS.includes(b.reason) ? b.reason : "other";
                const chat = (Array.isArray(b.chat) ? b.chat : []).slice(-40).map((c) => ({
                    t: str(c.t, 30), nick: str(c.nick, 24), text: str(c.text, 200),
                }));
                const rep = b.reporter || {}, tgt = b.target || {};
                if (!str(tgt.nick, 24)) return json(res, 400, { error: "대상이 없어요" });
                // 같은 사람이 같은 대상을 10분 안에 여러 번 신고하면 하나로
                const dup = db.prepare(`SELECT id FROM reports WHERE reporter_device = ? AND target_device = ? AND reporter_account = ? AND target_account = ? AND created_at > ? AND status = 'open'`)
                    .get(device(rep.device), device(tgt.device), account(rep.account), account(tgt.account), new Date(Date.now() - 600e3).toISOString());
                if (dup && (device(rep.device) || account(rep.account))) return json(res, 200, { id: dup.id, duplicate: true });
                const r = db.prepare(`INSERT INTO reports (created_at, reporter_nick, reporter_device, reporter_account, target_nick, target_device, target_account, room, reason, detail, chat)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(nowIso(), str(rep.nick, 24), device(rep.device), account(rep.account), str(tgt.nick, 24), device(tgt.device), account(tgt.account),
                    str(b.room, 60), reason, str(b.detail, 300), JSON.stringify(chat));
                return json(res, 200, { id: Number(r.lastInsertRowid) });
            }
            return json(res, 404, { error: "없는 주소예요" });
        }

        // 관리 페이지 (정적 파일)
        if (p === "/admin") return redirect(res, "/admin/");
        if (p === "/admin/" && m === "GET") return sendFile(res, path.join(HERE, "public", "index.html"));
        if (p === "/admin/config" && m === "GET") return json(res, 200, { client_id: clientId || "" });

        // 관리 API
        if (!p.startsWith("/admin/api/")) return json(res, 404, { error: "없는 주소예요" });
        // 다른 사이트에서 보낸 요청 막기 (쿠키는 SameSite=Strict, 변경 요청은 이 헤더 필수)
        if (m !== "GET" && req.headers["x-spw-admin"] !== "1") return json(res, 403, { error: "잘못된 요청이에요" });

        if (p === "/admin/api/login" && m === "POST") {
            const body = await readJson(req);
            let info;
            try {
                if (!clientId && !customVerifier) throw new Error("GOOGLE_CLIENT_ID 없음");
                info = await verifyGoogle(String(body.credential || ""));
            } catch (e) {
                return json(res, 401, { error: "구글 로그인을 확인할 수 없어요" });
            }
            const email = normEmail(info.email);
            if (!email || info.email_verified === false) return json(res, 401, { error: "구글 계정 이메일을 확인할 수 없어요" });
            if (!isAdmin(email)) {
                audit(email, "login_denied");
                return json(res, 403, { error: `${email} 은(는) 등록된 관리자가 아니에요` });
            }
            const token = crypto.randomBytes(32).toString("base64url");
            db.prepare("INSERT INTO sessions (token_hash, email, expires_at) VALUES (?, ?, ?)").run(sha256(token), email, Date.now() + SESSION_DAYS * 864e5);
            db.prepare("DELETE FROM sessions WHERE expires_at < ?").run(Date.now());
            audit(email, "login");
            res.setHeader("Set-Cookie", `${COOKIE}=${token}; Path=/admin; HttpOnly; SameSite=Strict; Max-Age=${SESSION_DAYS * 86400}${secureCookie ? "; Secure" : ""}`);
            return json(res, 200, { email, name: info.name || "", picture: info.picture || "" });
        }

        const email = sessionEmail(req);
        if (!email) return json(res, 401, { error: "로그인이 필요해요" });
        if (await accounts.handleAdmin(req, res, url, email, helpers)) return;

        if (p === "/admin/api/logout" && m === "POST") {
            const token = parseCookies(req.headers.cookie || "")[COOKIE];
            db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(sha256(token));
            res.setHeader("Set-Cookie", `${COOKIE}=; Path=/admin; HttpOnly; SameSite=Strict; Max-Age=0${secureCookie ? "; Secure" : ""}`);
            return json(res, 200, { ok: true });
        }
        if (p === "/admin/api/me" && m === "GET") return json(res, 200, { email, owner: owners.has(email) });

        // 공지
        if (p === "/admin/api/notices" && m === "GET") {
            const rows = db.prepare("SELECT * FROM notices ORDER BY pinned DESC, updated_at DESC").all();
            return json(res, 200, { notices: rows.map((r) => ({ ...r, pinned: !!r.pinned, published: !!r.published, platforms: r.platforms ? r.platforms.split(",") : [] })) });
        }
        if (p === "/admin/api/notices" && m === "POST") {
            const n = cleanNotice(await readJson(req));
            const t = nowIso();
            const r = db.prepare(`INSERT INTO notices (kind, title, body, platforms, min_version, max_version, starts_at, ends_at, pinned, published, created_by, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(n.kind, n.title, n.body, n.platforms, n.min_version, n.max_version, n.starts_at, n.ends_at, n.pinned, n.published, email, t, t);
            audit(email, "notice_create", `${r.lastInsertRowid} ${n.title}`);
            return json(res, 200, { id: Number(r.lastInsertRowid) });
        }
        const nm = p.match(/^\/admin\/api\/notices\/(\d+)$/);
        if (nm && m === "PUT") {
            const n = cleanNotice(await readJson(req));
            const r = db.prepare(`UPDATE notices SET kind=?, title=?, body=?, platforms=?, min_version=?, max_version=?, starts_at=?, ends_at=?, pinned=?, published=?, updated_at=? WHERE id=?`)
                .run(n.kind, n.title, n.body, n.platforms, n.min_version, n.max_version, n.starts_at, n.ends_at, n.pinned, n.published, nowIso(), Number(nm[1]));
            if (!r.changes) return json(res, 404, { error: "없는 공지예요" });
            audit(email, "notice_update", `${nm[1]} ${n.title}`);
            return json(res, 200, { ok: true });
        }
        if (nm && m === "DELETE") {
            const r = db.prepare("DELETE FROM notices WHERE id = ?").run(Number(nm[1]));
            if (!r.changes) return json(res, 404, { error: "없는 공지예요" });
            audit(email, "notice_delete", nm[1]);
            return json(res, 200, { ok: true });
        }

        // 점검 모드
        if (p === "/admin/api/maintenance" && m === "GET") return json(res, 200, maintenance());
        if (p === "/admin/api/maintenance" && m === "PUT") {
            const b = await readJson(req);
            const v = { on: !!b.on, message: String(b.message || "").slice(0, 200) };
            setSetting("maintenance", v);
            audit(email, v.on ? "maintenance_on" : "maintenance_off", v.message);
            return json(res, 200, v);
        }

        // 관리자 계정
        if (p === "/admin/api/admins" && m === "GET") {
            const rows = db.prepare("SELECT email, added_by, added_at FROM admins ORDER BY added_at").all();
            return json(res, 200, { admins: rows.map((r) => ({ ...r, owner: owners.has(r.email) })) });
        }
        if (p === "/admin/api/admins" && m === "POST") {
            const e = normEmail((await readJson(req)).email);
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)) return json(res, 400, { error: "이메일 형식이 올바르지 않아요" });
            db.prepare("INSERT OR IGNORE INTO admins (email, added_by, added_at) VALUES (?, ?, ?)").run(e, email, nowIso());
            audit(email, "admin_add", e);
            return json(res, 200, { ok: true });
        }
        const am = p.match(/^\/admin\/api\/admins\/(.+)$/);
        if (am && m === "DELETE") {
            const e = normEmail(decodeURIComponent(am[1]));
            if (owners.has(e)) return json(res, 400, { error: "서버 설정(ADMIN_EMAILS)에 있는 계정은 여기서 지울 수 없어요" });
            if (e === email) return json(res, 400, { error: "자기 자신은 지울 수 없어요" });
            db.prepare("DELETE FROM admins WHERE email = ?").run(e);
            db.prepare("DELETE FROM sessions WHERE email = ?").run(e);
            audit(email, "admin_remove", e);
            return json(res, 200, { ok: true });
        }

        // 신고
        if (p === "/admin/api/reports" && m === "GET") {
            purgeOld();
            const status = url.searchParams.get("status") || "open";
            const rows = status === "all"
                ? db.prepare("SELECT * FROM reports ORDER BY id DESC LIMIT 200").all()
                : db.prepare("SELECT * FROM reports WHERE status = ? ORDER BY id DESC LIMIT 200").all(status);
            const counts = Object.fromEntries(db.prepare("SELECT status, COUNT(*) AS n FROM reports GROUP BY status").all().map((r) => [r.status, r.n]));
            return json(res, 200, { reports: rows.map((r) => ({ ...r, chat: JSON.parse(r.chat || "[]") })), counts });
        }
        const rm = p.match(/^\/admin\/api\/reports\/(\d+)$/);
        if (rm && m === "PUT") {
            const b = await readJson(req);
            const status = ["open", "done", "dismissed"].includes(b.status) ? b.status : null;
            if (!status) return json(res, 400, { error: "상태가 올바르지 않아요" });
            const r = db.prepare("UPDATE reports SET status = ?, note = ?, handled_by = ?, handled_at = ? WHERE id = ?")
                .run(status, str(b.note, 300), email, nowIso(), Number(rm[1]));
            if (!r.changes) return json(res, 404, { error: "없는 신고예요" });
            audit(email, "report_" + status, rm[1]);
            return json(res, 200, { ok: true });
        }

        // 제재 (기기 ID 기준: mute = 채팅 금지, ban = 접속 차단)
        if (p === "/admin/api/sanctions" && m === "GET") {
            const rows = db.prepare("SELECT * FROM sanctions ORDER BY id DESC LIMIT 200").all();
            const now = nowIso();
            return json(res, 200, { sanctions: rows.map((x) => ({ ...x, active: !x.revoked_at && (!x.until || x.until > now) })) });
        }
        if (p === "/admin/api/sanctions" && m === "POST") {
            const b = await readJson(req);
            const dev = device(b.device);
            const acc = account(b.account);
            if (!dev && !acc) return json(res, 400, { error: "기기 ID나 계정 번호가 필요해요" });
            if (!SANCTION_KINDS.includes(b.kind)) return json(res, 400, { error: "제재 종류가 올바르지 않아요" });
            const hours = Number(b.hours) || 0;     // 0 = 영구
            const until = hours > 0 ? new Date(Date.now() + hours * 3600e3).toISOString() : "";
            const r = db.prepare(`INSERT INTO sanctions (device, account, nick, kind, reason, until, report_id, created_by, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(dev, acc, str(b.nick, 24), b.kind, str(b.reason, 200), until, Number(b.report_id) || null, email, nowIso());
            if (Number(b.report_id)) {
                db.prepare("UPDATE reports SET status = 'done', handled_by = ?, handled_at = ? WHERE id = ?").run(email, nowIso(), Number(b.report_id));
            }
            audit(email, "sanction_" + b.kind, `${str(b.nick, 24)} ${acc || dev.slice(0, 8)} ${hours ? hours + "h" : "영구"} ${str(b.reason, 100)}`);
            return json(res, 200, { id: Number(r.lastInsertRowid), until });
        }
        const sm = p.match(/^\/admin\/api\/sanctions\/(\d+)$/);
        if (sm && m === "DELETE") {
            const r = db.prepare("UPDATE sanctions SET revoked_at = ? WHERE id = ? AND revoked_at = ''").run(nowIso(), Number(sm[1]));
            if (!r.changes) return json(res, 404, { error: "없거나 이미 풀린 제재예요" });
            audit(email, "sanction_revoke", sm[1]);
            return json(res, 200, { ok: true });
        }

        // 금칙어 (게임에 기본 목록이 있고, 여기서 추가한 것을 더함)
        if (p === "/admin/api/words" && m === "GET") {
            return json(res, 200, { words: db.prepare("SELECT * FROM words ORDER BY word").all() });
        }
        if (p === "/admin/api/words" && m === "POST") {
            const w = String((await readJson(req)).word || "").trim().toLowerCase().replace(/\s+/g, "").slice(0, 20);
            if (w.length < 2) return json(res, 400, { error: "두 글자 이상 입력해 주세요" });
            db.prepare("INSERT OR IGNORE INTO words (word, added_by, added_at) VALUES (?, ?, ?)").run(w, email, nowIso());
            audit(email, "word_add", w);
            return json(res, 200, { ok: true });
        }
        const wm = p.match(/^\/admin\/api\/words\/(.+)$/);
        if (wm && m === "DELETE") {
            const w = decodeURIComponent(wm[1]);
            db.prepare("DELETE FROM words WHERE word = ?").run(w);
            audit(email, "word_remove", w);
            return json(res, 200, { ok: true });
        }

        if (p === "/admin/api/audit" && m === "GET") {
            return json(res, 200, { audit: db.prepare("SELECT * FROM audit ORDER BY id DESC LIMIT 100").all() });
        }
        return json(res, 404, { error: "없는 주소예요" });
    }

    const app = async (req, res) => {
        try {
            await handle(req, res);
        } catch (e) {
            if (e instanceof HttpError) return json(res, e.status, { error: e.message });
            console.error(e);
            json(res, 500, { error: "서버 오류" });
        }
    };
    app.purgeOld = () => { accounts.purge(); return purgeOld(); };
    app.accounts = accounts;
    return app;
}

// ---------------------------------------------------------------- 도우미
class HttpError extends Error {
    constructor(status, message) { super(message); this.status = status; }
}

function json(res, status, data, cors = false) {
    const body = JSON.stringify(data);
    const h = { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" };
    if (cors) h["Access-Control-Allow-Origin"] = "*";
    res.writeHead(status, h);
    res.end(body);
}

function redirect(res, to) {
    res.writeHead(301, { Location: to });
    res.end();
}

function sendFile(res, file) {
    fs.readFile(file, (err, data) => {
        if (err) return json(res, 404, { error: "없는 파일" });
        res.writeHead(200, {
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": "no-cache",
            // 구글 로그인 팝업이 창을 주고받을 수 있게
            "Cross-Origin-Opener-Policy": "same-origin-allow-popups",
            "X-Frame-Options": "DENY",
            "Referrer-Policy": "strict-origin-when-cross-origin",
        });
        res.end(data);
    });
}

function parseCookies(header) {
    const out = {};
    for (const part of header.split(";")) {
        const i = part.indexOf("=");
        if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
    }
    return out;
}

// Apple 로그인은 결과를 form_post 로 보낸다
async function readForm(req) {
    const raw = await new Promise((resolve, reject) => {
        let size = 0; const chunks = [];
        req.on("data", (c) => { size += c.length; if (size > MAX_BODY) { reject(new HttpError(413, "내용이 너무 커요")); req.destroy(); return; } chunks.push(c); });
        req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
        req.on("error", reject);
    });
    return Object.fromEntries(new URLSearchParams(raw));
}

function readJson(req) {
    return new Promise((resolve, reject) => {
        let size = 0;
        const chunks = [];
        req.on("data", (c) => {
            size += c.length;
            if (size > MAX_BODY) { reject(new HttpError(413, "내용이 너무 커요")); req.destroy(); return; }
            chunks.push(c);
        });
        req.on("end", () => {
            try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {}); }
            catch { reject(new HttpError(400, "JSON 형식이 아니에요")); }
        });
        req.on("error", reject);
    });
}

// ---------------------------------------------------------------- 실행
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const port = Number(process.env.PORT || 7780);
    const dataDir = process.env.DATA_DIR || path.join(HERE, "data");
    const clientId = process.env.GOOGLE_CLIENT_ID || "";
    const owners = (process.env.ADMIN_EMAILS || "").split(",");
    const db = openDb(path.join(dataDir, "admin.sqlite"));
    if (!clientId) console.warn("[admin] GOOGLE_CLIENT_ID 가 없어 관리 페이지에 로그인할 수 없습니다");
    const app = createApp({ db, clientId, ownerEmails: owners, env: process.env });
    app.purgeOld();
    setInterval(() => app.purgeOld(), 3600e3);      // 30일 지난 신고 삭제 (1시간마다)
    http.createServer(app).listen(port, () => {
        console.log(`[admin] http://0.0.0.0:${port}  관리자: ${owners.filter(Boolean).join(", ") || "(없음)"}`);
    });
}
