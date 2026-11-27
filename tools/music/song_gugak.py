"""곡: 신명 장단 (104 BPM, E 계면조 5음, 약 1분 28초) — 가야금(고토) 뜯기, 대금(샤쿠하치) 가락, 해금(피들) 후렴, 꽹과리 대신 아고고
  덩(둥) = 장구 북편, 덕(딱) = 채편 느낌. 3·3·2 엇박 장단을 섞는다
  python3 tools/music/song_gugak.py [미리듣기.wav] → audio/drum/songs/gugak/backing.ogg, song.gd
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L

CHORDS = {
    "Em": {"voicing": [52, 55, 59, 62], "root": 40},
    "G": {"voicing": [50, 55, 59, 62], "root": 43},
    "Dsus": {"voicing": [50, 55, 57, 62], "root": 38},
    "Asus": {"voicing": [52, 57, 59, 64], "root": 45},
}
PATTERNS = {
    "A": {"don": [0, 8], "ka": [4, 12]},
    "B": {"don": [0, 6, 12], "ka": [4, 10]},                          # 3·3·2
    "C": {"don": [0, 8], "ka": [4, 6, 12]},
    "D": {"don": [0, 3, 8], "ka": [6, 12]},
    "s1": {"don": [0, 6, 12], "ka": [4, 10]},
    "s2": {"don": [0, 8], "ka": [4, 12, 14]},
    "s3": {"don": [0, 3, 8], "ka": [6, 12]},
    "s4": {"don": [0, 8, 10], "ka": [4, 12, 14]},
    "E": {"don": [0, 6, 8], "ka": [4, 12]},
    "F": {"don": [0, 3, 8], "ka": [4, 12, 14]},
    "G": {"don": [0, 6, 12], "ka": [4, 10, 14]},
    "k1": {"don": [0, 6, 12], "ka": [4, 10]},
    "k2": {"don": [0, 8], "ka": [4, 12], "hold": {0: 4}},             # 덩~ 피버
    "l1": {"don": [0, 3, 8], "ka": [6, 12]},
    "l2": {"don": [0, 8], "ka": [4, 6, 10, 12, 14]},                  # 마지막 몰아치기
}
RIFFS = {
    # 대금: 길게 끌다 꺾기
    "t1": [(0, 6, 76), (6, 2, 74), (8, 2, 76), (10, 6, 79)],
    "t2": [(0, 4, 81), (4, 4, 79), (8, 2, 76), (10, 2, 74), (12, 4, 71)],
    "t3": [(0, 6, 74), (6, 2, 71), (8, 8, 69)],
    "t4": [(0, 4, 71), (4, 2, 74), (6, 2, 71), (8, 8, 76)],
    "b1": [(0, 2, 83), (2, 2, 81), (4, 4, 79), (8, 2, 81), (10, 6, 76)],
    "b2": [(0, 8, 76), (8, 4, 74), (12, 4, 71)],
    # 해금 후렴
    "h1": [(0, 6, 71), (6, 2, 74), (8, 8, 76)],
    "h2": [(0, 6, 74), (6, 2, 71), (8, 8, 69)],
    "h3": [(0, 4, 76), (4, 4, 79), (8, 4, 76), (12, 4, 74)],
    "h4": [(0, 12, 76), (12, 4, 74)],
}

B = L.Bars({"intro": ["Em", "Dsus"], "verse": ["Em", "Em", "Dsus", "Em"], "chorus": ["G", "Dsus", "Em", "Em"],
            "break": ["Asus", "Dsus"], "outro": ["Em"]})
B.section("intro").plain("intro", 2, leads=("t1", "t2"))
B.section("verse").echo(["A", "B", "C"], rest=True, rest_leads=("t3", "t4", "t1"))
B.echo(["D"])
B.section("chorus").echo2([("s1", "s2"), ("s3", "s4")])
B.section("break").plain("break", 2, leads=("b1", "b2"))
B.section("verse").echo(["E", "F", "G"])
B.section("chorus").echo2([("k1", "k2"), ("l1", "l2")])
B.section("outro").plain("outro", 1)
k = 0
for bar in B.bars:
    if bar["sec"] == "chorus":
        bar["lead2"] = ("h1", "h2", "h3", "h4")[k % 4]
        k += 1

SONG = {
    "title": "신명 장단", "bpm": 104, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": B.bars,
    "reverb": 0.22,
    "mix": {0: 80, 1: 82, 2: 127, 3: 100, 4: 78, 9: 120},
    "programs": {0: (0, 32), 1: (0, 107), 2: (0, 77), 3: (0, 110), 4: (0, 107), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 92, "style": "anchor", "pops": ()},
        {"type": "arp", "ch": 1, "vel": 62, "order": {"chorus": [0, 2, 3, 2, 1, 2, 3, 2], "default": [0, 2, 1, 3]},
         "every": 2, "dur": 2.5, "shift": 12},
        {"type": "chord", "ch": 4, "vel": 56, "voices": [0, 2], "steps": [(0, 4, 58), (8, 4, 50)]},
        {"type": "lead", "ch": 2, "vel": 116},
        {"type": "lead", "ch": 3, "vel": 100, "key": "lead2"},
        {"type": "perc", "ch": 9, "key": 67, "outro_key": 52, "skip": ["break"],
         "steps": {"chorus": [(s, 56 if s % 4 == 0 else 42) for s in range(0, 16, 2)], "default": [(0, 52), (4, 40), (8, 52), (12, 40)]}},
    ],
    "extra": [(i, 0, 12, 9, 52, 58) for i, b in enumerate(B.bars)
              if b["sec"] in ("chorus", "break") and (i == 0 or B.bars[i - 1]["sec"] != b["sec"])],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "gugak", sys.argv)
