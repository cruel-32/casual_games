"""캐릭터 대사 (TTS): "야호!", "이겼다!", "아이씨!", "짜증나!", "우하하!" 같은 짧은 말을 목소리 5가지로

  준비 (한 번만):
    pip install sherpa-onnx==1.13.8     (2.x 는 이 모델을 못 읽음)
    curl -L -o /tmp/tts/ko.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-mimic3-ko_KO-kss_low.tar.bz2
    tar xjf /tmp/tts/ko.tar.bz2 -C /tmp/tts
  실행: python3 tools/audio/gen_tts_lines.py [모델 폴더]  →  audio/sfx/line_<종류>_<목소리>_<번호>.wav

  모델은 성인 여성 낭독 목소리(KSS) 하나뿐이라, 목소리마다 높이를 바꾼다:
    TTS 를 (빠르기 ÷ 높이배율) 로 만든 뒤 높이배율만큼 빠르게 재생 → 말 빠르기는 TEMPO, 높이(와 울림)는 배율만큼
  목소리 번호는 gen_voice.py 와 같다: 0 보통 아이 / 1 여자아이 / 2 굵은 목소리 / 3 아주 얇고 높은 목소리 / 4 털보 아저씨
"""
import os
import sys
from fractions import Fraction

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly, butter, lfilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "sfx")
MODEL = sys.argv[1] if len(sys.argv) > 1 else "/tmp/tts/vits-mimic3-ko_KO-kss_low"
TEMPO = 1.45            # 말 빠르기 (원래 낭독보다 빠르게)

# (이름, 높이 배율, 걸걸함)
TYPES = [
    ("boy", 1.4, 0.0),
    ("girl", 1.6, 0.0),
    ("deep", 0.86, 0.0),
    ("squeak", 1.95, 0.0),
    ("beard", 0.6, 0.8),
]

# 종류별 대사 (Fighter 의 목소리 종류와 같은 이름 — 게임에서 합성 목소리와 섞어서 고름)
#   너무 짧은 말("아야!", "헉!", "아싸!")은 이 모델이 0.1초로 뭉개서 조금 긴 말로 바꿈
LINES = {
    "win": ["야호!", "이겼다!", "우하하하!", "내가 일등이다!"],
    "die": ["아이씨!", "짜증나!", "으아악!", "안 돼애!"],
    "hit": ["아야야!", "아이씨!", "아이고!"],
    "pickup": ["아싸라비아!", "좋았어!", "득템!"],
    "laugh": ["우하하!", "메롱!", "히히히!"],
    "push": ["받아라!", "에이잇!", "간다!"],
    "surprise": ["허억!", "어머나!", "앗 뜨거!"],
}


def make_tts():
    import sherpa_onnx
    d = MODEL.rstrip("/") + "/"
    cfg = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=d + "ko_KO-kss_low.onnx", lexicon="",
                                                   tokens=d + "tokens.txt", data_dir=d + "espeak-ng-data"),
        num_threads=2))
    return sherpa_onnx.OfflineTts(cfg)


def trim(x, sr, thr=0.02):
    a = np.abs(x)
    idx = np.where(a > thr * a.max())[0]
    if len(idx) == 0:
        return x
    s = max(idx[0] - int(0.01 * sr), 0)
    e = min(idx[-1] + int(0.04 * sr), len(x))
    return x[s:e]


def growl(x, sr, amount):
    """털보: 살짝 찢어지게(포화) + 거친 떨림 + 고음 줄임"""
    t = np.arange(len(x)) / sr
    y = np.tanh(x * (1.0 + 3.0 * amount)) / np.tanh(1.0 + 3.0 * amount)
    y *= 1.0 + 0.3 * amount * np.sin(2 * np.pi * 27.0 * t)
    b, a = butter(2, 3200 / (sr / 2))
    return lfilter(b, a, y)


def main():
    import glob
    for old in glob.glob(os.path.join(OUT, "line_*.wav")):
        os.remove(old)
        if os.path.exists(old + ".import"):
            os.remove(old + ".import")
    tts = make_tts()
    count = 0
    for ti, (tname, pitch, rough) in enumerate(TYPES):
        for kind, lines in LINES.items():
            for n, text in enumerate(lines, 1):
                a = tts.generate(text, sid=0, speed=TEMPO / pitch)
                sr = a.sample_rate
                x = np.array(a.samples, dtype=np.float64)
                if len(x) == 0:
                    print("빈 소리:", text)
                    continue
                fr = Fraction(1.0 / pitch).limit_denominator(40)      # 높이배율만큼 빠르게 = 짧게
                y = resample_poly(x, fr.numerator, fr.denominator)
                if rough > 0:
                    y = growl(y / (np.abs(y).max() + 1e-9), sr, rough)
                y = trim(y, sr)
                f = int(0.006 * sr)
                y[:f] *= np.linspace(0, 1, f)
                y[-f:] *= np.linspace(1, 0, f)
                y = y / (np.abs(y).max() + 1e-9) * 0.85
                wavfile.write(os.path.join(OUT, "line_%s_%d_%d.wav" % (kind, ti, n)), sr, (y * 32767).astype(np.int16))
                count += 1
    print(count, "lines")


if __name__ == "__main__":
    main()
