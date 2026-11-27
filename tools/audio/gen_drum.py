"""뒷북의 달인 효과음: python3 tools/audio/gen_drum.py
  audio/drum/cue.wav    '준비' 신호
  audio/drum/miss.wav   놓침
  (둥·딱 북 소리와 반주는 곡과 같은 사운드폰트로 tools/music/song_*.py 가 만든다)
"""
import os, sys
import numpy as np
from scipy.io import wavfile
sys.path.insert(0, os.path.dirname(__file__))
from synth import *

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'audio', 'drum')
os.makedirs(OUT, exist_ok=True)


def save(name, y, peak=.9):
    y = y / max(np.max(np.abs(y)), 1e-6) * peak
    wavfile.write(os.path.join(OUT, name), SR, (y * 32767).astype(np.int16))


# 둥·딱 북 소리는 곡과 같은 사운드폰트로 만든다 → tools/music/song_lib.py (make_drums)

t = t_(.12)
cue = np.sin(2 * np.pi * 1760 * t) * np.exp(-t * 30) + .4 * np.sin(2 * np.pi * 2640 * t) * np.exp(-t * 40)
save('cue.wav', cue, .6)

t = t_(.25)
miss = np.sin(2 * np.pi * np.cumsum(300 * np.exp(-t * 4)) / SR) * np.exp(-t * 10) * .6
save('miss.wav', miss, .5)
# 반주는 곡마다 tools/music/song_*.py 로 만든다 (audio/drum/songs/<곡>/backing.ogg)
