"""배경음악 생성: python3 tools/audio/gen_bgm.py  →  audio/bgm/menu.ogg, audio/bgm/match.ogg
둘 다 16마디 무한 반복용 (끝의 잔향을 앞에 겹쳐 이음매 없이 이어짐). 외부 음원 없이 코드로 합성."""
import os, sys, subprocess
import numpy as np
from scipy.io import wavfile
sys.path.insert(0, os.path.dirname(__file__))
from synth import *

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'audio', 'bgm')
os.makedirs(OUT, exist_ok=True)
N_ = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
def m(n):
    b = n.rstrip('0123456789'); o = int(n[len(b):])
    return 12 * (o + 1) + N_[b[0]] + (1 if '#' in b else 0) - (1 if b.endswith('b') and len(b) > 1 else 0)


# ---- 악기 ----
def kick(v=1.0):
    t = t_(.35); return v * np.sin(2 * np.pi * np.cumsum(45 + 90 * np.exp(-t * 32)) / SR) * np.exp(-t * 10)
def snare(v=1.0):
    t = t_(.22); return v * (bp(noise(.22), 1200, 7000) * .35 + .3 * np.sin(2 * np.pi * 190 * t)) * np.exp(-t * 22)
def hat(v=1.0):
    t = t_(.06); return v * hp(noise(.06), 7500) * np.exp(-t * 70) * .14
def shaker(v=1.0):
    t = t_(.09); return v * bp(noise(.09), 4000, 9000) * np.sin(np.pi * t / .09) * .14
def bass(midi, sec, v=1.0):
    t = t_(sec + .05); f = hz(midi)
    w = .55 * sq(2 * np.pi * f * t) + .6 * np.sin(2 * np.pi * f * t)
    return v * lp(w, 800) * adsr(len(t), .004, .06, .7, .03, sec) * .4
def pluck(midi, v=1.0):  # 우쿨렐레 느낌
    t = t_(.5); f = hz(midi)
    return v * lp(tri(2 * np.pi * f * t) + .3 * sq(2 * np.pi * f * t, .2), 3500) * np.exp(-t * 9) * .22
def toy(midi, sec, v=1.0):
    t = t_(max(sec, .3) + .4); f = hz(midi)
    w = np.sin(2 * np.pi * f * t + 1.2 * np.exp(-t * 7) * np.sin(2 * np.pi * f * 3.5 * t))
    return v * w * np.exp(-t * 3.5) * .3
def lead(midi, sec, v=1.0):
    t = t_(sec + .08)
    f = hz(midi) * (1 + .005 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 4 - .5, 0, 1))
    return v * lp(sq(2 * np.pi * np.cumsum(f) / SR, .25), 5000) * adsr(len(t), .005, .08, .6, .05, sec - .02) * .2
def arp(midi, v=1.0):
    t = t_(.16); return v * lp(sq(2 * np.pi * hz(midi) * t, .125), 4000) * np.exp(-t * 20) * .12
def pad(ms, sec, v=1.0):
    t = t_(sec + .3); w = 0
    for mm in ms:
        for det in (-.003, .003):
            w = w + saw(2 * np.pi * hz(mm) * (1 + det) * t)
    return v * lp(w / (2 * len(ms)), 1600) * adsr(len(t), .25, .2, .8, .25, sec) * .16


def render(bpm, bars, events, path, master=.85):
    beat = 60.0 / bpm
    total = bars * 4 * beat
    buf = np.zeros(int((total + 3.0) * SR))
    for at, y in events:
        mixat(buf, y, at * beat)
    loop_n = int(total * SR)
    out = buf[:loop_n].copy()
    out[:len(buf) - loop_n] += buf[loop_n:]          # 꼬리를 앞에 겹쳐 이음매 없이 반복
    out = np.tanh(out / np.max(np.abs(out)) * 1.4) / np.tanh(1.4) * master
    wav = path + '.wav'
    wavfile.write(wav, SR, (out * 32767).astype(np.int16))
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '5', path + '.ogg'], check=True)
    os.remove(wav)
    print(os.path.basename(path), round(total, 2), 's')


CHORD = {'F': ['F', 'A', 'C'], 'Dm': ['D', 'F', 'A'], 'Bb': ['Bb', 'D', 'F'], 'C': ['C', 'E', 'G'], 'Gm': ['G', 'Bb', 'D'],
         'Am': ['A', 'C', 'E'], 'G': ['G', 'B', 'D'], 'Em': ['E', 'G', 'B'], 'E': ['E', 'G#', 'B']}

