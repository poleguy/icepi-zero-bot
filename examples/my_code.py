from amaranth import *

class MyCode(Elaboratable):
    def __init__(self, width, height, console_columns, console_rows):
        self.WIDTH = width
        self.HEIGHT = height
        self.CONSOLE_COLUMNS = console_columns
        self.CONSOLE_ROWS = console_rows

        self.px = Signal(signed(32), name="px")
        self.py = Signal(signed(32), name="py")
        self.hsync = Signal(name="hsync")
        self.vsync = Signal(name="vsync")
        
        self.col = Signal(signed(32), name="col")
        self.row = Signal(signed(32), name="row")

        self.char = Signal(signed(32), name="char")
        self.foreground_color = Signal(24, name="foreground_color")
        self.background_color = Signal(24, name="background_color")

    def elaborate(self, platform):
        m = Module()

        frame_counter = Signal(32)
        old_vsync = Signal()

        red = Signal(8)
        green = Signal(8)
        blue = Signal(8)

        m.d.comb += [
            red.eq(self.col * 4),
            green.eq(self.py),
            blue.eq(frame_counter),

            self.background_color.eq(Cat(blue, green, red)),
            self.foreground_color.eq(0xFFFFFF),
            self.char.eq(0)
        ]

        m.d.sync += old_vsync.eq(self.vsync)
        with m.If(~self.vsync & old_vsync):
            m.d.sync += frame_counter.eq(frame_counter + 1)

        return m
