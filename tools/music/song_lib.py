"""뒷북의 달인 곡 만들기 도구 — 곡 정의(마디 목록) → 반주 ogg + 노트 json + 북 소리

곡 하나를 통째로 쓰고, 북 파트(둥 = 킥 역할, 딱 = 스네어 역할)가 곧 게임 노트가 된다.
  call 마디: 진행자가 치므로 반주에 북소리가 들어 있음
  resp 마디: 반주에서 북을 비움 → 플레이어가 채워야 곡이 완성됨
  그 밖(intro·rest·break·outro): 밴드만

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

    for b, bar in enumerate(bars):
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
    for (b, s, d, k, v) in song.get("extra_brass", []):
        add(b if b >= 0 else n_bars + b, s, d, CH_BRASS, k, v)

    don, ka = make_drums()

    def place(buf, sample, t, gain=1.0):
        i = int(round(t * R.SR))
        j = min(i + len(sample), len(buf))
        if j > i:
            buf[i:j] += sample[: j - i] * gain

    band = R.render(notes, PROGRAMS, length)
    band = band / (np.abs(band).max() + 1e-9) * 0.55
    host = np.zeros_like(band)
    player = np.zeros_like(band)
    # 선창·따라 치기 짝: call 이 이어진 마디들 → 같은 패턴의 resp 마디들
    turns = []
    b = 0
    while b < n_bars:
        if bars[b]["role"] != "call":
            b += 1
            continue
        c0 = b
        while b < n_bars and bars[b]["role"] == "call":
            b += 1
        n = b - c0
        while b < n_bars and bars[b]["role"] != "resp":
            b += 1
        r0 = b
        assert [bars[c0 + k]["pat"] for k in range(n)] == [bars[r0 + k]["pat"] for k in range(n)], "선창과 따라 치기 패턴이 달라요 (마디 %d)" % c0
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
        r = r0 * bar_len
        for (ms, lane, e) in tnotes:
            smp = don if lane == 0 else ka
            for base, buf in ((a, host), (r, player)):
                place(buf, smp, base + ms / 1000.0)
                if e >= 0:                                   # 피버: 누르는 동안 16분음표마다 작게
                    t = ms + step * 1000 * ROLL_STEP_16
                    while t < e - 20:
                        place(buf, smp, base + t / 1000.0, 0.35)
                        t += step * 1000 * ROLL_STEP_16
        turns.append({"bars": n, "attack_t": round(a, 4), "response_t": round(r, 4), "notes": tnotes})
        b = r0 + n

    mix_b = R.reverb(band + host * DRUM_GAIN, wet=0.16)
    mix_p = R.reverb(band + host * DRUM_GAIN + player * DRUM_GAIN, wet=0.16)
    scale = 1.0 / (np.abs(mix_p).max() + 1e-9)
    backing = R.soft_limit_fixed(mix_b * scale)
    os.makedirs(out_audio_dir, exist_ok=True)
    tmp = os.path.join(out_audio_dir, "_backing.wav")
    R.save_wav(tmp, backing)
    # 용량: Vorbis q1 (약 80kbps 스테레오)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "1",
                    os.path.join(out_audio_dir, "backing.ogg")], check=True)
    os.remove(tmp)
    if preview_path:
        R.save_wav(preview_path, R.soft_limit_fixed(mix_p * scale))
    if drums_dir:
        # 게임의 북 소리 (모노, 짧게). 진행자 북(반주 안)과 같은 소리
        from scipy.io import wavfile
        for name, x in (("don", don), ("ka", ka)):
            wavfile.write(os.path.join(drums_dir, name + ".wav"), R.SR, (np.clip(x[:, 0], -1, 1) * 32767).astype(np.int16))
    chart = {"title": song["title"], "bpm": bpm, "length": round(n_bars * bar_len, 3), "turns": turns}
    # 게임이 읽는 노트: GDScript 상수 파일 (스크립트라서 내보내기에 항상 포함됨, JSON 은 필터에 안 걸리면 빠짐)
    with open(os.path.join(out_audio_dir, "song.gd"), "w") as f:
        f.write("extends RefCounted\n## 자동 생성 (tools/music/song_*.py) — 손으로 고치지 마세요\n")
        f.write("## turns: [{bars, attack_t(선창 시작 초), response_t(따라 치기 시작 초), notes: [[ms, 북(0 둥 1 딱), 끝 ms(-1 = 한 번 치기)]]}]\n")
        f.write("const DATA := " + json.dumps(chart, ensure_ascii=False) + "\n")
    roles = "".join({"intro": "I", "call": "C", "rest": ".", "resp": "R", "outro": "O", "break": "b"}[x["role"]] for x in bars)
    return chart, roles
