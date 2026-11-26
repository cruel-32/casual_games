"""뒷북의 달인 소리: python3 tools/audio/gen_drum.py
  audio/drum/don.wav    왼쪽 북 '둥' (낮은 큰북)
  audio/drum/ka.wav     오른쪽 북 '딱' (북 테두리)
  audio/drum/cue.wav    '준비' 신호 (마디 앞 박)
  audio/drum/miss.wav   놓침
  audio/drum/groove.ogg 반주 100 BPM, 8마디 무한 반복 (북 소리와 겹치지 않게 가볍게)
"""
import os, sys
import numpy as np
from scipy.io import wavfile
sys.path.insert(0, os.path.dirname(__file__))
from synth import *
import gen_bgm_lib as G

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'audio', 'drum')
os.makedirs(OUT, exist_ok=True)


def save(name, y, peak=.9):
    y = y / max(np.max(np.abs(y)), 1e-6) * peak
    wavfile.write(os.path.join(OUT, name), SR, (y * 32767).astype(np.int16))


# 둥: 경쾌한 태고 — 음을 조금 올리고(150Hz대) 울림은 짧게, 채가 닿는 순간의 '톡' 소리를 더함
t = t_(.38)
don = np.sin(2 * np.pi * np.cumsum(150 + 90 * np.exp(-t * 40)) / SR) * np.exp(-t * 11)
don += .45 * np.sin(2 * np.pi * np.cumsum(330 + 80 * np.exp(-t * 40)) / SR) * np.exp(-t * 20)
don += .25 * np.sin(2 * np.pi * 520 * t) * np.exp(-t * 35)
don += bp(noise(.38), 1500, 5000) * np.exp(-t * 120) * .55       # 채 소리
save('don.wav', don)

# 딱: 테두리를 치는 맑은 소리 (나무 블록처럼 짧고 높게)
t = t_(.12)
ka = np.sin(2 * np.pi * 1900 * t) * np.exp(-t * 60) * .8 + np.sin(2 * np.pi * 3100 * t) * np.exp(-t * 80) * .45
ka += np.sin(2 * np.pi * 950 * t) * np.exp(-t * 45) * .35
ka += bp(noise(.12), 3000, 9000) * np.exp(-t * 150) * .5
save('ka.wav', ka, .8)

t = t_(.12)
cue = np.sin(2 * np.pi * 1760 * t) * np.exp(-t * 30) + .4 * np.sin(2 * np.pi * 2640 * t) * np.exp(-t * 40)
save('cue.wav', cue, .6)

t = t_(.25)
miss = np.sin(2 * np.pi * np.cumsum(300 * np.exp(-t * 4)) / SR) * np.exp(-t * 10) * .6
save('miss.wav', miss, .5)

# ---- 반주: 100 BPM, C장조, 리듬 천국 느낌의 가벼운 펑크 (킥·하이햇·베이스·피아노 스탭)
ev = []
prog = ['C', 'Am', 'F', 'G'] * 2
for bi, c in enumerate(prog):
    b0 = bi * 4
    tones = G.CHORD[c]
    root = G.m(tones[0] + '2'); root = root - 12 if root > G.m('E2') else root
    for o, d, v in [(0, .45, 1.0), (1.5, .2, .8), (2, .45, .95), (3, .2, .7), (3.5, .2, .8)]:
        ev.append((b0 + o, G.bass(root + (12 if o in (1.5, 3.5) else 0), d, v)))
    # 박이 또렷하게: 매 박 킥(1·3박 강하게) + 2·4박 스네어 + 8분 하이햇(정박 강세) = 북을 칠 수 있는 8분음표 격자
    for k, v in enumerate((1.0, .7, .9, .7)):
        ev.append((b0 + k, G.kick(v)))
    ev.append((b0 + 1, G.snare(.55))); ev.append((b0 + 3, G.snare(.55)))
    for k in range(8):
        ev.append((b0 + k * .5, G.hat(.9 if k % 2 == 0 else .55)))
    for o in (.5, 1.5, 2.5, 3.5):           # 엇박 피아노 스탭 (박은 플레이어 북이 채움)
        for j, nn in enumerate(tones):
            ev.append((b0 + o + j * .01, G.pluck(G.m(nn + '4'), .55)))
    ev.append((b0 + 1, G.shaker(.9))); ev.append((b0 + 3, G.shaker(.9)))
G.render(100, 8, ev, os.path.join(OUT, 'groove'), .92)
