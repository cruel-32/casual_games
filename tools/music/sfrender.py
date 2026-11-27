"""사운드폰트 렌더러 (TinySoundFont) — 음표 목록을 스테레오 float 배열로.
note: (start_sec, dur_sec, chan, key, vel). 채널별 악기는 programs={chan: (bank, preset)} (9번 채널은 드럼)
"""
import numpy as np
import tinysoundfont

SR = 44100
SF2 = "/home/claude/sf/gugs/GeneralUser-GS.sf2"


def render(notes, programs, length_sec, gain_db=0.0, cc=None):
    synth = tinysoundfont.Synth(gain=gain_db, samplerate=SR)
    sf = synth.sfload(SF2)
    for ch, (bank, preset) in programs.items():
        synth.program_select(ch, sf, bank, preset, is_drums=(ch == 9))
    for ch, ccs in (cc or {}).items():
        for num, val in ccs:
            synth.control_change(ch, num, val)
    events = []
    for (st, du, ch, key, vel) in notes:
        events.append((st, 1, ch, key, vel))
        events.append((st + max(du, 0.01), 0, ch, key, 0))
    events.sort(key=lambda e: (e[0], e[1]))           # 같은 시각이면 끄기 먼저
    total = int(length_sec * SR)
    out = np.zeros((total, 2), dtype=np.float32)
    pos = 0
    for (t, on, ch, key, vel) in events:
        target = min(int(round(t * SR)), total)
        if target > pos:
            buf = np.frombuffer(synth.generate(target - pos), dtype=np.float32).reshape(-1, 2)
            out[pos:target] = buf
            pos = target
        if on:
            synth.noteon(ch, key, vel)
        else:
            synth.noteoff(ch, key)
    if pos < total:
        out[pos:] = np.frombuffer(synth.generate(total - pos), dtype=np.float32).reshape(-1, 2)
    return out


def reverb(x, wet=0.18, size=1.6, seed=3):
    """작은 방 잔향: 지수 감쇠 노이즈 임펄스와 컨볼루션 (스테레오 좌우 다른 임펄스)"""
    from scipy.signal import fftconvolve
    rng = np.random.default_rng(seed)
    n = int(size * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.0 / size)
    y = np.zeros_like(x)
    for c in range(2):
        ir = rng.standard_normal(n) * env
        ir[: int(0.012 * SR)] = 0                    # 앞쪽 12ms 비움 (초기 반사 지연)
        ir /= np.sqrt((ir ** 2).sum())
        y[:, c] = fftconvolve(x[:, c], ir)[: len(x)]
    return x * (1 - wet) + y * wet


def soft_limit(x, ceiling=0.95):
    peak = np.abs(x).max() + 1e-9
    x = x / peak * 1.2
    return np.tanh(x) / np.tanh(1.2) * ceiling


def save_wav(path, x):
    from scipy.io import wavfile
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def soft_limit_fixed(x, drive=1.2, ceiling=0.92):
    """배율은 그대로 두고 봉우리만 부드럽게 (같은 배율로 여러 파일을 맞출 때)"""
    return np.tanh(x * drive) / np.tanh(drive) * ceiling
