// node --test test.mjs — 구글 검증 대신 가짜 검증기로 관리 API 흐름을 확인
import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { openDb, createApp, compareVersion } from "./server.mjs";

const fakeVerify = async (cred) => {
    if (cred.startsWith("ok:")) return { email: cred.slice(3), email_verified: true };
    throw new Error("bad");
};

async function withServer(fn) {
    const db = openDb(":memory:");
    const srv = http.createServer(createApp({ db, clientId: "", ownerEmails: ["Owner@Gmail.com"], verifyGoogle: fakeVerify, secureCookie: false }));
    await new Promise((r) => srv.listen(0, r));
    const base = `http://127.0.0.1:${srv.address().port}`;
    let cookie = "";
    const call = async (method, path, body, extra = {}) => {
        const r = await fetch(base + path, {
            method, body: body === undefined ? undefined : JSON.stringify(body),
            headers: { "Content-Type": "application/json", "X-SPW-Admin": "1", cookie, ...extra },
        });
        const sc = r.headers.get("set-cookie");
        if (sc) cookie = sc.split(";")[0];
        return { status: r.status, data: await r.json().catch(() => ({})), headers: r.headers };
    };
    try { await fn(call); } finally { srv.close(); }
}

test("버전 비교", () => {
    assert.equal(compareVersion("0.2.10", "0.2.9"), 1);
    assert.equal(compareVersion("0.2", "0.2.0"), 0);
    assert.equal(compareVersion("0.1.9", "0.2.0"), -1);
});

test("로그인·권한·공지·점검", async () => {
    await withServer(async (call) => {
        assert.equal((await call("GET", "/admin/api/me")).status, 401);
        assert.equal((await call("POST", "/admin/api/login", { credential: "bad" })).status, 401);
        assert.equal((await call("POST", "/admin/api/login", { credential: "ok:stranger@gmail.com" })).status, 403);
        // 다른 사이트에서 온 요청(헤더 없음)은 거절
        assert.equal((await call("POST", "/admin/api/login", { credential: "ok:owner@gmail.com" }, { "X-SPW-Admin": "" })).status, 403);
        const login = await call("POST", "/admin/api/login", { credential: "ok:owner@gmail.com" });
        assert.equal(login.status, 200);
        assert.match(login.headers.get("set-cookie"), /HttpOnly; SameSite=Strict/);
        assert.equal((await call("GET", "/admin/api/me")).data.email, "owner@gmail.com");

        // 공지 작성 → 공개 API 필터
        await call("POST", "/admin/api/notices", { kind: "banner", title: "점검 안내", body: "22시", platforms: ["pc"] });
        await call("POST", "/admin/api/notices", { kind: "notice", title: "모두에게" });
        await call("POST", "/admin/api/notices", { kind: "notice", title: "임시", published: false });
        await call("POST", "/admin/api/notices", { kind: "notice", title: "미래", starts_at: new Date(Date.now() + 864e5).toISOString() });
        await call("POST", "/admin/api/notices", { kind: "patch", title: "구버전용", max_version: "0.1.9" });
        assert.equal((await call("POST", "/admin/api/notices", { kind: "zzz", title: "x" })).status, 400);
        let pub = await call("GET", "/api/notices?platform=android&version=0.2.0");
        assert.deepEqual(pub.data.notices.map((n) => n.title), ["모두에게"]);
        assert.equal(pub.headers.get("access-control-allow-origin"), "*");
        pub = await call("GET", "/api/notices?platform=pc&version=0.1.0");
        assert.deepEqual(pub.data.notices.map((n) => n.title).sort(), ["구버전용", "모두에게", "점검 안내"].sort());

        // 수정·삭제
        const list = (await call("GET", "/admin/api/notices")).data.notices;
        const id = list.find((n) => n.title === "모두에게").id;
        assert.equal((await call("PUT", `/admin/api/notices/${id}`, { kind: "notice", title: "바뀐 제목", pinned: true })).status, 200);
        assert.equal((await call("DELETE", `/admin/api/notices/${id}`)).status, 200);
        assert.equal((await call("DELETE", `/admin/api/notices/${id}`)).status, 404);

        // 점검 모드
        await call("PUT", "/admin/api/maintenance", { on: true, message: "점검 중" });
        assert.deepEqual((await call("GET", "/api/status")).data.maintenance, { on: true, message: "점검 중" });

        // 관리자 추가·삭제, 서버 설정 계정은 못 지움
        assert.equal((await call("POST", "/admin/api/admins", { email: "friend@gmail.com" })).status, 200);
        assert.equal((await call("DELETE", "/admin/api/admins/owner%40gmail.com")).status, 400);
        assert.equal((await call("DELETE", "/admin/api/admins/friend%40gmail.com")).status, 200);
        assert.ok((await call("GET", "/admin/api/audit")).data.audit.length > 5);

        // 로그아웃 후 접근 불가
        await call("POST", "/admin/api/logout");
        assert.equal((await call("GET", "/admin/api/notices")).status, 401);
    });
});

