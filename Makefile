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

RTL_SIM := $(shell find hdl -name "*.vhd" ! \( $(SIM_EXCLUDE) \) | sort)

# Testbenches that target FPGA_webserver (top, needs UNISIM) excluded from sim flow
TB_SIM_EXCLUDE := -name tb_FPGA_webserver.vhd
TBS_SIM := $(shell find testbenches -name "tb_*.vhd" ! \( $(TB_SIM_EXCLUDE) \) | sort)

ALL_SIM_SRC := $(RTL_SIM) $(TBS_SIM)
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
	$(GHDL) -r $(GHDL_FLAGS) $(TB) --stop-time=$(or $(STOP),1ms)

wave: analyze
	@test -n "$(TB)" || { echo "Set TB=<testbench-name>"; exit 1; }
	$(GHDL) -e $(GHDL_FLAGS) $(TB)
	$(GHDL) -r $(GHDL_FLAGS) $(TB) --wave=sim/$(TB).ghw --stop-time=$(or $(STOP),1ms)

sim-tbs: analyze
	@fail=0; \
	for tb in $(TBS_NAMES); do \
	    echo "=== $$tb ==="; \
	    $(GHDL) -e $(GHDL_FLAGS) $$tb 2>&1 && \
	    $(GHDL) -r $(GHDL_FLAGS) $$tb --stop-time=$(or $(STOP),1ms) 2>&1 || fail=1; \
	done; \
	exit $$fail

clean:
	rm -rf sim/
