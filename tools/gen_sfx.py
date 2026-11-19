"""効果音 9 個(仕様書 §9.13)を合成して assets/sfx/<名前>.wav に書く。標準ライブラリだけ・乱数は使わない(何度回しても同じバイト列)。
16bit PCM・モノラル・22050 Hz。合計 300 KB 以下(非機能 NFR-7)。

    python tools/gen_sfx.py
"""

import math
import struct
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"
RATE = 22050
TAU = 2 * math.pi


def tone(buf, at, dur, f0, f1=None, gain=1.0, decay=0.0, square=False):
    """音 1 本を buf に足す。f0→f1 へ直線で動き、exp(-decay*t) で消える。square なら矩形に近い音(奇数倍音 3 本)。"""
    f1 = f1 or f0
    start = int(at * RATE)
    n = int(dur * RATE)
    while len(buf) < start + n:
        buf.append(0.0)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        e = gain * math.exp(-decay * t) * min(1.0, (n - i) / (0.004 * RATE), i / (0.001 * RATE))
        s = math.sin(phase)
        if square:
            s += math.sin(3 * phase) / 3 + math.sin(5 * phase) / 5
        buf[start + i] += e * s
        phase += TAU * (f0 + (f1 - f0) * i / n) / RATE


def write(name, buf, peak):
    top = max(abs(x) for x in buf) or 1.0
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(x / top * peak * 32767)) for x in buf))


def main():
    b = []
    tone(b, 0, 0.03, 2400, 1800, decay=120)  # 打鍵: 短く乾いた音
    write("key", b, 0.25)
    b = []
    tone(b, 0, 0.09, 880, square=True, decay=8)
    tone(b, 0.11, 0.09, 880, square=True, decay=8)  # アラート: 2 回鳴る
    write("alert", b, 0.55)
    b = []
    tone(b, 0, 0.35, 220, 150, square=True, decay=4)  # 悪化: 低い警告
    write("escalated", b, 0.7)
    b = []
    tone(b, 0, 0.08, 660, decay=10)
    tone(b, 0.07, 0.18, 990, decay=12)  # 直った: 上がる 2 音
    write("fixed", b, 0.6)
    b = []
    tone(b, 0, 0.12, 180, square=True, decay=6)  # 打ち間違い: 短いブザー
    write("cmd_error", b, 0.45)
    b = []
    tone(b, 0, 0.28, 110, 90, square=True, decay=3)  # 禁止の操作: 低いブザー
    write("forbidden", b, 0.6)
    b = []
    tone(b, 0, 0.05, 1500, decay=40)  # 補完の候補なし: 小さい音
    write("bell", b, 0.3)
    b = []
    for k, f in enumerate([523, 659, 784, 1047]):
        tone(b, k * 0.12, 0.3, f, decay=6)  # 夜が明けた
    write("over", b, 0.6)
    b = []
    tone(b, 0, 0.04, 1200, 1400, decay=30)  # メニューの選択
    write("select", b, 0.35)
    total = sum(p.stat().st_size for p in OUT.glob("*.wav"))
    print(f"{len(list(OUT.glob('*.wav')))} 個、合計 {total:,} バイト")


if __name__ == "__main__":
    main()
