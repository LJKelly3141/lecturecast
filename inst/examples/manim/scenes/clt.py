import csv
import math
from pathlib import Path

from manim import *


def read_csv(name):
    with open(Path(__file__).parent / "data" / name, newline="") as f:
        return list(csv.DictReader(f))


class SampleMeans(Scene):
    def construct(self):
        means = [float(r["mean"]) for r in read_csv("means.csv")]
        lo, hi, nbins = min(means), max(means), 20
        width = (hi - lo) / nbins
        bin_of = lambda m: min(int((m - lo) / width), nbins - 1)
        counts = [0] * nbins
        for m in means:
            counts[bin_of(m)] += 1
        ymax = max(counts) * 1.1
        ax = Axes(x_range=[lo, hi, (hi - lo) / 4], y_range=[0, ymax, max(1, round(ymax / 4))],
                  x_length=11, y_length=5.5, tips=False, axis_config={"include_numbers": False})
        title = Text("Averages of samples of 30", font_size=36).to_edge(UP)
        self.add(ax, title)

        heights = [0] * nbins

        def block(m):
            b = bin_of(m)
            heights[b] += 1
            return Rectangle(width=ax.x_axis.unit_size * width, height=ax.y_axis.unit_size,
                             stroke_width=0.5, fill_opacity=0.8, color=BLUE).move_to(
                ax.c2p(lo + (b + 0.5) * width, heights[b] - 0.5))

        self.next_section("draw a sample")
        for m in means[:8]:
            self.play(FadeIn(block(m), shift=DOWN), run_time=0.4)

        self.next_section("many more samples")
        self.play(LaggedStart(*[FadeIn(block(m)) for m in means[8:]], lag_ratio=0.02), run_time=4)

        self.next_section("the bell shape")
        mu = sum(means) / len(means)
        sd = (sum((m - mu) ** 2 for m in means) / (len(means) - 1)) ** 0.5
        scale = len(means) * width / (sd * math.sqrt(2 * math.pi))
        curve = ax.plot(lambda x: scale * math.exp(-((x - mu) / sd) ** 2 / 2), x_range=[lo, hi], color=YELLOW)
        self.play(Create(curve), run_time=2)
