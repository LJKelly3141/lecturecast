import csv
from pathlib import Path

from manim import *


def read_csv(name):
    with open(Path(__file__).parent / "data" / name, newline="") as f:
        return list(csv.DictReader(f))


class DemandShift(Scene):
    def construct(self):
        c = {r["curve"]: (float(r["intercept"]), float(r["slope"])) for r in read_csv("curves.csv")}
        ax = Axes(x_range=[0, 10, 2], y_range=[0, 10, 2], x_length=7, y_length=4.5, tips=False)
        labels = ax.get_axis_labels(Text("Quantity", font_size=24), Text("Price", font_size=24))

        def line(name, color):
            # Keep the line inside the axes: x where 0 <= a + b * x <= 10.
            a, b = c[name]
            ends = sorted([(0 - a) / b, (10 - a) / b])
            return ax.plot(lambda x: a + b * x, x_range=[max(0, ends[0]), min(10, ends[1])], color=color)

        def equilibrium(name):
            (a1, b1), (a2, b2) = c["supply"], c[name]
            x = (a2 - a1) / (b1 - b2)
            return ax.c2p(x, a1 + b1 * x)

        supply = line("supply", BLUE)
        demand = line("demand", RED)
        dot = Dot(equilibrium("demand"), color=YELLOW)
        self.add(ax, labels)
        self.play(Create(supply), Create(demand), run_time=1.5)
        self.play(FadeIn(dot))

        self.next_section("demand shifts right")
        self.play(Transform(demand, line("demand_new", RED)), dot.animate.move_to(equilibrium("demand_new")), run_time=2)

        self.next_section("price and quantity rise")
        self.play(Create(ax.get_lines_to_point(dot.get_center(), color=GRAY)), run_time=1.5)
