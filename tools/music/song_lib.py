"""뒷북의 달인 곡 만들기 도구 — 곡 정의(마디 목록) → 반주 ogg + 노트 json + 북 소리

곡 하나를 통째로 쓰고, 북 파트(둥 = 킥 역할, 딱 = 스네어 역할)가 곧 게임 노트가 된다.
  북 마디(call·resp, 패턴 pat 이 있는 마디): 반주에 북 파트가 들어 있고(진행자가 치는 모습), 플레이어도 같은 자리에서 함께 친다
    (call·resp 이름은 예전 선창·따라 치기 구성에서 온 것. 지금은 둘 다 그냥 '북 마디')
  그 밖(intro·rest·break·outro): 밴드만 (북 쉼)

마디 하나 = dict: role, chord, pat(북 패턴 이름, call/resp 만), brass(후렴 브라스 여부), sax(색소폰 리프 이름)
북 패턴 = {"don": [칸...], "ka": [칸...], "hold": {칸: 길이}}   칸 = 16분음표 (0~15), hold = 둥 피버(누르고 있는 칸 수)

필요: pip install pretty_midi mido tinysoundfont(--no-deps), 사운드폰트 GeneralUser GS (sfrender.SF2 경로)
"""
import json
import os
import subprocess

import numpy as np

import sfrender as R

CH_BASS, CH_CLAV, CH_EP, CH_SAX, CH_BRASS, CH_DRUM = 0, 1, 2, 3, 4, 9
PROGRAMS = {CH_BASS: (0, 33), CH_CLAV: (0, 7), CH_EP: (0, 4), CH_SAX: (0, 65), CH_BRASS: (0, 61), CH_DRUM: (128, 0)}
DRUM_GAIN = 0.75
MAX_TURN_BARS = 4                    # 차례 하나 = 북 마디 최대 4개 (점수 정산·노트 발표 단위)
ROLL_STEP_16 = 1                     # 피버 '드르륵' 간격 = 16분음표 (게임의 ROLL_STEP 0.125초와 같음, 120 BPM)


def make_drums():
    """둥: 태고 북 + 킥 / 딱: 사이드스틱 + 스네어 살짝. 앞쪽 무음을 잘라 바로 소리 나게, 꼬리는 짧게"""
    don = R.render([(0.0, 0.4, 5, 45, 120)], {5: (0, 116)}, 0.8) * 0.9 \
        + R.render([(0.0, 0.2, 9, 36, 110)], {9: (128, 0)}, 0.8) * 0.8
    ka = R.render([(0.0, 0.1, 9, 37, 120)], {9: (128, 0)}, 0.5) * 1.0 \
        + R.render([(0.0, 0.1, 9, 38, 70)], {9: (128, 0)}, 0.5) * 0.45
    out = []
    for x, length, peak in ((don, 0.42, 0.9), (ka, 0.22, 0.75)):
        m = x.mean(axis=1)
        start = int(np.argmax(np.abs(m) > 0.02 * np.abs(m).max()))
        m = m[start:start + int(length * R.SR)]
        fade = int(0.04 * R.SR)
        m[-fade:] *= np.linspace(1, 0, fade)
        m = m / (np.abs(m).max() + 1e-9) * peak
        out.append(np.stack([m, m], axis=1))
    return out[0], out[1]


