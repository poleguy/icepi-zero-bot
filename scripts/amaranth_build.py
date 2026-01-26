import sys
from amaranth.back import verilog

from my_code import MyCode

if len(sys.argv) < 2:
    print(f"Usage: {sys.argv[0]} OUTPUT_FILE")
    sys.exit(2)

width=640
height=480
console_columns=width/8
console_rows=height/8

module = MyCode(width=width, height=height, console_columns=console_columns, console_rows=console_rows)
with open(sys.argv[1], "w") as f:
    f.write(verilog.convert(module, name="my_code_no_generics",
        ports=[
            module.px, module.py, module.hsync, module.vsync, module.col, module.row, 
            module.char, module.foreground_color, module.background_color
        ],
        emit_src=False,
        strip_internal_attrs=True
    ))
