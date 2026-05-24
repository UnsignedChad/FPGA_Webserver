# ECP5 build notes

Tools needed on the host:

```
apt-get install yosys nextpnr-ecp5 fpga-trellis openfpgaloader \
                libghdl-dev yosys-dev ghdl-llvm
```

`yosys -m ghdl` calls into `ghdl-yosys-plugin`. The plugin must be built
against the installed yosys + ghdl pair, and the apt versions sometimes
do not line up. As of debian trixie (yosys 0.52, ghdl 5.0.1) the master
branch does not compile cleanly against g++14. Workarounds:

- `oss-cad-suite` from yosyshq packages all tools at a known-good combo
- pin yosys + plugin to matching tags built from source
- use `ghdl --synth=verilog` then `yosys read_verilog` (no plugin)

Once `yosys -m ghdl ...` works on a trivial design, the project flow is:

```
make ecp5            # synth + place + pack -> build/ecp5/top.bit
make ecp5-prog       # flash via FT232H JTAG
```

The PLL phase shift in `hdl/ecp5/clocking.vhd` is a guess. Expect to
tweak `CLKOS_CPHASE` after first bringup using a scope on `eth_txck`.
