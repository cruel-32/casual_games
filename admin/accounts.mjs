// 계정 (소셜 로그인) · 하루 판수 · 광고 보상 · 운영 단계
//
// 개인정보 최소화: 제공자 이름과 "제공자 사용자 번호를 해시한 값"만 저장한다.
// 이메일·이름·프로필 사진은 요청하지도, 저장하지도 않는다 (구글 scope=openid, 애플 scope 없음).
//
// 공개 (Caddy /api/*)
//   GET    /api/auth/providers            켜진 로그인 제공자
//   POST   /api/auth/start {provider}     로그인 시작 → {id, url}  (게임이 url 을 브라우저로 연다)
//   GET    /api/auth/go?id=               제공자 로그인 화면으로 이동
//   GET|POST /api/auth/callback/<p>       제공자가 돌아오는 곳 → "게임으로 돌아가세요" 화면
//   GET    /api/auth/poll?id=             게임이 기다리며 확인 → {status, token}
//   POST   /api/auth/logout               (Bearer) 이 기기 로그아웃
//   GET    /api/account                   (Bearer) 내 계정·오늘 판수
//   DELETE /api/account                   (Bearer) 계정 삭제 (스토어 요구사항)
//   GET    /api/ads/ssv?...               AdMob 보상형 광고 서버 확인(SSV) → 판수 +1
// 게임 서버 전용 (/internal/*)
//   POST /internal/account/verify {token}         → {account}
//   POST /internal/plays/start {accounts:[id]}    → {ok, blocked:[id], phase}
//
// 환경 변수: PUBLIC_URL, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
//           APPLE_SERVICE_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY

import crypto from "node:crypto";
import { createRemoteJWKSet, jwtVerify, SignJWT, importPKCS8 } from "jose";

export const PROVIDERS = ["google", "apple"];
const PROVIDER_NAMES = { google: "구글", apple: "Apple" };
const LOGIN_TTL_MS = 10 * 60e3;          // 로그인 시작 후 10분 안에 끝내야 함
const TOKEN_DAYS = 180;                  // 게임 로그인 유지 기간
const KST_MS = 9 * 3600e3;

// 운영 정책 기본값 — 관리 페이지 "운영 정책" 탭에서 바꾼다
export const DEFAULT_POLICY = {
    phase: "beta",          // beta = 모든 제한 끔 / live = 정식 출시 (판수 제한·광고 적용)
    daily_free: 1,          // 하루 무료 판수 (광고 1번마다 +ad_reward) (1판 = 한 번 시작한 경기, 최대 5라운드)
    ad_reward: 1,           // 보상형 광고 1번에 늘어나는 판수
    ad_daily_max: 5,        // 하루에 광고로 늘릴 수 있는 최대 횟수
};

const sha256 = (s) => crypto.createHash("sha256").update(s).digest("hex");
const b64url = (buf) => Buffer.from(buf).toString("base64url");
const nowIso = () => new Date().toISOString();

// 한국 시간 기준 날짜 (하루 판수가 자정에 초기화)
export function kstDay(ms = Date.now()) {
    return new Date(ms + KST_MS).toISOString().slice(0, 10);
}

