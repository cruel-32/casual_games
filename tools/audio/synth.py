"""Small Party World 소리 합성 공용 함수 (numpy). 샘플·외부 음원 없이 코드로만 만든다."""
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(11)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, f, order=2):
    return sosfilt(butter(order, min(f, SR / 2 - 200), 'low', fs=SR, output='sos'), x)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, 'high', fs=SR, output='sos'), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, min(hi, SR / 2 - 200)], 'band', fs=SR, output='sos'), x)


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def adsr(n, a=.005, d=.08, s=.6, r=.06, hold=None):
    t = np.arange(n) / SR
    e = np.full(n, s, dtype=float)
    ai = max(1, int(a * SR))
    e[:ai] = np.linspace(0, 1, ai)
    di = int(d * SR)
    seg = e[ai:ai + di]
    e[ai:ai + di] = np.linspace(1, s, len(seg))
    if hold is not None:
        ri = int(hold * SR)
        if ri < n:
            e[ri:] *= np.exp(-(t[ri:] - t[ri]) / max(r, 1e-3))
    return e


def sweep(f0, f1, sec, curve='exp'):
    """주파수가 f0 → f1 로 변하는 위상 (sin 에 넣어 쓴다)"""
    t = t_(sec)
    k = t / max(sec, 1e-6)
    f = f0 * (f1 / f0) ** k if curve == 'exp' else f0 + (f1 - f0) * k
    return 2 * np.pi * np.cumsum(f) / SR


def sq(phase, duty=.5):
    return np.where((phase / (2 * np.pi)) % 1.0 < duty, 1.0, -1.0)


def tri(phase):
    x = (phase / (2 * np.pi)) % 1.0
    return 2 * np.abs(2 * x - 1) - 1


def saw(phase):
    return 2 * ((phase / (2 * np.pi)) % 1.0) - 1


def fade(x, fin=.002, fout=.01):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)
    return x


def norm(x, peak=.89):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def mixat(dst, src, at_sec):
    s = int(at_sec * SR)
    e = min(len(dst), s + len(src))
    dst[s:e] += src[:e - s]
    return dst