def funk_arrange(b, bar, ctx, add):
    """펑크 편곡 (베이스·클라비넷·전자 피아노·하이햇·브라스·색소폰) — 마디 하나"""
    bars, chords, patterns, riffs, n_bars = ctx["bars"], ctx["chords"], ctx["patterns"], ctx["riffs"], ctx["n_bars"]
    role = bar["role"]
    ch = chords[bar["chord"]]
    root = ch["root"]
    last = role == "outro"
    pat = patterns.get(bar.get("pat")) if bar.get("pat") else None
    # 베이스: 둥 자리에 근음 (킥과 맞물림) + 옥타브 튕김 + 다음 마디 근음으로 이끄는 음
    anchor = pat["don"] if pat else [0, 3, 8, 10]
    if last:
        add(b, 0, 8, CH_BASS, root, 112)
    elif role != "break":
        for s in anchor:
            add(b, s, 2 if s in (0, 8) else 1, CH_BASS, root, 110 if s in (0, 8) else 96)
        for s in (6, 14):
            if s not in anchor:
                add(b, s, 1, CH_BASS, root + 12, 92)
        nxt = chords[bars[b + 1]["chord"]]["root"] if b + 1 < n_bars else root
        if nxt != root:
            add(b, 15, 1, CH_BASS, nxt - 1, 84)
    else:
        add(b, 0, 6, CH_BASS, root, 100)                       # 간주: 긴 음으로 쉬어 가기
        add(b, 8, 6, CH_BASS, root + 7, 90)
    # 클라비넷: 16분 엇박 찹
    if not last and role != "break":
        for s, v in ((2, 78), (3, 60), (6, 82), (10, 78), (11, 60), (14, 82)):
            for k in ch["voicing"][:4]:
                add(b, s, 0.6, CH_CLAV, k, v)
    # 전자 피아노: 마디 첫 박 화음 + 3박 엇박
    for k in ch["voicing"]:
        add(b, 0, 7 if not last else 16, CH_EP, k + 12, (70 if role != "break" else 80) if not last else 84)
        if not last and role != "break":
            add(b, 10, 2, CH_EP, k + 12, 58)
    # 하이햇: 시간 맞추기용으로 작게
    if not last:
        for k in range(8):
            add(b, k * 2, 0.5, CH_DRUM, 42, (46 if k % 2 == 0 else 32) if role != "break" else 28)
        if b % 2 == 1 and role != "break":
            add(b, 14, 1, CH_DRUM, 46, 34)
    else:
        add(b, 0, 8, CH_DRUM, 49, 96)
    # 후렴 브라스: 북과 겹치지 않는 엇박 자리(6·14)에 짧게
    if bar.get("brass"):
        for s in (6, 14):
            for k in ch["voicing"][1:4]:
                add(b, s, 1, CH_BRASS, k + 12, 88)
    # 색소폰 리프
    if bar.get("sax"):
        for (s, d, k) in riffs[bar["sax"]]:
            add(b, s, d, CH_SAX, k, 92)