export function migrate(db) {
    db.exec(`
        CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            public_id TEXT NOT NULL UNIQUE,
            provider TEXT NOT NULL,
            subject_hash TEXT NOT NULL UNIQUE,
            ad_free INTEGER NOT NULL DEFAULT 0,
            ad_free_note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            last_login_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS account_tokens (
            token_hash TEXT PRIMARY KEY,
            account_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            expires_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS play_days (
            account_id INTEGER NOT NULL,
            day TEXT NOT NULL,
            used INTEGER NOT NULL DEFAULT 0,
            bonus INTEGER NOT NULL DEFAULT 0,
            ads INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (account_id, day)
        );
        CREATE TABLE IF NOT EXISTS ad_rewards (
            transaction_id TEXT PRIMARY KEY,
            account_id INTEGER NOT NULL,
            at TEXT NOT NULL
        );
    `);
    // 이전 버전 표에 계정 칸 추가
    const addCol = (table, col, def) => {
        const cols = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
        if (cols.length && !cols.includes(col)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${def}`);
    };
    addCol("sanctions", "account", "TEXT NOT NULL DEFAULT ''");
    addCol("reports", "reporter_account", "TEXT NOT NULL DEFAULT ''");
    addCol("reports", "target_account", "TEXT NOT NULL DEFAULT ''");
}

export function makeAccounts({ db, env = {}, getSetting, setSetting, audit, providers: providerOverride, fetchImpl = fetch, ssvKeys }) {
    const publicUrl = (env.PUBLIC_URL || "https://spw.cloudish.cloud").replace(/\/$/, "");
    const pepper = (() => {
        let p = env.ACCOUNT_PEPPER || getSetting("account_pepper", "");
        if (!p) { p = crypto.randomBytes(32).toString("hex"); setSetting("account_pepper", p); }
        return p;
    })();
    const logins = new Map();       // 로그인 진행 중 (메모리, 10분)

    const policy = () => ({ ...DEFAULT_POLICY, ...getSetting("policy", {}) });

    // ---- 제공자 (테스트에서는 providerOverride 로 바꿔 끼움)
    const real = {
        google: env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && (() => {
            const jwks = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));
            return {
                authorizeUrl: (s) => "https://accounts.google.com/o/oauth2/v2/auth?" + new URLSearchParams({
                    client_id: env.GOOGLE_CLIENT_ID, redirect_uri: s.redirect, response_type: "code", scope: "openid",
                    state: s.id, code_challenge: s.challenge, code_challenge_method: "S256", prompt: "select_account",
                }),
                async exchange(params, s) {
                    const r = await fetchImpl("https://oauth2.googleapis.com/token", {
                        method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
                        body: new URLSearchParams({ code: params.code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
                            redirect_uri: s.redirect, grant_type: "authorization_code", code_verifier: s.verifier }),
                    });
                    const d = await r.json();
                    if (!d.id_token) throw new Error("google token: " + (d.error || r.status));
                    const { payload } = await jwtVerify(d.id_token, jwks, { issuer: ["https://accounts.google.com", "accounts.google.com"], audience: env.GOOGLE_CLIENT_ID });
                    return String(payload.sub);
                },
            };
        })(),
        apple: env.APPLE_SERVICE_ID && env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY && (() => {
            const jwks = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
            const clientSecret = async () => {
                const key = await importPKCS8(env.APPLE_PRIVATE_KEY.replace(/\\n/g, "\n"), "ES256");
                return new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: env.APPLE_KEY_ID })
                    .setIssuer(env.APPLE_TEAM_ID).setIssuedAt().setExpirationTime("5m")
                    .setAudience("https://appleid.apple.com").setSubject(env.APPLE_SERVICE_ID).sign(key);
            };
            return {
                // 이름·이메일을 요청하지 않음 (scope 없음)
                authorizeUrl: (s) => "https://appleid.apple.com/auth/authorize?" + new URLSearchParams({
                    client_id: env.APPLE_SERVICE_ID, redirect_uri: s.redirect, response_type: "code", response_mode: "form_post", state: s.id,
                }),
                async exchange(params, s) {
                    const r = await fetchImpl("https://appleid.apple.com/auth/token", {
                        method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
                        body: new URLSearchParams({ client_id: env.APPLE_SERVICE_ID, client_secret: await clientSecret(), code: params.code,
                            grant_type: "authorization_code", redirect_uri: s.redirect }),
                    });
                    const d = await r.json();
                    if (!d.id_token) throw new Error("apple token: " + (d.error || r.status));
                    const { payload } = await jwtVerify(d.id_token, jwks, { issuer: "https://appleid.apple.com", audience: env.APPLE_SERVICE_ID });
                    return String(payload.sub);
                },
            };
        })(),
    };
    const providers = providerOverride || Object.fromEntries(Object.entries(real).filter(([, v]) => v));
    const enabled = () => PROVIDERS.filter((p) => providers[p]);

    // ---- 계정
    function upsertAccount(provider, subject) {
        const h = sha256(pepper + ":" + provider + ":" + subject);
        const t = nowIso();
        let row = db.prepare("SELECT * FROM accounts WHERE subject_hash = ?").get(h);
        if (!row) {
            const pid = crypto.randomBytes(6).toString("hex").toUpperCase();    // 문의·결제 연결용 공개 번호
            db.prepare("INSERT INTO accounts (public_id, provider, subject_hash, created_at, last_login_at) VALUES (?, ?, ?, ?, ?)").run(pid, provider, h, t, t);
            row = db.prepare("SELECT * FROM accounts WHERE subject_hash = ?").get(h);
        } else {
            db.prepare("UPDATE accounts SET last_login_at = ? WHERE id = ?").run(t, row.id);
        }
        return row;
    }

    function issueToken(accountId) {
        const token = crypto.randomBytes(32).toString("base64url");
        db.prepare("INSERT INTO account_tokens (token_hash, account_id, created_at, expires_at) VALUES (?, ?, ?, ?)")
            .run(sha256(token), accountId, nowIso(), Date.now() + TOKEN_DAYS * 864e5);
        return token;
    }

    function accountByToken(token) {
        if (!token) return null;
        const t = db.prepare("SELECT account_id, expires_at FROM account_tokens WHERE token_hash = ?").get(sha256(String(token)));
        if (!t || t.expires_at < Date.now()) return null;
        return db.prepare("SELECT * FROM accounts WHERE id = ?").get(t.account_id) || null;
    }

    function bearer(req) {
        const h = String(req.headers.authorization || "");
        return h.startsWith("Bearer ") ? h.slice(7).trim() : "";
    }

    function dayRow(accountId, day = kstDay()) {
        return db.prepare("SELECT used, bonus, ads FROM play_days WHERE account_id = ? AND day = ?").get(accountId, day) || { used: 0, bonus: 0, ads: 0 };
    }

    // 오늘 판수 상태 (베타·광고 제거 계정은 무제한)
    function plays(acc) {
        const pol = policy();
        const d = dayRow(acc.id);
        const unlimited = pol.phase !== "live" || !!acc.ad_free;
        const limit = pol.daily_free + d.bonus;
        return {
            phase: pol.phase, unlimited, limit, used: d.used, bonus: d.bonus,
            left: unlimited ? -1 : Math.max(limit - d.used, 0),
            ads_today: d.ads, ad_daily_max: pol.ad_daily_max, ad_reward: pol.ad_reward,
            ads_enabled: pol.phase === "live" && !acc.ad_free && d.ads < pol.ad_daily_max,
        };
    }

    function publicAccount(acc) {
        return { id: acc.public_id, provider: acc.provider, provider_name: PROVIDER_NAMES[acc.provider] || acc.provider,
            ad_free: !!acc.ad_free, created_at: acc.created_at, plays: plays(acc) };
    }

    function deleteAccount(acc) {
        db.prepare("DELETE FROM account_tokens WHERE account_id = ?").run(acc.id);
        db.prepare("DELETE FROM play_days WHERE account_id = ?").run(acc.id);
        db.prepare("DELETE FROM ad_rewards WHERE account_id = ?").run(acc.id);
        db.prepare("DELETE FROM accounts WHERE id = ?").run(acc.id);
    }

    // 오래된 기록 정리: 지난 판수(8일), 만료 토큰, 광고 거래 번호(30일)
    function purge(now = Date.now()) {
        db.prepare("DELETE FROM play_days WHERE day < ?").run(kstDay(now - 8 * 864e5));
        db.prepare("DELETE FROM account_tokens WHERE expires_at < ?").run(now);
        db.prepare("DELETE FROM ad_rewards WHERE at < ?").run(new Date(now - 30 * 864e5).toISOString());
        for (const [k, s] of logins) if (s.expires < now) logins.delete(k);
    }

    // 판 시작: 남은 판수가 없는 계정을 알려 주고, 모두 가능하면 1판씩 차감
    function startPlays(publicIds) {
        const pol = policy();
        const accs = publicIds.map((id) => db.prepare("SELECT * FROM accounts WHERE public_id = ?").get(String(id))).filter(Boolean);
        if (pol.phase !== "live") return { ok: true, blocked: [], phase: pol.phase };
        const day = kstDay();
        const counted = accs.filter((a) => !a.ad_free);
        const blocked = counted.filter((a) => { const d = dayRow(a.id, day); return d.used >= pol.daily_free + d.bonus; }).map((a) => a.public_id);
        if (blocked.length) return { ok: false, blocked, phase: pol.phase };
        for (const a of counted) {
            db.prepare(`INSERT INTO play_days (account_id, day, used) VALUES (?, ?, 1)
                ON CONFLICT(account_id, day) DO UPDATE SET used = used + 1`).run(a.id, day);
        }
        return { ok: true, blocked: [], phase: pol.phase };
    }

    function grantAd(acc, transactionId) {
        const pol = policy();
        const day = kstDay();
        const d = dayRow(acc.id, day);
        if (d.ads >= pol.ad_daily_max) return { ok: false, reason: "오늘 광고 보상을 모두 받았어요" };
        try {
            db.prepare("INSERT INTO ad_rewards (transaction_id, account_id, at) VALUES (?, ?, ?)").run(String(transactionId), acc.id, nowIso());
        } catch { return { ok: false, reason: "이미 받은 보상이에요" }; }
        db.prepare(`INSERT INTO play_days (account_id, day, bonus, ads) VALUES (?, ?, ?, 1)
            ON CONFLICT(account_id, day) DO UPDATE SET bonus = bonus + ?, ads = ads + 1`).run(acc.id, day, pol.ad_reward, pol.ad_reward);
        return { ok: true };
    }

    // ---- AdMob 서버 측 확인 (SSV): 구글이 서명한 콜백만 인정
    let keyCache = { at: 0, keys: {} };
    async function admobKeys() {
        if (ssvKeys) return ssvKeys;
        if (Date.now() - keyCache.at < 6 * 3600e3 && Object.keys(keyCache.keys).length) return keyCache.keys;
        const r = await fetchImpl("https://www.gstatic.com/admob/reward/verifier-keys.json");
        const d = await r.json();
        keyCache = { at: Date.now(), keys: Object.fromEntries((d.keys || []).map((k) => [String(k.keyId), k.pem])) };
        return keyCache.keys;
    }
    async function verifySsv(rawQuery) {
        const i = rawQuery.indexOf("&signature=");
        if (i < 0) return false;
        const message = rawQuery.slice(0, i);
        const params = new URLSearchParams(rawQuery);
        const pem = (await admobKeys())[params.get("key_id")];
        if (!pem) return false;
        const sig = Buffer.from(params.get("signature") || "", "base64url");
        return crypto.verify("sha256", Buffer.from(message), pem, sig);
    }

    // ---- 화면
    const page = (title, text, ok = true) => `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#fff7e8;color:#1d3557;font-family:system-ui,"Apple SD Gothic Neo","Malgun Gothic",sans-serif}
.c{background:#fffdf6;border:3px solid #1d3557;border-radius:20px;box-shadow:6px 6px 0 rgba(29,53,87,.18);padding:28px 30px;max-width:360px;text-align:center}
h1{font-size:24px;margin:0 0 10px;color:${ok ? "#2a9d8f" : "#e63946"}}p{margin:0;line-height:1.6}</style></head>
<body><div class="c"><h1>${title}</h1><p>${text}</p></div><script>setTimeout(function(){try{window.close()}catch(e){}},1500)</script></body></html>`;

    function sendHtml(res, status, html) {
        res.writeHead(status, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" });
        res.end(html);
    }

    // ---- 라우팅 (처리하면 true)
    async function handlePublic(req, res, url, { json, readJson, readForm }) {
        const p = url.pathname, m = req.method;
        if (p === "/api/auth/providers" && m === "GET") {
            return json(res, 200, { providers: enabled().map((id) => ({ id, name: PROVIDER_NAMES[id] })) }, true), true;
        }
        if (p === "/api/auth/start" && m === "POST") {
            const b = await readJson(req);
            const prov = String(b.provider || "");
            if (!providers[prov]) return json(res, 400, { error: "지원하지 않는 로그인이에요" }, true), true;
            purge();
            const id = crypto.randomBytes(18).toString("base64url");
            const verifier = crypto.randomBytes(32).toString("base64url");
            logins.set(id, { id, provider: prov, verifier, challenge: b64url(crypto.createHash("sha256").update(verifier).digest()),
                redirect: `${publicUrl}/api/auth/callback/${prov}`, status: "pending", expires: Date.now() + LOGIN_TTL_MS });
            return json(res, 200, { id, url: `${publicUrl}/api/auth/go?id=${id}` }, true), true;
        }
        if (p === "/api/auth/go" && m === "GET") {
            const s = logins.get(url.searchParams.get("id") || "");
            if (!s || s.status !== "pending" || s.expires < Date.now()) return sendHtml(res, 400, page("로그인 시간이 지났어요", "게임에서 로그인을 다시 눌러 주세요.", false)), true;
            res.writeHead(302, { Location: providers[s.provider].authorizeUrl(s), "Cache-Control": "no-store" });
            res.end();
            return true;
        }
        const cb = p.match(/^\/api\/auth\/callback\/(google|apple)$/);
        if (cb && (m === "GET" || m === "POST")) {
            const params = m === "POST" ? await readForm(req) : Object.fromEntries(url.searchParams);
            const s = logins.get(params.state || "");
            if (!s || s.provider !== cb[1] || s.status !== "pending" || s.expires < Date.now()) {
                return sendHtml(res, 400, page("로그인 시간이 지났어요", "게임에서 로그인을 다시 눌러 주세요.", false)), true;
            }
            if (params.error || !params.code) {
                s.status = "error"; s.error = "로그인을 취소했어요";
                return sendHtml(res, 200, page("로그인 취소", "게임으로 돌아가 주세요.", false)), true;
            }
            try {
                const sub = await providers[s.provider].exchange(params, s);
                const acc = upsertAccount(s.provider, sub);
                s.token = issueToken(acc.id);
                s.status = "done";
                return sendHtml(res, 200, page("로그인 완료", "게임으로 돌아가 주세요.<br>이 창은 닫아도 돼요.")), true;
            } catch (e) {
                console.error("[auth]", e.message);
                s.status = "error"; s.error = "로그인을 확인하지 못했어요";
                return sendHtml(res, 200, page("로그인 실패", "잠시 뒤 게임에서 다시 시도해 주세요.", false)), true;
            }
        }
        if (p === "/api/auth/poll" && m === "GET") {
            const s = logins.get(url.searchParams.get("id") || "");
            if (!s || s.expires < Date.now()) return json(res, 200, { status: "expired" }, true), true;
            if (s.status === "done") {
                logins.delete(s.id);           // 토큰은 한 번만 내준다
                const acc = accountByToken(s.token);
                return json(res, 200, { status: "done", token: s.token, account: acc && publicAccount(acc) }, true), true;
            }
            return json(res, 200, { status: s.status, error: s.error || "" }, true), true;
        }
        if (p === "/api/auth/logout" && m === "POST") {
            db.prepare("DELETE FROM account_tokens WHERE token_hash = ?").run(sha256(bearer(req)));
            return json(res, 200, { ok: true }, true), true;
        }
        if (p === "/api/account" && (m === "GET" || m === "DELETE")) {
            const acc = accountByToken(bearer(req));
            if (!acc) return json(res, 401, { error: "로그인이 필요해요" }, true), true;
            if (m === "GET") return json(res, 200, { account: publicAccount(acc) }, true), true;
            deleteAccount(acc);
            audit("(본인)", "account_delete", acc.public_id);
            return json(res, 200, { ok: true }, true), true;
        }
        if (p === "/api/ads/ssv" && m === "GET") {
            const raw = url.search.slice(1);
            if (!(await verifySsv(raw).catch(() => false))) return json(res, 403, { error: "bad signature" }), true;
            const q = new URLSearchParams(raw);
            const acc = db.prepare("SELECT * FROM accounts WHERE public_id = ?").get(String(q.get("custom_data") || q.get("user_id") || ""));
            if (!acc) return json(res, 200, { ok: false, reason: "no account" }), true;     // 200: AdMob 이 재시도하지 않게
            return json(res, 200, grantAd(acc, q.get("transaction_id") || crypto.randomUUID())), true;
        }
        return false;
    }

    async function handleInternal(req, res, url, { json, readJson }) {
        const p = url.pathname, m = req.method;
        if (p === "/internal/account/verify" && m === "POST") {
            const acc = accountByToken((await readJson(req)).token);
            return json(res, 200, { account: acc ? publicAccount(acc) : null }), true;
        }
        if (p === "/internal/plays/start" && m === "POST") {
            const b = await readJson(req);
            return json(res, 200, startPlays(Array.isArray(b.accounts) ? b.accounts.slice(0, 16) : [])), true;
        }
        return false;
    }

    async function handleAdmin(req, res, url, email, { json, readJson }) {
        const p = url.pathname, m = req.method;
        if (p === "/admin/api/policy" && m === "GET") {
            const n = db.prepare("SELECT COUNT(*) AS n FROM accounts").get().n;
            const adFree = db.prepare("SELECT COUNT(*) AS n FROM accounts WHERE ad_free = 1").get().n;
            const today = db.prepare("SELECT COUNT(*) AS n, COALESCE(SUM(used),0) AS used, COALESCE(SUM(ads),0) AS ads FROM play_days WHERE day = ?").get(kstDay());
            return json(res, 200, { policy: policy(), providers: enabled(), stats: { accounts: n, ad_free: adFree, today } }), true;
        }
        if (p === "/admin/api/policy" && m === "PUT") {
            const b = await readJson(req);
            const v = {
                phase: b.phase === "live" ? "live" : "beta",
                daily_free: Math.max(0, Math.min(100, parseInt(b.daily_free, 10) || 0)),
                ad_reward: Math.max(0, Math.min(10, parseInt(b.ad_reward, 10) || 0)),
                ad_daily_max: Math.max(0, Math.min(50, parseInt(b.ad_daily_max, 10) || 0)),
            };
            setSetting("policy", v);
            audit(email, "policy_update", JSON.stringify(v));
            return json(res, 200, v), true;
        }
        // 계정 찾기 (공개 번호) · 광고 제거 수동 지급 (스토어 결제 연동 전까지)
        const am = p.match(/^\/admin\/api\/accounts\/([0-9A-F]{12})$/);
        if (am && m === "GET") {
            const acc = db.prepare("SELECT * FROM accounts WHERE public_id = ?").get(am[1]);
            if (!acc) return json(res, 404, { error: "없는 계정이에요" }), true;
            return json(res, 200, { account: { ...publicAccount(acc), ad_free_note: acc.ad_free_note, last_login_at: acc.last_login_at } }), true;
        }
        if (am && m === "PUT") {
            const b = await readJson(req);
            const r = db.prepare("UPDATE accounts SET ad_free = ?, ad_free_note = ? WHERE public_id = ?").run(b.ad_free ? 1 : 0, String(b.note || "").slice(0, 200), am[1]);
            if (!r.changes) return json(res, 404, { error: "없는 계정이에요" }), true;
            audit(email, b.ad_free ? "ad_free_on" : "ad_free_off", `${am[1]} ${String(b.note || "").slice(0, 100)}`);
            return json(res, 200, { ok: true }), true;
        }
        return false;
    }

    return { handlePublic, handleInternal, handleAdmin, purge, policy, startPlays, grantAd, upsertAccount, issueToken, accountByToken, enabled };
}
