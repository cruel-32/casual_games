"""배경음악 악기·렌더 공용 함수 (gen_bgm.py 에서 떼어 냄, gen_drum.py 가 사용)"""
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