def build(song: dict, out_audio_dir: str, drums_dir: str = None, preview_path: str = None):
    bpm = float(song["bpm"])
    beat = 60.0 / bpm
    bar_len = beat * 4
    step = beat / 4
    bars = song["bars"]
    patterns = song["patterns"]
    chords = song["chords"]                 # 이름 → {"voicing": [...], "root": n}
    riffs = song.get("riffs", {})
    n_bars = len(bars)
    length = n_bars * bar_len + 2.5
    notes = []

    def add(b, s, d, ch, key, vel):
        notes.append((b * bar_len + s * step, d * step, ch, key, vel))

    ctx = {"bars": bars, "chords": chords, "patterns": patterns, "riffs": riffs, "n_bars": n_bars, "song": song}
    arrange = song.get("arrange", funk_arrange)
    for b, bar in enumerate(bars):
        arrange(b, bar, ctx, add)
    for (b, s, d, k, v) in song.get("extra_brass", []):
        add(b if b >= 0 else n_bars + b, s, d, CH_BRASS, k, v)
    for (b, s, d, ch, k, v) in song.get("extra", []):
        add(b if b >= 0 else n_bars + b, s, d, ch, k, v)


    don, ka = make_drums()

    def place(buf, sample, t, gain=1.0):
        i = int(round(t * R.SR))
        j = min(i + len(sample), len(buf))
        if j > i:
            buf[i:j] += sample[: j - i] * gain

    band = R.render(notes, song.get("programs", PROGRAMS), length,
                    cc={ch: [(7, v)] for ch, v in song.get("mix", {}).items()})      # mix: 채널 볼륨 (CC7, 기본 100)
    band = band / (np.abs(band).max() + 1e-9) * song.get("band_level", 0.55)
    host = np.zeros_like(band)
    # 북 마디(pat 이 있는 마디)가 이어진 구간 = 차례 (최대 MAX_TURN_BARS 마디씩). 진행자와 플레이어가 같은 자리에서 함께 친다
    #   반주에 북 파트가 그대로 들어 있음 (진행자 북) → 내가 치는 소리는 그 위에 겹친다
    turns = []
    b = 0
    while b < n_bars:
        if not bars[b].get("pat"):
            b += 1
            continue
        c0 = b
        while b < n_bars and bars[b].get("pat") and b - c0 < MAX_TURN_BARS:
            b += 1
        n = b - c0
        tnotes = []
        for k in range(n):
            p = patterns[bars[c0 + k]["pat"]]
            hold = p.get("hold", {})
            for lane, key in ((0, "don"), (1, "ka")):
                for s in p[key]:
                    ms = int(round((k * bar_len + s * step) * 1000))
                    h = hold.get(s, 0) if lane == 0 else 0
                    e = -1 if h <= 0 else int(round((k * bar_len + (s + h) * step) * 1000))
                    tnotes.append([ms, lane, e])
        tnotes.sort()
        a = c0 * bar_len
        for (ms, lane, e) in tnotes:
            smp = don if lane == 0 else ka
            place(host, smp, a + ms / 1000.0)
            if e >= 0:                                   # 피버: 누르는 동안 16분음표마다 작게
                t = ms + step * 1000 * ROLL_STEP_16
                while t < e - 20:
                    place(host, smp, a + t / 1000.0, 0.35)
                    t += step * 1000 * ROLL_STEP_16
        turns.append({"bars": n, "start": round(a, 4), "notes": tnotes})

    wet = song.get("reverb", 0.16)
    mix_b = R.reverb(band + host * DRUM_GAIN, wet=wet)
    scale = 1.0 / (np.abs(mix_b).max() + 1e-9)
    backing = R.soft_limit_fixed(mix_b * scale)
    os.makedirs(out_audio_dir, exist_ok=True)
    tmp = os.path.join(out_audio_dir, "_backing.wav")
    R.save_wav(tmp, backing)
    # 용량: Vorbis q0 (약 64kbps 스테레오) — 곡이 많아서
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(song.get("quality", 0)),
                    os.path.join(out_audio_dir, "backing.ogg")], check=True)
    os.remove(tmp)
    if preview_path:
        R.save_wav(preview_path, backing)
    if drums_dir:
        # 게임의 북 소리 (모노, 짧게). 진행자 북(반주 안)과 같은 소리
        from scipy.io import wavfile
        for name, x in (("don", don), ("ka", ka)):
            wavfile.write(os.path.join(drums_dir, name + ".wav"), R.SR, (np.clip(x[:, 0], -1, 1) * 32767).astype(np.int16))
    # 노트 사이가 너무 붙으면 칠 수 없음 (게임의 MIN_NOTE_GAP 0.09초)
    for tr in turns:
        ts = sorted(n[0] for n in tr["notes"])
        for x, y in zip(ts, ts[1:]):
            assert y - x >= 90, "%s: 노트가 너무 붙어요 (%d ms, 차례 %.2f초)" % (song["title"], y - x, tr["start"])
        for n in tr["notes"]:
            if n[2] >= 0:
                assert n[2] - n[0] >= 300, "%s: 피버가 너무 짧아요 (%d ms)" % (song["title"], n[2] - n[0])
    chart = {"title": song["title"], "bpm": bpm, "level": int(song.get("level", 3)), "length": round(n_bars * bar_len, 3), "turns": turns}
    # 게임이 읽는 노트: GDScript 상수 파일 (스크립트라서 내보내기에 항상 포함됨, JSON 은 필터에 안 걸리면 빠짐)
    with open(os.path.join(out_audio_dir, "song.gd"), "w") as f:
        f.write("extends RefCounted\n## 자동 생성 (tools/music/song_*.py) — 손으로 고치지 마세요\n")
        f.write("## turns: [{bars, start(차례 시작 초), notes: [[ms(차례 시작부터), 북(0 둥 1 딱), 끝 ms(-1 = 한 번 치기)]]}]\n")
        f.write("const DATA := " + json.dumps(chart, ensure_ascii=False) + "\n")
    roles = "".join("D" if x.get("pat") else {"intro": "I", "rest": ".", "outro": "O", "break": "b"}.get(x["role"], "?") for x in bars)
    return chart, roles


