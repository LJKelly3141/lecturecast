from manim import *


class Tiny(Scene):
    def construct(self):
        sq = Square(color=BLUE, fill_opacity=0.5)
        self.play(Create(sq), run_time=0.5)
        self.next_section("grow")
        self.play(sq.animate.scale(1.5), run_time=0.5)
        self.next_section("spin")
        self.play(Rotate(sq, PI / 4), run_time=0.5)