# ================= 메뉴: 100 BPM, F장조, 느긋한 장난감 보사 =================
ev = []
prog = ['F', 'Dm', 'Bb', 'C', 'F', 'Dm', 'Gm', 'C'] * 2
MEL = [  # 2마디 단위 프레이즈 (박, 음, 길이) — 8마디 = 4프레이즈
    [(0, 'C6', 1), (1, 'A5', .5), (1.5, 'C6', .5), (2, 'D6', 1.5), (4, 'C6', 1), (5, 'A5', 1), (6, 'F5', 2)],
    [(0, 'D6', .5), (.5, 'C6', .5), (1, 'Bb5', 1), (2, 'A5', 1), (3, 'G5', 1), (4, 'A5', .5), (4.5, 'Bb5', .5), (5, 'C6', 3)],
    [(0, 'C6', 1), (1, 'A5', .5), (1.5, 'C6', .5), (2, 'F6', 1.5), (4, 'E6', 1), (5, 'D6', 1), (6, 'C6', 2)],
    [(0, 'Bb5', .5), (.5, 'A5', .5), (1, 'G5', 1), (2, 'Bb5', 1), (3, 'E5', 1), (4, 'F5', 4)],
]
for bi, c in enumerate(prog):
    b0 = bi * 4
    tones = CHORD[c]
    root = m(tones[0] + '2'); root = root - 12 if root > m('E2') else root
    fifth = m(tones[2] + '2'); fifth = fifth - 12 if fifth > root + 12 else fifth
    for o, n, d in [(0, root, 1.4), (1.5, fifth if fifth > root else fifth + 12, .45), (2, root + 12, 1.4), (3.5, fifth if fifth > root else fifth + 12, .45)]:
        ev.append((b0 + o, bass(n, d * 60 / 100, .9)))
    for o in (0, 2):
        ev.append((b0 + o, kick(.6)))
    for k in range(8):
        ev.append((b0 + k * .5, shaker(1.0 if k % 2 else .6)))
    ev.append((b0 + 1, snare(.25))); ev.append((b0 + 3, snare(.25)))
    for o in (.5, 1.5, 2.5, 3.0, 3.5):
        for j, nn in enumerate(tones):
            ev.append((b0 + o + j * .012, pluck(m(nn + '4'), .8 if o != 3.0 else .6)))
    if bi >= 8:
        ev.append((b0, pad([m(nn + '4') for nn in tones], 4 * 60 / 100 - .1, .8)))
for half in (0, 1):
    for p, phrase in enumerate(MEL):
        base = half * 32 + p * 8
        for o, n, d in phrase:
            ev.append((base + o, toy(m(n), d * .6, 1.0 if half == 0 else .9)))
            if half == 1:
                ev.append((base + o, toy(m(n) - 12, d * .6, .45)))
render(100, 16, ev, os.path.join(OUT, 'menu'), .8)

# ================= 경기: 138 BPM, A단조, 신나는 칩튠 =================
ev = []
prog = ['Am', 'F', 'C', 'G', 'Am', 'F', 'C', 'E'] * 2
LEAD = [
    [(0, 'E5', .5), (.5, 'A5', .5), (1, 'C6', .5), (1.5, 'B5', .5), (2, 'A5', 1), (3, 'E5', .5), (3.5, 'G5', .5),
     (4, 'F5', .5), (4.5, 'A5', .5), (5, 'C6', 1), (6, 'D6', .5), (6.5, 'C6', .5), (7, 'A5', 1)],
    [(0, 'G5', .5), (.5, 'C6', .5), (1, 'E6', 1), (2, 'D6', .5), (2.5, 'C6', .5), (3, 'B5', 1),
     (4, 'B5', .5), (4.5, 'C6', .5), (5, 'D6', .5), (5.5, 'E6', .5), (6, 'G#5', 1), (7, 'B5', 1)],
]
for bi, c in enumerate(prog):
    b0 = bi * 4
    tones = CHORD[c]
    root = m(tones[0] + '2'); root = root - 12 if root > m('E2') else root
    for k in range(8):
        ev.append((b0 + k * .5, bass(root + (12 if k % 2 else 0), .2, 1.0 if k % 2 == 0 else .8)))
    for k in range(4):
        ev.append((b0 + k, kick(1.0)))
    ev.append((b0 + 1, snare(.9))); ev.append((b0 + 3, snare(.9)))
    if bi % 4 == 3:
        ev.append((b0 + 3.5, snare(.6))); ev.append((b0 + 3.75, snare(.7)))
    for k in range(8):
        ev.append((b0 + k * .5 + .25 * 0, hat(1.0 if k % 2 else .55)))
        ev.append((b0 + k * .5 + .25, hat(.45)))
    seq_ = [0, 1, 2, 1, 0, 1, 2, 1]
    for k in range(16):
        tn = tones[[0, 1, 2, 1][k % 4]]
        ev.append((b0 + k * .25, arp(m(tn + '5') + (12 if k % 8 >= 4 else 0), .9 if k % 2 == 0 else .6)))
    ev.append((b0, pad([m(nn + '3') for nn in tones], 4 * 60 / 138 - .05, .9)))
for rep in range(2):
    for p in range(2):
        for o, n, d in LEAD[p]:
            if n == 'G#5':
                n = 'G5'          # 앞 4마디는 G 코드 위라 G# 대신 G
            ev.append((rep * 32 + p * 8 + o, lead(m(n), d * 60 / 138, 1.0)))
    for p in range(2):
        for o, n, d in LEAD[p]:
            if rep == 1:
                ev.append((rep * 32 + p * 8 + 16 + o, lead(m(n) + 12, d * 60 / 138, .55)))
            ev.append((rep * 32 + p * 8 + 16 + o, lead(m(n), d * 60 / 138, .95)))
render(138, 16, ev, os.path.join(OUT, 'match'), .8)