# ================================================================ 범용 편곡 (곡 = 데이터)
# 곡 dict 에 "layers" 를 주면 generic_arrange 를 쓴다. 마디 dict 에는 role 말고도 sec(구간 이름: intro·verse·chorus·break·outro …)
# 레이어 공통: ch(채널), vel, when(쓸 구간 목록, 없으면 outro 빼고 전부), roles(쓸 역할 목록), skip(뺄 구간·역할)
#   bass  style: anchor(둥 자리에 근음 + 엇박 옥타브) | eighths(8분 근음, oct 면 옥타브 번갈아) | long(긴 근음 + 5도)
#   chord steps: [(칸, 길이, 세기)] 화음 (voices = voicing 에서 쓸 범위 [시작, 끝], shift = 반음 이동)
#   power steps: 근음 파워코드 (근음+12·+19·+24)
#   arp   order: voicing 순서, every: 칸 간격, dur
#   perc  key(드럼 음), steps: [(칸, 세기)]
#   lead  key(마디 dict 에서 읽을 키, 기본 "lead") → song["riffs"][이름] = [(칸, 길이, 음)]
# steps·order 등은 {구간: 값, "default": 값} 로 구간마다 다르게 줄 수 있다. 마무리(outro) 마디: bass·chord·power 는 긴 음 하나, perc 는 outro_key


def _by_sec(v, sec):
    if isinstance(v, dict):
        return v.get(sec, v.get("default"))
    return v


def _active(layer, bar):
    sec, role = bar.get("sec", ""), bar["role"]
    if sec in layer.get("skip", ()) or role in layer.get("skip", ()):
        return False
    if "roles" in layer and role not in layer["roles"]:
        return False
    if "when" in layer:
        return sec in layer["when"] or role in layer["when"]
    return True


