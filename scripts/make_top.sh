#!/bin/bash

ghdl --synth --std=08 --out=verilog code/top.vhd code/dvi_out.vhd code/tmds_encoder.vhd code/console.vhd -e top > code/top.ghdl.v