test("자기 자신은 지울 수 없음", async () => {
    await withServer(async (call) => {
        await call("POST", "/admin/api/login", { credential: "ok:owner@gmail.com" });
        await call("POST", "/admin/api/admins", { email: "b@x.com" });
        // b 로 로그인
        const b = await call("POST", "/admin/api/login", { credential: "ok:b@x.com" });
        assert.equal(b.status, 200);
        assert.equal((await call("GET", "/admin/api/me")).data.email, "b@x.com");
        // b 세션으로 자기 자신 삭제는 불가
        assert.equal((await call("DELETE", "/admin/api/admins/b%40x.com")).status, 400);
    });
});

test("신고·제재·금칙어 (게임 서버 전용 주소 포함)", async () => {
    await withServer(async (call) => {
        const dev = (s) => s.padEnd(16, "x");
        // 게임 서버 → 신고 접수 (로그인 없이), 프록시를 거친 요청은 거절
        const rep = { reporter: { nick: "철수", device: dev("aaaa") }, target: { nick: "나쁜애", device: dev("bbbb") }, room: "방1", reason: "abuse", detail: "욕함",
            chat: [{ t: "2026-11-27T00:00:00Z", nick: "나쁜애", text: "욕설" }] };
        assert.equal((await call("POST", "/internal/reports", rep, { "X-Forwarded-For": "1.2.3.4" })).status, 404);
        const r1 = await call("POST", "/internal/reports", rep);
        assert.equal(r1.status, 200);
        const r2 = await call("POST", "/internal/reports", rep);
        assert.equal(r2.data.duplicate, true);               // 10분 안 같은 신고는 하나로
        // 관리자 로그인 전엔 볼 수 없음
        assert.equal((await call("GET", "/admin/api/reports")).status, 401);
        await call("POST", "/admin/api/login", { credential: "ok:owner@gmail.com" });
        let list = await call("GET", "/admin/api/reports");
        assert.equal(list.data.reports.length, 1);
        assert.equal(list.data.reports[0].chat[0].text, "욕설");
        // 제재 → 게임 서버 목록에 보이고, 신고는 처리됨
        const s = await call("POST", "/admin/api/sanctions", { device: dev("bbbb"), nick: "나쁜애", kind: "mute", hours: 24, reason: "욕설", report_id: list.data.reports[0].id });
        assert.equal(s.status, 200);
        assert.equal((await call("POST", "/admin/api/sanctions", { device: "x", kind: "ban" })).status, 400);
        let mod = await call("GET", "/internal/moderation");
        assert.deepEqual(mod.data.sanctions.map((x) => [x.device, x.kind]), [[dev("bbbb"), "mute"]]);
        assert.equal((await call("GET", "/admin/api/reports?status=open")).data.reports.length, 0);
        // 제재 해제
        assert.equal((await call("DELETE", "/admin/api/sanctions/" + s.data.id)).status, 200);
        mod = await call("GET", "/internal/moderation");
        assert.equal(mod.data.sanctions.length, 0);
        // 금칙어
        await call("POST", "/admin/api/words", { word: " 나 쁜말 " });
        assert.equal((await call("POST", "/admin/api/words", { word: "a" })).status, 400);
        mod = await call("GET", "/internal/moderation");
        assert.deepEqual(mod.data.words, ["나쁜말"]);
        await call("DELETE", "/admin/api/words/" + encodeURIComponent("나쁜말"));
        assert.deepEqual((await call("GET", "/internal/moderation")).data.words, []);
    });
});

test("30일 지난 신고 삭제", async () => {
    const db = openDb(":memory:");
    const app = createApp({ db, clientId: "", ownerEmails: [], verifyGoogle: async () => ({}) });
    const old = new Date(Date.now() - 31 * 864e5).toISOString();
    db.prepare("INSERT INTO reports (created_at, reporter_nick, target_nick, reason) VALUES (?, 'a', 'b', 'abuse')").run(old);
    db.prepare("INSERT INTO reports (created_at, reporter_nick, target_nick, reason) VALUES (?, 'a', 'c', 'abuse')").run(new Date().toISOString());
    assert.equal(app.purgeOld(), 1);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM reports").get().n, 1);
});
