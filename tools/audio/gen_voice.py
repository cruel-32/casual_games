"""캐릭터 목소리 효과음 (아이 목소리 감탄사) — 포먼트 합성, 샘플·녹음 없이 코드로만 만든다

  voice_push_*  밀칠 때 기합 ("핫!", "얍!", "에잇!")
  voice_hit_*   밀쳐졌을 때 ("윽!", "으악!", "아얏!")
  voice_die_*   탈락할 때 ("으아아아~", "꺄아아~")

캐릭터마다 목소리 높이는 게임에서 pitch 로 바꾼다 (scripts/character/fighter.gd voice_pitch).
실행: python3 tools/audio/gen_voice.py  →  audio/sfx/voice_*.wav
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter

from synth import SR, lp, hp, bp, rng

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "sfx")

# 아이 목소리 모음 포먼트 (F1, F2, F3 Hz)
V = {
    "a": (1000, 1650, 3300),
    "e": (650, 2350, 3350),
    "i": (420, 3000, 3700),
    "o": (650, 1100, 3200),
    "u": (450, 1050, 3200),
    "eu": (470, 1750, 3200),   # ㅡ
    "ya": (900, 1900, 3300),
}
BW = (110, 150, 240)


def _resonator(x, f, bw):
    """시간에 따라 바뀌는 2차 공진 필터 (f, bw: 샘플별 배열)"""
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    r = np.exp(-np.pi * bw / SR)
    c = 2 * r * np.cos(2 * np.pi * f / SR)
    rr = r * r
    g = (1 - r)  # 대략적인 이득 보정
    for n in range(len(x)):
        v = g[n] * x[n] + c[n] * y1 - rr[n] * y2
        y2 = y1
        y1 = v
        y[n] = v
    return y


def voice(segs, base=1.0):
    """segs: [(sec, vowel0, vowel1, f0_0, f0_1, amp0, amp1, breath)] 를 이어 붙여 소리 하나"""
    f0s, a, fm, br = [], [], [[], [], []], []
    for sec, v0, v1, p0, p1, a0, a1, b in segs:
        n = int(sec * SR)
        k = np.linspace(0, 1, n)
        ks = k * k * (3 - 2 * k)       # 부드러운 전이
        f0s.append(p0 * (p1 / p0) ** k)
        a.append(a0 + (a1 - a0) * k)
        br.append(np.full(n, b))
        for i in range(3):
            fm[i].append(V[v0][i] + (V[v1][i] - V[v0][i]) * ks)
    f0 = np.concatenate(f0s) * base
    amp = np.concatenate(a)
    breath = np.concatenate(br)
    n = len(f0)
    t = np.arange(n) / SR
    # 떨림(비브라토) + 미세한 흔들림
    f0 = f0 * (1 + 0.025 * np.sin(2 * np.pi * 5.5 * t) + 0.006 * rng.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1)))
    phase = np.cumsum(f0) / SR
    saw = 2 * (phase % 1.0) - 1
    glottal = lp(-saw, 2600, 1)                       # 성대 소리 (고음 줄임)
    noise = hp(rng.standard_normal(n), 900) * 0.6     # 숨소리
    src = glottal * (1 - breath) + noise * breath
    src *= amp
    out = np.zeros(n)
    gains = (1.0, 0.55, 0.25)
    for i in range(3):
        f = np.concatenate(fm[i]) * (1.08 if base > 1.05 else 1.0)
        out += gains[i] * _resonator(src, f, np.full(n, BW[i]))
    # 앞뒤 클릭 방지
    fade = int(0.006 * SR)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out


def burst(sec, lo, hi, amp=1.0):
    """자음 소리 (ㅎ·ㅋ·ㅅ 같은 바람/터짐)"""
    x = bp(rng.standard_normal(int(sec * SR)), lo, hi) * amp
    e = np.linspace(1, 0, len(x)) ** 1.5
    return x * e


def silence(sec):
    return np.zeros(int(sec * SR))


def cat(*parts):
    return np.concatenate(parts)


def save(name, x, peak=0.85):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, SR, (x * 32767).astype(np.int16))
    print("saved", path, f"{len(x) / SR:.2f}s")


P = 360.0   # 기본 목소리 높이 (아이)

sounds = {
    # 밀칠 때: 짧고 힘 있게, 끝을 끊는다
    "voice_push_1": cat(burst(0.05, 800, 4000, 0.5),                              # 하
                        voice([(0.05, "a", "a", P * 1.05, P * 1.25, 0.2, 1.0, 0.35),
                               (0.11, "a", "a", P * 1.25, P * 1.1, 1.0, 0.6, 0.08)]),
                        burst(0.03, 3000, 7000, 0.25)),                           # 앗
    "voice_push_2": voice([(0.05, "i", "ya", P * 1.15, P * 1.35, 0.3, 1.0, 0.05),   # 야
                           (0.12, "ya", "a", P * 1.35, P * 1.15, 1.0, 0.5, 0.05)]),
    "voice_push_3": voice([(0.07, "e", "e", P * 1.1, P * 1.3, 0.3, 1.0, 0.05),     # 에
                           (0.08, "e", "i", P * 1.3, P * 1.2, 1.0, 0.7, 0.05)]),   # 잇
    # 맞았을 때: 놀람, 위로 튀었다가 꺾임
    "voice_hit_1": voice([(0.05, "eu", "eu", P * 1.3, P * 1.6, 0.3, 1.0, 0.1),      # 윽
                          (0.08, "eu", "eu", P * 1.6, P * 1.2, 1.0, 0.3, 0.2)]),
    "voice_hit_2": voice([(0.06, "eu", "eu", P * 1.25, P * 1.35, 0.4, 0.9, 0.08),   # 으
                          (0.05, "eu", "a", P * 1.35, P * 1.7, 0.9, 1.0, 0.05),     # 아
                          (0.14, "a", "a", P * 1.7, P * 1.25, 1.0, 0.25, 0.1)]),
    "voice_hit_3": cat(voice([(0.08, "a", "a", P * 1.4, P * 1.5, 0.4, 1.0, 0.05)]),  # 아
                       voice([(0.05, "i", "ya", P * 1.6, P * 1.8, 0.6, 1.0, 0.05),    # 얏
                              (0.08, "ya", "a", P * 1.8, P * 1.4, 1.0, 0.4, 0.1)])),
    # 탈락: 길게 떨어지는 비명
    "voice_die_1": voice([(0.08, "eu", "eu", P * 1.3, P * 1.45, 0.3, 0.9, 0.08),     # 으
                          (0.06, "eu", "a", P * 1.45, P * 1.8, 0.9, 1.0, 0.05),      # 아
                          (0.75, "a", "o", P * 1.8, P * 1.0, 1.0, 0.15, 0.15)]),     # 아아~
    "voice_die_2": cat(burst(0.035, 1500, 5000, 0.5),                                # 꺄
                       voice([(0.06, "i", "ya", P * 1.7, P * 2.0, 0.4, 1.0, 0.1),
                              (0.7, "ya", "a", P * 2.0, P * 1.15, 1.0, 0.12, 0.18)])),
}

if __name__ == "__main__":
    for name, x in sounds.items():
        save(name, x)
