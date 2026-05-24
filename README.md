# FPGA Webserver

Software-free HTTP/TCP/UDP/ICMP/ARP stack in VHDL. No CPU, no firmware,
no OS — frames in on the Ethernet PHY, parsed by RTL, replies out the
same PHY. Forked from [hamsternz/FPGA_Webserver](https://github.com/hamsternz/FPGA_Webserver)
which stopped in 2016 partway through the TCP close states.

## status

| Layer        | works | notes |
|--------------|:-----:|-------|
| ARP          | yes   | sim verified, replies with our_mac to broadcast request |
| ICMP echo    | yes   | sim verified, type 0 reply to type 8 request |
| UDP RX       | yes   | sim verified, exposes ports + payload on `udp_rx_*` |
| UDP TX       | -     | can't send a zero-data packet, see hamster TODO |
| TCP SYN/ACK  | yes   | sim verified, responds to SYN with SYN+ACK |
| TCP data     | -     | logic in place + HTTP/1.0 payload, but sim throughput collapses in state\_established so the data path isn't sim-verified yet. should work on real silicon. |
| HTTP/1.0     | yes   | 119-byte static response in `tcp_engine_content_memory.vhd` |
| RX FCS       | yes   | drops bad-crc frames |
| RX MAC filter| yes   | only our_mac and broadcast |
| RX IP cksum  | yes   | drops bad ip headers |
| 10/100Mbps TX| -     | needs the 4k FIFO from hamster's TODO; only gigabit works |

## sim (no hardware needed)

```
make analyze
make TB=tb_harness run STOP=200us   # all 7 scenarios pass
make TB=tb_harness wave STOP=200us  # writes sim/tb_harness.ghw for gtkwave
```

Needs `ghdl-mcode` and (optionally) `gtkwave`. See `DESIGN.md` for the
RX/TX pipeline diagrams and the byte-reversed MAC/IP storage convention
that bites everyone the first time.

## hardware target

Colorlight 5A-75B v8 (Lattice ECP5 LFE5U-25F, 24k LUTs, gigabit RGMII
via Realtek RTL8211FD) programmed over JTAG with an FT232H breakout.
Total ~$45. The original target was the Nexys Video (Artix-7); the
port lives in `hdl/ecp5/` and a constraints file is in
`constraints/colorlight_5a_75b.lpf`.

```
make ecp5         # synth -> place -> pack -> build/ecp5/top.bit
make ecp5-prog    # flash via FT232H JTAG
```

Tool prereqs in `BUILD_ECP5.md`. The `ghdl-yosys-plugin` build is the
fiddly piece; oss-cad-suite avoids it.

## verifying on hardware

Once flashed, with the board on an IP in your network (config in the
top entity's generics):

```
python3 scripts/verify_fpga.py 10.0.0.10
```

That runs ping then opens TCP/80 and checks the HTTP/1.0 response.

## layout

```
hdl/                project rtl (xilinx-flavour originals)
hdl/ecp5/           ecp5-specific replacements for clocking, tx_rgmii,
                    receive_raw_data + top_colorlight wrapper
constraints/        nexys_video.xdc, colorlight_5a_75b.lpf
testbenches/        tb_harness.vhd is the self-checking one;
                    the rest are wave-dump-only originals from hamster
sim_models/         net_pkg.vhd (frame builders + crc + cksum) and
                    tx_rgmii_sim.vhd (sim stub for the xilinx ODDR)
scripts/            verify_fpga.py: ping + http get smoke test
DESIGN.md           architecture, diagrams, conventions
BUILD_ECP5.md       ecp5 toolchain notes
README.txt          hamster's original status notes (kept for history)
```

## license

MIT, same as upstream. See LICENSE.