def generic_arrange(b, bar, ctx, add):
    import random
    rng = random.Random(b * 7919 + 13)
    song = ctx["song"]
    chords, patterns, riffs, bars, n_bars = ctx["chords"], ctx["patterns"], ctx["riffs"], ctx["bars"], ctx["n_bars"]
    ch = chords[bar["chord"]]
    root = ch["root"]
    sec = bar.get("sec", bar["role"])
    last = bar["role"] == "outro"
    pat = patterns.get(bar.get("pat")) if bar.get("pat") else None

    def hv(v):
        return max(1, min(127, int(v + rng.randint(-4, 4))))

    for L in song["layers"]:
        if last and L["type"] in ("bass", "chord", "power", "pad"):
            if not L.get("outro", True):
                continue
        elif not _active(L, bar):
            continue
        t, c, vel = L["type"], L["ch"], L.get("vel", 90)
        if t == "bass":
            off = L.get("shift", 0)
            if last:
                add(b, 0, 12, c, root + off, vel + 10)
                continue
            style = _by_sec(L.get("style", "anchor"), sec)
            if style == "anchor":
                anchor = pat["don"] if pat else _by_sec(L.get("anchor", [0, 3, 8, 10]), sec)
                for s in anchor:
                    add(b, s, 2 if s in (0, 8) else 1, c, root + off, hv(vel if s in (0, 8) else vel - 12))
                for s in L.get("pops", (6, 14)):
                    if s not in anchor:
                        add(b, s, 1, c, root + off + 12, hv(vel - 16))
            elif style == "boom":
                anchor = pat["don"] if pat else [0, 10]
                for i, s in enumerate(anchor):
                    nxt = anchor[i + 1] if i + 1 < len(anchor) else 16
                    add(b, s, max(1, nxt - s - 0.5), c, root + off, hv(vel if s in (0, 8) else vel - 10))
            elif style == "eighths":
                for k in range(8):
                    o = 12 if (L.get("oct") and k % 2 == 1) else 0
                    add(b, k * 2, 1.5 if not L.get("oct") else 1.0, c, root + off + o, hv(vel if k % 4 == 0 else vel - 14))
            elif style == "long":
                add(b, 0, 7.5, c, root + off, hv(vel))
                add(b, 8, 7.5, c, root + off + L.get("second", 7), hv(vel - 10))
            elif style == "steps":       # 직접: [(칸, 길이, 근음에서 반음, 세기 차)]
                for (s, d, iv, dv) in _by_sec(L["steps"], sec):
                    add(b, s, d, c, root + off + iv, hv(vel + dv))
            elif style == "tumbao":
                add(b, 6, 2, c, root + off + 7, hv(vel - 8))
                add(b, 12, 4, c, root + off, hv(vel))
            # 다음 마디 근음으로 이끄는 음
            nxt = chords[bars[b + 1]["chord"]]["root"] if b + 1 < n_bars else root
            if L.get("lead_in", True) and nxt != root and style in ("anchor", "eighths", "boom"):
                add(b, 15, 1, c, nxt - 1 + off, hv(vel - 20))
        elif t in ("chord", "pad"):
            v0, v1 = L.get("voices", [0, 5])
            keys = [k + L.get("shift", 0) for k in ch["voicing"][v0:v1]]
            if last:
                for k in keys:
                    add(b, 0, 14, c, k, vel)
                continue
            steps = _by_sec(L.get("steps", [(0, 15, vel)]), sec)
            for (s, d, v) in steps:
                for k in keys:
                    add(b, s, d, c, k, hv(v))
        elif t == "power":
            keys = [root + L.get("shift", 12) + i for i in (0, 7, 12)]
            if last:
                for k in keys:
                    add(b, 0, 14, c, k, vel)
                continue
            for (s, d, v) in _by_sec(L["steps"], sec):
                for k in keys:
                    add(b, s, d, c, k, hv(v))
        elif t == "arp":
            if last:
                continue
            order = _by_sec(L["order"], sec)
            every = L.get("every", 2)
            vs = ch["voicing"]
            for i, s in enumerate(range(0, 16, every)):
                k = vs[order[i % len(order)] % len(vs)] + L.get("shift", 0)
                add(b, s, L.get("dur", every * 0.9), c, k, hv(vel if s % 4 == 0 else vel - 12))
        elif t == "perc":
            if last:
                if L.get("outro_key"):
                    add(b, 0, 8, c, L["outro_key"], vel)
                continue
            for (s, v) in _by_sec(L["steps"], sec):
                add(b, s, 0.5, c, L["key"], hv(v))
        elif t == "lead":
            name = bar.get(L.get("key", "lead"))
            if name:
                for (s, d, k) in riffs[name]:
                    add(b, s, d, c, k + L.get("shift", 0), hv(vel))


