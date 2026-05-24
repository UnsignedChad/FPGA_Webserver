# ECP5 build notes

## tools

oss-cad-suite from yosyshq ships every tool at known-good versions:

```
curl -L -o ocs.tgz https://github.com/YosysHQ/oss-cad-suite-build/releases/latest/download/oss-cad-suite-linux-x64-$(date +%Y%m%d).tgz
mkdir -p ~/tools && tar -xzf ocs.tgz -C ~/tools
source ~/tools/oss-cad-suite/environment
```

(swap the date for the actual release tag from the github releases page;
the `latest/download/` redirect doesn't honour the date template).

apt versions don't line up: yosys 0.52 + g++14 won't compile
ghdl-yosys-plugin master.

## flow

```
source ~/tools/oss-cad-suite/environment
make ecp5         # synth + place + pack -> build/ecp5/top.bit
make ecp5-prog    # flash via FT232H JTAG
```

## known issues

- **synth is slow.** First attempt ran for 12+ minutes without finishing
  on this design (40+ vhdl modules). yosys `synth_ecp5` was CPU-bound, not
  hung. Either let it run longer (might be 20-30 min total) or invoke a
  minimal synth flow manually:

  ```
  yosys -m ghdl -p "ghdl --std=08 ... -e top_colorlight; \
                    proc; opt; memory; opt; \
                    techmap; opt; \
                    write_json build/ecp5/top.json"
  ```

  ie. skip the full `synth_ecp5` pass list and pick the essentials.

- **PLL phase shift is a guess.** `hdl/ecp5/clocking.vhd`'s
  `CLKOS_CPHASE` was set to 5 (=90 deg from CLKOP=3 at 500 MHz VCO). Expect
  to tweak after first bringup using a scope on `eth_txck`. Use `ecppll
  -i 25 -o 125 --phase=90 -f x.v` for a generated reference if needed.

- **vhdl primitives are local components**, not `library ecp5u`. ghdl
  treats them as blackboxes; yosys binds them via `synth_ecp5`. If you
  add a new ECP5 primitive, declare the component locally in the file
  that uses it.

- **multi-driver / latch fixes**: synth surfaced two real bugs in the
  original code that simulators didn't complain about:
  - `tcp_engine.tosend_seq_num` was written in two processes
  - `FPGA_webserver.leds` was a level-sensitive latch
  Both fixed in tree.
