"""캐릭터 목소리 효과음 (아이 목소리 감탄사) — 포먼트 합성, 샘플·녹음 없이 코드로만 만든다

  파일: audio/sfx/voice_<종류>_<목소리>_<번호>.wav  (목소리 0 보통 아이 / 1 여자아이 / 2 굵은 목소리 / 3 아주 높은 목소리)
  push     밀칠 때·차징 던지기 기합 ("핫!", "얍!", "에잇!", "하앗!")
  hit      밀쳐졌을 때 ("윽!", "으악!", "아얏!", "끄악!")
  die      탈락할 때 ("으아아~", "꺄아~", "우에에~")
  jump     점프 ("홉!", "앗!", "영차")
  pickup   아이템 먹음 ("오!", "야호", "우와")
  win      이겼을 때 ("야호~", "와아~", "이예~")
  laugh    웃음 ("히히히", "하하하")
  surprise 놀람 ("헉!", "앗!")

캐릭터마다 목소리 종류(voice_type)를 정하고, 같은 종류 안에서도 음높이를 조금씩 다르게 한다 (scripts/character/fighter.gd).
실행: python3 tools/audio/gen_voice.py  →  audio/sfx/voice_*.wav (예전 파일은 지움)
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


def voice(segs, base=1.0, fs=1.0):
    """segs: [(sec, vowel0, vowel1, f0_0, f0_1, amp0, amp1, breath)] 를 이어 붙여 소리 하나
    fs: 포먼트 배율 (1보다 크면 작고 가는 목소리, 작으면 크고 굵은 목소리)"""
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
        f = np.concatenate(fm[i]) * (1.08 if base > 1.05 else 1.0) * fs
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


# 목소리 종류 (캐릭터마다 하나씩 — scripts/character/fighter.gd voice_type)
#   (이름, 기본 높이 Hz, 포먼트 배율, 숨소리 더함)
TYPES = [
    ("boy", 330.0, 1.0, 0.0),       # 0 보통 아이
    ("girl", 430.0, 1.12, 0.03),    # 1 가는 여자아이
    ("deep", 200.0, 0.84, 0.05),    # 2 굵은 목소리 (덩치)
    ("squeak", 540.0, 1.22, 0.0),   # 3 아주 높은 만화 목소리
]


def make_sounds(P, fs, br):
    """한 목소리 종류의 감탄사 전부. P = 기본 높이, fs = 포먼트 배율, br = 숨소리 더함"""
    def v(segs):
        return voice([(sec, a, b, p0, p1, a0, a1, min(bb + br, 0.6)) for sec, a, b, p0, p1, a0, a1, bb in segs], 1.0, fs)
    return {
        # 밀칠 때·차징 던지기: 짧고 힘 있게
        "push_1": cat(burst(0.05, 800, 4000, 0.5),                                       # 핫
                      v([(0.05, "a", "a", P * 1.05, P * 1.25, 0.2, 1.0, 0.35),
                         (0.11, "a", "a", P * 1.25, P * 1.1, 1.0, 0.6, 0.08)]),
                      burst(0.03, 3000, 7000, 0.25)),
        "push_2": v([(0.05, "i", "ya", P * 1.15, P * 1.35, 0.3, 1.0, 0.05),              # 얍
                     (0.12, "ya", "a", P * 1.35, P * 1.15, 1.0, 0.5, 0.05)]),
        "push_3": v([(0.07, "e", "e", P * 1.1, P * 1.3, 0.3, 1.0, 0.05),                 # 에잇
                     (0.08, "e", "i", P * 1.3, P * 1.2, 1.0, 0.7, 0.05)]),
        "push_4": cat(burst(0.06, 700, 3500, 0.45),                                      # 하앗
                      v([(0.07, "a", "a", P * 1.0, P * 1.1, 0.3, 0.8, 0.3),
                         (0.10, "a", "a", P * 1.3, P * 1.2, 1.0, 0.5, 0.05)])),
        # 맞았을 때
        "hit_1": v([(0.05, "eu", "eu", P * 1.3, P * 1.6, 0.3, 1.0, 0.1),                 # 윽
                    (0.08, "eu", "eu", P * 1.6, P * 1.2, 1.0, 0.3, 0.2)]),
        "hit_2": v([(0.06, "eu", "eu", P * 1.25, P * 1.35, 0.4, 0.9, 0.08),              # 으악
                    (0.05, "eu", "a", P * 1.35, P * 1.7, 0.9, 1.0, 0.05),
                    (0.14, "a", "a", P * 1.7, P * 1.25, 1.0, 0.25, 0.1)]),
        "hit_3": cat(v([(0.08, "a", "a", P * 1.4, P * 1.5, 0.4, 1.0, 0.05)]),             # 아얏
                     v([(0.05, "i", "ya", P * 1.6, P * 1.8, 0.6, 1.0, 0.05),
                        (0.08, "ya", "a", P * 1.8, P * 1.4, 1.0, 0.4, 0.1)])),
        "hit_4": cat(burst(0.04, 1500, 4500, 0.45),                                      # 끄악
                     v([(0.05, "eu", "a", P * 1.5, P * 1.9, 0.5, 1.0, 0.1),
                        (0.12, "a", "a", P * 1.9, P * 1.4, 1.0, 0.3, 0.15)])),
        # 탈락: 길게 떨어지는 비명
        "die_1": v([(0.08, "eu", "eu", P * 1.3, P * 1.45, 0.3, 0.9, 0.08),               # 으아아~
                    (0.06, "eu", "a", P * 1.45, P * 1.8, 0.9, 1.0, 0.05),
                    (0.75, "a", "o", P * 1.8, P * 1.0, 1.0, 0.15, 0.15)]),
        "die_2": cat(burst(0.035, 1500, 5000, 0.5),                                      # 꺄아~
                     v([(0.06, "i", "ya", P * 1.7, P * 2.0, 0.4, 1.0, 0.1),
                        (0.7, "ya", "a", P * 2.0, P * 1.15, 1.0, 0.12, 0.18)])),
        "die_3": v([(0.1, "u", "e", P * 1.4, P * 1.7, 0.3, 1.0, 0.08),                   # 우에에~
                    (0.65, "e", "eu", P * 1.7, P * 0.9, 1.0, 0.1, 0.2)]),
        # 점프: 아주 짧은 기합
        "jump_1": cat(burst(0.04, 900, 4000, 0.4),                                       # 홉
                      v([(0.07, "o", "o", P * 1.2, P * 1.4, 0.4, 1.0, 0.15)])),
        "jump_2": v([(0.05, "a", "a", P * 1.3, P * 1.5, 0.4, 1.0, 0.1)]),                # 앗
        "jump_3": v([(0.07, "ya", "o", P * 1.1, P * 1.35, 0.3, 1.0, 0.05),               # 영차
                     (0.07, "a", "a", P * 1.35, P * 1.2, 0.8, 0.4, 0.15)]),
        # 아이템 먹음: 기뻐서 올라가는 소리
        "pickup_1": v([(0.18, "o", "o", P * 1.1, P * 1.6, 0.4, 1.0, 0.05)]),              # 오!
        "pickup_2": v([(0.09, "ya", "a", P * 1.3, P * 1.5, 0.4, 1.0, 0.05),               # 야호
                       (0.16, "o", "o", P * 1.6, P * 1.9, 1.0, 0.4, 0.05)]),
        "pickup_3": v([(0.1, "u", "a", P * 1.2, P * 1.4, 0.4, 1.0, 0.05),                 # 우와
                       (0.16, "a", "a", P * 1.5, P * 1.75, 1.0, 0.35, 0.08)]),
        # 승리 환호: 길게
        "win_1": v([(0.1, "ya", "a", P * 1.4, P * 1.6, 0.4, 1.0, 0.05),                   # 야호~
                    (0.5, "o", "o", P * 1.8, P * 1.6, 1.0, 0.15, 0.08)]),
        "win_2": v([(0.12, "u", "a", P * 1.3, P * 1.6, 0.3, 1.0, 0.05),                   # 와아~
                    (0.55, "a", "a", P * 1.7, P * 1.9, 1.0, 0.15, 0.1)]),
        "win_3": v([(0.1, "i", "e", P * 1.5, P * 1.6, 0.4, 1.0, 0.05),                    # 이예~
                    (0.45, "e", "e", P * 1.8, P * 2.0, 1.0, 0.2, 0.05)]),
        # 웃음: 히히·하하 (짧은 소리 여러 번)
        "laugh_1": cat(*[cat(burst(0.03, 2000, 6000, 0.35), v([(0.06, "i", "i", P * (1.6 - k * 0.08), P * (1.5 - k * 0.08), 0.5, 0.7, 0.3)]), silence(0.04)) for k in range(4)]),
        "laugh_2": cat(*[cat(burst(0.04, 800, 3500, 0.4), v([(0.07, "a", "a", P * (1.4 - k * 0.07), P * (1.3 - k * 0.07), 0.5, 0.7, 0.3)]), silence(0.05)) for k in range(3)]),
        # 놀람
        "surprise_1": cat(burst(0.05, 1200, 5000, 0.5),                                  # 헉
                          v([(0.06, "eo" if False else "o", "eu", P * 1.6, P * 1.8, 0.6, 0.9, 0.45)])),
        "surprise_2": v([(0.09, "a", "a", P * 1.7, P * 2.1, 0.3, 1.0, 0.1)]),             # 앗!
    }


SR_OUT = 22050      # 파일 크기를 줄이려고 반으로 (목소리엔 충분)


def save22(name, x, peak=0.85):
    from scipy.signal import resample_poly
    y = resample_poly(x, 1, SR // SR_OUT) if SR % SR_OUT == 0 else x
    y = y / (np.max(np.abs(y)) + 1e-9) * peak
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, SR_OUT if SR % SR_OUT == 0 else SR, (y * 32767).astype(np.int16))
    return len(y)


if __name__ == "__main__":
    import glob
    for old in glob.glob(os.path.join(OUT, "voice_*.wav")):
        os.remove(old)
        if os.path.exists(old + ".import"):
            os.remove(old + ".import")
    count = 0
    for ti, (tname, P, fs, br) in enumerate(TYPES):
        for name, x in make_sounds(P, fs, br).items():
            kind, n = name.rsplit("_", 1)
            save22("voice_%s_%d_%s" % (kind, ti, n), x)
            count += 1
    print(count, "voices")
