"""곡: 붐뱁 스트리트 (92 BPM, D단조, 약 1분 31초) — 콘트라베이스, 로즈 피아노 찹, 비브라폰 훅, 스트링 패드
  python3 tools/music/song_hiphop.py [미리듣기.wav] → audio/drum/songs/hiphop/backing.ogg, song.gd
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L

CHORDS = {
    "Dm9": {"voicing": [53, 57, 60, 64], "root": 38},
    "Bbmaj7": {"voicing": [53, 57, 58, 62], "root": 34},
    "Gm9": {"voicing": [55, 58, 62, 65, 69], "root": 43},
    "A7": {"voicing": [55, 58, 61, 64], "root": 45},
}
PATTERNS = {
    "A": {"don": [0, 10], "ka": [4, 12]},
    "B": {"don": [0, 3, 10], "ka": [4, 12]},
    "C": {"don": [0, 7, 10], "ka": [4, 12]},
    "D": {"don": [0, 2, 10], "ka": [4, 12]},
    "h1": {"don": [0, 10], "ka": [4, 12, 15]},
    "h2": {"don": [0, 3, 8], "ka": [4, 12]},
    "h3": {"don": [0, 7, 10], "ka": [4, 12]},
    "h4": {"don": [0, 10], "ka": [4, 12, 14]},
    "E": {"don": [0, 3, 7, 10], "ka": [4, 12]},
    "F": {"don": [0, 10, 13], "ka": [4, 12]},
    "G": {"don": [0, 6, 10], "ka": [4, 9, 12]},
    "k1": {"don": [0, 10], "ka": [4, 12, 15]},
    "k2": {"don": [0, 8], "ka": [4, 12], "hold": {0: 4}},          # 둥~ 피버
    "l1": {"don": [0, 3, 10], "ka": [4, 12]},
    "l2": {"don": [0, 8, 10], "ka": [4, 12, 13, 14, 15]},           # 마지막 필인
}
RIFFS = {
    "v1": [(0, 3, 74), (3, 1, 72), (4, 4, 69), (10, 2, 67), (12, 4, 69)],
    "v2": [(0, 2, 72), (2, 2, 74), (4, 6, 77), (12, 2, 76), (14, 2, 74)],
    "v3": [(0, 6, 76), (6, 2, 74), (8, 4, 73), (12, 4, 69)],
    "v4": [(0, 4, 74), (6, 2, 72), (8, 8, 69)],
    "s1": [(0, 6, 70), (6, 2, 69), (8, 8, 67)],
    "s2": [(0, 6, 69), (6, 2, 67), (8, 8, 64)],
    "s3": [(0, 4, 65), (4, 4, 69), (8, 8, 72)],
    "s4": [(0, 12, 74), (12, 4, 72)],
}

B = L.Bars({"intro": ["Dm9", "Bbmaj7"], "verse": ["Dm9", "Dm9", "Bbmaj7", "A7"], "chorus": ["Gm9", "A7", "Dm9", "Bbmaj7"],
            "outro": ["Dm9"]})
B.section("intro").plain("intro", 2, leads=("v1", "v2"))
B.section("verse").echo(["A", "B"], rest=True, rest_leads=("v3", "v4"))
B.echo(["C", "D"])
B.section("chorus").echo2([("h1", "h2"), ("h3", "h4")])
B.section("verse").echo(["E", "F", "G"])
B.section("chorus").echo2([("k1", "k2"), ("l1", "l2")])
B.section("outro").plain("outro", 1, leads=("v4",))
k = 0
for bar in B.bars:
    if bar["sec"] == "chorus":
        bar["lead"] = ("s1", "s2", "s3", "s4")[k % 4]
        k += 1

SONG = {
    "title": "붐뱁 스트리트", "bpm": 92, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": B.bars,
    "reverb": 0.2,
    "mix": {0: 96, 1: 127, 2: 115, 3: 88, 9: 127},
    "programs": {0: (0, 32), 1: (0, 4), 2: (0, 49), 3: (0, 11), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 108, "style": "boom"},
        {"type": "chord", "ch": 1, "vel": 84, "shift": 12,
         "steps": {"intro": [(0, 14, 84)], "default": [(0, 5, 86), (6, 1, 68), (7, 3, 76), (14, 2, 66)]}},
        {"type": "pad", "ch": 2, "vel": 58, "when": ["chorus", "outro"], "steps": [(0, 16, 58)]},
        {"type": "lead", "ch": 3, "vel": 86},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49,
         "steps": [(0, 70), (2, 50), (4, 62), (6, 50), (7, 38), (8, 70), (10, 50), (12, 62), (14, 54)]},
        {"type": "perc", "ch": 9, "key": 70, "when": ["chorus"], "steps": [(s, 26 if s % 2 else 34) for s in range(16)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "hiphop", sys.argv)
