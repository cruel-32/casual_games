"""무궁화 꽃이 피었습니다: 구호 한 음절 소리 (마림바 + 합창 '아', C5 한 음).
게임에서 음절마다 pitch_scale 로 높낮이를 바꿔 부른다 (mugunghwa_game.gd CHANT_PITCH).
  python3 tools/audio/gen_mugunghwa.py → audio/mugunghwa/chant.wav
필요: tools/music/sfrender.py (tinysoundfont + GeneralUser GS)
"""
import os
import sys

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "music"))
import sfrender as R

mar = R.render([(0.0, 0.35, 0, 72, 118)], {0: (0, 12)}, 0.7)          # 마림바
cho = R.render([(0.0, 0.32, 1, 72, 100)], {1: (0, 52)}, 0.7)          # 합창 '아'
x = mar / (np.abs(mar).max() + 1e-9) * 0.8 + cho / (np.abs(cho).max() + 1e-9) * 0.45
m = x.mean(axis=1)
start = int(np.argmax(np.abs(m) > 0.02 * np.abs(m).max()))
m = m[start:start + int(0.55 * R.SR)]
fade = int(0.12 * R.SR)
m[-fade:] *= np.linspace(1, 0, fade)
m = m / (np.abs(m).max() + 1e-9) * 0.9
from scipy.io import wavfile
out = os.path.join(ROOT, "audio", "mugunghwa", "chant.wav")
wavfile.write(out, R.SR, (m * 32767).astype(np.int16))
print("saved", out, len(m) / R.SR, "s")
