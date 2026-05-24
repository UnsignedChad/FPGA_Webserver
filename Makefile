# GHDL simulation Makefile for FPGA_Webserver
#
# Targets:
#   analyze       - analyze all sim-compatible sources (default)
#   TB=name run   - elaborate + run a testbench
#   TB=name wave  - run with .ghw waveform output
#   sim-tbs       - run every sim-compatible testbench
#   clean

GHDL       := ghdl
STD        := --std=08
GHDL_FLAGS := $(STD) --workdir=sim -fsynopsys -frelaxed

# Files excluded from GHDL sim:
#   arp_resolver.vhd      - half-written dead code (undeclared signals, never instantiated)
#   clocking.vhd          - Xilinx UNISIM (MMCM)
#   tx_rgmii.vhd          - Xilinx UNISIM (ODDR)
#   receive_raw_data.vhd  - Xilinx UNISIM (IDDR)
#   FPGA_webserver.vhd    - top-level wrapper that instantiates the above
SIM_EXCLUDE := -name arp_resolver.vhd -o -name clocking.vhd -o -name tx_rgmii.vhd -o -name receive_raw_data.vhd -o -name FPGA_webserver.vhd

RTL_SIM := $(shell find hdl -path hdl/ecp5 -prune -o -name "*.vhd" ! \( $(SIM_EXCLUDE) \) -print | sort)
SIM_STUBS := $(shell find sim_models -name "*.vhd" 2>/dev/null | sort)

# Testbenches that target FPGA_webserver (top, needs UNISIM) excluded from sim flow
TB_SIM_EXCLUDE := -name tb_FPGA_webserver.vhd
TBS_SIM := $(shell find testbenches -name "tb_*.vhd" ! \( $(TB_SIM_EXCLUDE) \) | sort)

ALL_SIM_SRC := $(RTL_SIM) $(SIM_STUBS) $(TBS_SIM)
TBS_NAMES := $(notdir $(basename $(TBS_SIM)))

.PHONY: all analyze run wave sim-tbs clean help

help:
	@echo "Targets:"
	@echo "  analyze       - ghdl -a on all sim sources"
	@echo "  TB=name run   - elaborate + run a testbench (1 ms sim time)"
	@echo "  TB=name wave  - run with .ghw waveform output"
	@echo "  sim-tbs       - run every sim-compatible testbench"
	@echo "  clean"
	@echo ""
	@echo "Sim testbenches:"
	@for tb in $(TBS_NAMES); do echo "  $$tb"; done

analyze: sim/.analyzed

sim/.analyzed: $(ALL_SIM_SRC)
	@mkdir -p sim
	@for f in $(ALL_SIM_SRC); do \
	    echo "  ANALYZE $$f"; \
	    $(GHDL) -a $(GHDL_FLAGS) $$f || exit 1; \
	done
	@touch sim/.analyzed

run: analyze
	@test -n "$(TB)" || { echo "Set TB=<testbench-name>"; exit 1; }
	$(GHDL) -e $(GHDL_FLAGS) $(TB)
	$(GHDL) -r $(GHDL_FLAGS) $(TB) --ieee-asserts=disable --stop-time=$(or $(STOP),1ms)

wave: analyze
	@test -n "$(TB)" || { echo "Set TB=<testbench-name>"; exit 1; }
	$(GHDL) -e $(GHDL_FLAGS) $(TB)
	$(GHDL) -r $(GHDL_FLAGS) $(TB) --ieee-asserts=disable --wave=sim/$(TB).ghw --stop-time=$(or $(STOP),1ms)

sim-tbs: analyze
	@fail=0; \
	for tb in $(TBS_NAMES); do \
	    echo "=== $$tb ==="; \
	    $(GHDL) -e $(GHDL_FLAGS) $$tb 2>&1 && \
	    $(GHDL) -r $(GHDL_FLAGS) $$tb --ieee-asserts=disable --stop-time=$(or $(STOP),1ms) 2>&1 || fail=1; \
	done; \
	exit $$fail

clean:
	rm -rf sim/

# ---------------------------------------------------------------------
# ecp5 build for colorlight 5a-75b. requires ghdl-yosys-plugin + nextpnr-ecp5
# + fpga-trellis + openfpgaloader. apt has the last three; the plugin
# needs building from source against the installed ghdl.
#
#   make ecp5             # synthesise + place + pack to build/top.bit
#   make ecp5-prog        # flash via FT232H JTAG
# ---------------------------------------------------------------------

ECP5_PART     := 25k
ECP5_PACKAGE  := CABGA256
ECP5_TOP      := top_colorlight
ECP5_LPF      := constraints/colorlight_5a_75b.lpf
ECP5_BUILD    := build/ecp5

# rtl sources for synth: everything in hdl/ EXCEPT the xilinx-specific
# originals that the ecp5/ directory shadows, the broken arp_resolver,
# and the nexys-targeted FPGA_webserver port shell (top_colorlight wraps
# the same entity but with the right pin shapes).
ECP5_RTL := $(shell find hdl \
    -name "*.vhd" \
    ! -name arp_resolver.vhd \
    ! -name clocking.vhd \
    ! -name receive_raw_data.vhd \
    ! -name tx_rgmii.vhd \
    | sort) hdl/ecp5/clocking.vhd hdl/ecp5/receive_raw_data.vhd hdl/ecp5/tx_rgmii.vhd hdl/ecp5/top_colorlight.vhd

$(ECP5_BUILD):
	mkdir -p $@

$(ECP5_BUILD)/top.json: $(ECP5_RTL) | $(ECP5_BUILD)
	yosys -m ghdl -p "ghdl --std=08 -fsynopsys -frelaxed $(ECP5_RTL) -e $(ECP5_TOP); synth_ecp5 -json $@"

$(ECP5_BUILD)/top.config: $(ECP5_BUILD)/top.json $(ECP5_LPF)
	nextpnr-ecp5 --$(ECP5_PART) --package $(ECP5_PACKAGE) --speed 6 \
	  --json $< --lpf $(ECP5_LPF) --textcfg $@

$(ECP5_BUILD)/top.bit: $(ECP5_BUILD)/top.config
	ecppack $< $@

.PHONY: ecp5 ecp5-prog
ecp5: $(ECP5_BUILD)/top.bit

ecp5-prog: $(ECP5_BUILD)/top.bit
	openFPGALoader -c ft232 $<
