#!/bin/bash
set -e -x

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 INPUT_FILE OUTPUT_DIR CODE_DIR"
    exit 2
fi

INPUT="$1"
OUTPUT="$2"
CODE="$3"
SCRIPTDIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

guess_hdl() {
    if grep -i -q -E '^[[:space:]]*library[[:space:]]+ieee[[:space:]]*;[[:space:]]*$' $INPUT; then
        echo "VHDL"
        return 0
    fi

    if grep -i -q -E -e '^[[:space:]]*from[[:space:]]+amaranth' -e '^[[:space:]]*import[[:space:]]+amaranth' $INPUT; then
        echo "Amaranth"
        return 0
    fi

    echo "SystemVerilog"
    return 0
}

VHDL_INPUT_FILES=("$CODE/top.vhd" "$CODE/dvi_out.vhd" "$CODE/tmds_encoder.vhd" "$CODE/console.vhd")

type=$(guess_hdl)
case $type in
  VHDL)
    VERILOG_INPUT=("$OUTPUT/my_code.ghdl.v")
    cp "$INPUT" "$OUTPUT/my_code.vhd"
    ghdl --synth --std=08 --out=verilog "${VHDL_INPUT_FILES[@]}" "$OUTPUT/my_code.vhd" -e top > "${VERILOG_INPUT[0]}"
    ;;
  Verilog)
    VERILOG_INPUT=("$OUTPUT/my_code.v" "$CODE/top.ghdl.v")
    cp "$INPUT" "${VERILOG_INPUT[0]}"
    ;;
  SystemVerilog)
    VERILOG_INPUT=("$OUTPUT/my_code.sv" "$CODE/top.ghdl.v")
    cp "$INPUT" "${VERILOG_INPUT[0]}"
    ;;
  Amaranth)
    VERILOG_INPUT=("$OUTPUT/my_code.amaranth.v" "$CODE/my_code_wrapper.sv" "$CODE/top.ghdl.v")
    cp "$INPUT" "$OUTPUT/my_code.py"
    PYTHONPATH="$PYTHONPATH:$OUTPUT/" python3 "$SCRIPTDIR/amaranth_build.py" "${VERILOG_INPUT[0]}"
    ;;
  *)
    echo "Unknown HDL $type."
    exit 1
    ;;
esac

yosys -p 'synth_ecp5 -top top -json "'"$OUTPUT/synth.json"'"' "$CODE/pll.v" "${VERILOG_INPUT[@]}"
nextpnr-ecp5 --25k --package "$FPGA_PACKAGE" --lpf "$CODE/icepi-zero.lpf" --json "$OUTPUT/synth.json" --textcfg "$OUTPUT/bitstream.config" --report "$OUTPUT/report.json"
ecppack --compress "$OUTPUT/bitstream.config" "$OUTPUT/bitstream.bit"
