"""곡: 펑크 그루브 (120 BPM, E단조, 약 1분 28초)
구성: 전주 4 → 1절(선창·쉼·따라 치기 ×3, 바로 이어서 ×2) → 후렴(브라스, 2마디 선창 ×2) → 간주(색소폰) → 2절(×4) → 후렴 2(피버) → 마무리

  python3 tools/music/song_funk.py [미리듣기.wav]
  → audio/drum/songs/funk/backing.ogg, audio/drum/songs/funk/chart.json, audio/drum/don.wav, audio/drum/ka.wav
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib

ROOT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

CHORDS = {
    "Em9": {"voicing": [52, 55, 59, 62, 66], "root": 40},      # E G B D F#
    "A13": {"voicing": [55, 61, 64, 66, 69], "root": 45},      # G C# E F# A
    "Cmaj9": {"voicing": [52, 55, 59, 60, 62], "root": 36},    # E G B C D
    "D6": {"voicing": [54, 57, 59, 62, 66], "root": 38},       # F# A B D F#
    "Bm7": {"voicing": [50, 54, 57, 59, 62], "root": 35},      # D F# A B D
}
# 북 패턴 (16분음표 칸) — 둥 = 킥 역할, 딱 = 스네어 역할, hold = 둥 피버 길이
PATTERNS = {
    "A": {"don": [0, 8], "ka": [4, 12]},                                   # 쿵 짝 쿵 짝
    "B": {"don": [0, 6, 8], "ka": [4, 12]},                                # 3박 앞 당김
    "B2": {"don": [0, 8, 10], "ka": [4, 12]},
    "C": {"don": [0, 3, 8, 10], "ka": [4, 12]},                            # 펑크 킥
    "D": {"don": [0, 8, 10], "ka": [4, 7, 12]},                            # 고스트 딱
    "E1": {"don": [0, 3, 8, 14], "ka": [4, 12]},
    "E2": {"don": [0, 6, 8], "ka": [4, 12, 13, 14, 15]},                   # 필인
    "F1": {"don": [0, 3, 8], "ka": [4, 12, 14]},
    "F2": {"don": [0, 6, 10], "ka": [4, 12, 13, 14, 15]},
    "G": {"don": [0, 3, 6, 8], "ka": [4, 12]},
    "H": {"don": [0, 8, 11], "ka": [4, 7, 12, 15]},
    "I": {"don": [0, 2, 8, 10], "ka": [4, 12, 14]},
    "J": {"don": [0, 3, 8, 10, 14], "ka": [4, 12]},
    "K1": {"don": [0, 3, 8, 11], "ka": [4, 12, 14]},
    "K2": {"don": [0, 6, 8], "ka": [4, 12], "hold": {0: 4}},               # 둥~ 피버
    "L1": {"don": [0, 8], "ka": [4, 12, 15], "hold": {8: 4}},
    "L2": {"don": [0, 3, 8], "ka": [4, 7, 12, 13, 14, 15]},                # 마지막 필인
}
RIFFS = {
    "a": [(0, 3, 64), (4, 2, 67), (6, 2, 69), (8, 4, 71), (12, 2, 74), (14, 2, 71)],     # E G A B D B
    "b": [(0, 2, 69), (2, 2, 67), (4, 4, 64), (10, 2, 62), (12, 4, 64)],                # A G E D E
    "c": [(0, 4, 71), (4, 2, 72), (6, 2, 71), (8, 6, 67), (14, 2, 69)],
    "d": [(0, 6, 69), (6, 2, 66), (8, 4, 64), (12, 4, 62)],
}

V = ["Em9", "A13"]          # 1·2절: 두 마디씩 번갈아
CH = ["Cmaj9", "D6", "Bm7", "Em9"]


def verse_bar(i, role, pat=None, sax=None):
    d = {"role": role, "chord": V[i % 2]}
    if pat:
        d["pat"] = pat
    if sax:
        d["sax"] = sax
    return d


bars = []
# 전주 4마디: 색소폰 리프
for k in range(4):
    bars.append(verse_bar(len(bars), "intro", sax="a" if k % 2 == 0 else "b"))
# 1절: 선창 → 쉼 1마디 → 따라 치기 (×3), 그다음 바로 이어서 (×2)
for p in ("A", "B", "B2"):
    bars.append(verse_bar(len(bars), "call", p))
    bars.append(verse_bar(len(bars), "rest", sax="b" if len(bars) % 2 else "a"))
    bars.append(verse_bar(len(bars), "resp", p))
for p in ("C", "D"):
    bars.append(verse_bar(len(bars), "call", p))
    bars.append(verse_bar(len(bars), "resp", p))


def chorus(pairs):
    k = 0
    for (p1, p2) in pairs:
        for role in ("call", "resp"):
            for p in (p1, p2):
                bars.append({"role": role, "chord": CH[k % 4], "pat": p, "brass": True})
                k += 1


chorus([("E1", "E2"), ("F1", "F2")])
# 간주: 색소폰
bars.append({"role": "break", "chord": "Cmaj9", "sax": "c"})
bars.append({"role": "break", "chord": "D6", "sax": "d"})
# 2절: 바로 이어서 ×4
for p in ("G", "H", "I", "J"):
    bars.append(verse_bar(len(bars), "call", p))
    bars.append(verse_bar(len(bars), "resp", p))
chorus([("K1", "K2"), ("L1", "L2")])
bars.append({"role": "outro", "chord": "Em9"})

SONG = {
    "title": "펑크 그루브",
    "bpm": 120,
    "chords": CHORDS,
    "patterns": PATTERNS,
    "riffs": RIFFS,
    "bars": bars,
    # 전주 끝 브라스 몰아치기, 마지막 큰 화음 (마디 -1 = 마지막 마디)
    "extra_brass": [(3, 12, 1, 64, 100), (3, 14, 1, 66, 104)] + [(-1, 0, 12, k, 108) for k in (52, 59, 64, 67, 71)],
}

if __name__ == "__main__":
    out = os.path.join(ROOT_DIR, "audio", "drum", "songs", "funk")
    chart, roles = song_lib.build(SONG, out, drums_dir=os.path.join(ROOT_DIR, "audio", "drum"),
                                  preview_path=sys.argv[1] if len(sys.argv) > 1 else None)
    print("bars %d (%.1fs) turns %d" % (len(bars), chart["length"], len(chart["turns"])))
    print(roles)