class Bars:
    """마디 목록 만들기: 구간마다 화음 순서를 돌리며 선창·쉼·따라 치기를 붙인다"""

    def __init__(self, progressions: dict):
        self.prog = progressions                  # 구간 → 화음 이름 목록 (마디마다 하나씩 돌림)
        self.bars = []
        self._k = 0
        self._sec = None

    def section(self, sec):
        self._sec = sec
        self._k = 0
        return self

    def bar(self, role, pat=None, **kw):
        p = self.prog[self._sec]
        d = {"role": role, "sec": self._sec, "chord": p[self._k % len(p)]}
        self._k += 1
        if pat:
            d["pat"] = pat
        d.update(kw)
        self.bars.append(d)
        return d

    def plain(self, role, n, leads=()):
        for i in range(n):
            self.bar(role, lead=leads[i % len(leads)] if leads else None)

    def echo(self, pats, rest=False, rest_leads=(), **kw):
        """같은 1마디 패턴을 2번 (rest 면 3번) — 예전 선창·(쉼)·따라 치기 자리"""
        for i, p in enumerate(pats):
            self.bar("call", p, **kw)
            if rest:   # 예전 '쉬는 마디' 자리: 지금은 같은 패턴을 한 번 더 (북이 끊기지 않게), 멜로디 리프는 그대로
                self.bar("rest", p, lead=rest_leads[i % len(rest_leads)] if rest_leads else None, **kw)
            self.bar("resp", p, **kw)

    def echo2(self, pairs, **kw):
        """2마디 패턴을 2번 — 예전 선창·따라 치기 자리"""
        for pair in pairs:
            for role in ("call", "resp"):
                for p in pair:
                    self.bar(role, p, **kw)


def main(song: dict, song_id: str, argv):
    """python3 tools/music/song_<id>.py [미리듣기.wav]"""
    root_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
    out = os.path.join(root_dir, "audio", "drum", "songs", song_id)
    chart, roles = build(song, out, preview_path=argv[1] if len(argv) > 1 else None)
    print("%s ★%d: bars %d (%.1fs) turns %d notes %d" % (song_id, chart["level"], len(song["bars"]), chart["length"], len(chart["turns"]),
                                                    sum(len(t["notes"]) for t in chart["turns"])))
    print(roles)
    return chart


# ================================================================ 북 패턴 글자표기 · 곡 구성
def P(text: str) -> dict:
    """북 패턴 한 마디를 16칸 글자로: D = 둥, K = 딱, H = 둥 피버 시작(뒤의 '=' 만큼 이어 누름), . = 쉼
    예) "D...K...D.D.K..." , "H===K...D...K..." (둥을 4칸 누르고 있다가 뗌)"""
    t = text.replace(" ", "")
    assert len(t) == 16, text
    pat = {"don": [], "ka": [], "hold": {}}
    i = 0
    while i < 16:
        ch = t[i]
        if ch == "D":
            pat["don"].append(i)
        elif ch == "K":
            pat["ka"].append(i)
        elif ch == "H":
            j = i + 1
            while j < 16 and t[j] == "=":
                j += 1
            pat["don"].append(i)
            pat["hold"][i] = j - i
            i = j
            continue
        i += 1
    if not pat["hold"]:
        del pat["hold"]
    return pat


def compose(progressions: dict, form: list):
    """곡 구성 → 마디 목록
    form: [(구간, 패턴 이름 목록 | 마디 수, {"lead": [리프...], "lead2": [...]} (선택)), ...]
      패턴 목록이면 북 마디(role play), 숫자면 밴드만(role = 구간 이름이 intro·break·outro 면 그대로, 아니면 rest)
      리프는 그 구간 마디들에 차례로 돌려 붙인다 (None = 그 마디 쉼)"""
    bars = []
    for item in form:
        sec, body = item[0], item[1]
        leads = item[2] if len(item) > 2 else {}
        prog = progressions[sec]
        n = len(body) if isinstance(body, (list, tuple)) else int(body)
        for k in range(n):
            d = {"sec": sec, "chord": prog[k % len(prog)]}
            if isinstance(body, (list, tuple)):
                d["role"] = "play"
                d["pat"] = body[k]
            else:
                d["role"] = sec if sec in ("intro", "break", "outro") else "rest"
            for key, lst in leads.items():
                if lst and lst[k % len(lst)]:
                    d[key] = lst[k % len(lst)]
            bars.append(d)
    return bars
