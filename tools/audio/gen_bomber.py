"""크레이지 봄버 효과음: python3 tools/audio/gen_bomber.py → audio/sfx/{bomb_place,boom,kick,crate_break,ghost_throw}.wav"""
import os, sys
import numpy as np
from scipy.io import wavfile
sys.path.insert(0, os.path.dirname(__file__))
from synth import *

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'audio', 'sfx')
sfx = {}
# 폭탄 놓기 '뽁' + 심지 '치익'
t = t_(.35)
pl = np.sin(sweep(320, 140, .12)) * np.exp(-t_(.12) * 30)
x = np.zeros(len(t))
mixat(x, pl, 0)
mixat(x, .35 * hp(noise(.25), 3500) * np.exp(-t_(.25) * 8), .06)
sfx['bomb_place'] = x
# 폭발 '쾅' (낮은 쿵 + 거친 노이즈 + 꼬리)
t = t_(1.2)
boom = np.sin(sweep(120, 32, 1.2)) * np.exp(-t * 4.5) * 1.0
boom += 1.1 * lp(noise(1.2), 900) * np.exp(-t * 5.5)
boom += .5 * bp(noise(1.2), 900, 3500) * np.exp(-t * 14)
sfx['boom'] = np.tanh(boom * 1.6)
# 폭탄 차기 '퉁' + 미끄러짐
t = t_(.4)
k = np.sin(sweep(260, 120, .1)) * np.exp(-t_(.1) * 35)
x = np.zeros(len(t))
mixat(x, k, 0)
mixat(x, .3 * bp(noise(.3), 600, 2500) * np.exp(-t_(.3) * 7), .05)
sfx['kick'] = x
# 상자 부서짐 '와장창' (나무)
t = t_(.5)
x = .8 * lp(noise(.5), 2200) * np.exp(-t * 12)
for i in range(5):
    mixat(x, .35 * np.sin(sweep(500 + 90 * i, 200, .1)) * np.exp(-t_(.1) * 40), .03 + i * .05)
sfx['crate_break'] = x
# 유령이 던짐 '휘익~' (올라갔다 내려오는 휘파람)
t = t_(.55)
f = np.concatenate([np.linspace(500, 1300, int(.25 * SR)), np.linspace(1300, 700, len(t) - int(.25 * SR))])
sfx['ghost_throw'] = .55 * np.sin(2 * np.pi * np.cumsum(f) / SR) * adsr(len(t), .03, .1, .8, .08, .45) + .15 * bp(noise(.55), 1500, 4000) * adsr(len(t), .05, .1, .6, .05, .45)
for k_, v in sfx.items():
    y = fade(norm(np.asarray(v, dtype=float)), .001, .02)
    wavfile.write(os.path.join(OUT, k_ + '.wav'), SR, (y * 32767).astype(np.int16))
print(len(sfx), 'bomber sfx')
