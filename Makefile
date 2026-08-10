SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
COMMON_ROOT ?= $(abspath $(ROOT)/../common)
BUILD_DIR ?= $(ROOT)/build
IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
VERIBLE_FORMAT ?= verible-verilog-format
CLANG_FORMAT ?= clang-format-14
HOST_CC ?= cc
PYTHON ?= python3
SBY ?= sby
SV2V ?= sv2v

RTL_SRCS := rtl/pwm_pkg.sv rtl/pwm_tickgen.sv rtl/pwm_timer.sv rtl/pwm_channel.sv \
            rtl/pwm_deadtime.sv rtl/pwm_carrier.sv rtl/pwm_capture.sv rtl/pwm_core.sv \
            rtl/pwm_reg.sv rtl/pwm_if.sv rtl/apb4_pwm.sv
CORE_SRCS := rtl/pwm_tickgen.sv rtl/pwm_timer.sv rtl/pwm_channel.sv \
             rtl/pwm_deadtime.sv rtl/pwm_carrier.sv rtl/pwm_capture.sv rtl/pwm_core.sv \
             rtl/pwm_reg.sv
RTL_HDRS := rtl/pwm_define.svh
C_SRCS := sw/src/pwm.c sw/tests/test_pwm.c
C_HDRS := sw/include/pwm.h sw/include/pwm_regs.h

COMMON_APB := $(COMMON_ROOT)/rtl/interface/apb4_if.sv
COMMON_REGISTER := $(COMMON_ROOT)/rtl/utils/register.sv
COMMON_FIFO := $(COMMON_ROOT)/rtl/utils/fifo.sv
COMMON_CDC := $(COMMON_ROOT)/rtl/cdc/cdc_sync.sv
IVERILOG_OUT := $(BUILD_DIR)/iverilog/pwm_tb.vvp
IVERILOG_CHANNEL_OUT := $(BUILD_DIR)/iverilog/pwm_channel_tb.vvp
VERILATOR_DIR := $(BUILD_DIR)/verilator
HOST_TEST := $(BUILD_DIR)/host/test_pwm

.PHONY: help doctor format format-check register-check lint test test-iverilog \
	test-verilator test-host synth formal clean

help:
	@printf '%s\n' \
	  'pwm targets:' \
	  '  doctor          verify required tools and Common checkout' \
	  '  format-check    verify SystemVerilog and C formatting' \
	  '  register-check  compare hand-written RTL and C definitions' \
	  '  lint            run Verilator lint on the APB4 wrapper' \
	  '  test            run Icarus, Verilator, and host C tests' \
	  '  synth           synthesize the PWM controller with Yosys' \
	  '  formal          prove controller properties with SBY/Bitwuzla'

doctor:
	@for tool in $(IVERILOG) $(VVP) $(VERILATOR) $(VERIBLE_FORMAT) $(CLANG_FORMAT) \
		$(HOST_CC) $(PYTHON) yosys $(SBY) $(SV2V) bitwuzla; do \
		command -v $$tool >/dev/null || { echo "missing tool: $$tool" >&2; exit 1; }; \
	done
	@test -f $(COMMON_APB) || { echo "missing Common checkout: $(COMMON_ROOT)" >&2; exit 1; }

format:
	$(VERIBLE_FORMAT) --flagfile=$(ROOT)/.verible-format --inplace $(RTL_SRCS) $(RTL_HDRS) \
		dv/unit/pwm_tb.sv dv/unit/pwm_channel_tb.sv dv/unit/apb4_pwm_tb.sv formal/pwm_formal.sv
	$(CLANG_FORMAT) -i $(C_SRCS) $(C_HDRS)

format-check:
	@set -e; for file in $(RTL_SRCS) $(RTL_HDRS) dv/unit/pwm_tb.sv dv/unit/pwm_channel_tb.sv \
		dv/unit/apb4_pwm_tb.sv formal/pwm_formal.sv; do \
		tmp=$$(mktemp); $(VERIBLE_FORMAT) --flagfile=$(ROOT)/.verible-format $$file > $$tmp; \
		cmp -s $$file $$tmp || { echo "SystemVerilog format mismatch: $$file" >&2; \
		rm -f $$tmp; exit 1; }; rm -f $$tmp; \
	done
	@set -e; for file in $(C_SRCS) $(C_HDRS); do \
		tmp=$$(mktemp); $(CLANG_FORMAT) $$file > $$tmp; cmp -s $$file $$tmp || { \
			echo "C format mismatch: $$file" >&2; rm -f $$tmp; exit 1; }; rm -f $$tmp; \
	done

register-check:
	$(PYTHON) scripts/check_register_parity.py

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-GENUNNAMED -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL \
		--top-module apb4_pwm -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl/interface \
		-I$(COMMON_ROOT)/rtl -I$(COMMON_ROOT)/rtl/utils $(COMMON_APB) $(COMMON_REGISTER) \
		$(COMMON_FIFO) $(COMMON_CDC) $(RTL_SRCS)

$(IVERILOG_OUT): $(CORE_SRCS) $(RTL_HDRS) dv/unit/pwm_tb.sv
	@mkdir -p $(@D)
	$(IVERILOG) -g2012 -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl -o $@ \
		$(COMMON_REGISTER) $(COMMON_FIFO) $(COMMON_CDC) $(CORE_SRCS) \
		dv/unit/pwm_tb.sv -s pwm_tb

$(IVERILOG_CHANNEL_OUT): rtl/pwm_channel.sv $(RTL_HDRS) dv/unit/pwm_channel_tb.sv
	@mkdir -p $(@D)
	$(IVERILOG) -g2012 -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl -o $@ \
		$(COMMON_REGISTER) rtl/pwm_channel.sv dv/unit/pwm_channel_tb.sv -s pwm_channel_tb

test-iverilog: $(IVERILOG_OUT) $(IVERILOG_CHANNEL_OUT)
	$(VVP) $(IVERILOG_OUT) | tee $(BUILD_DIR)/iverilog/test.log
	@grep -q PWM_TEST_PASS $(BUILD_DIR)/iverilog/test.log
	$(VVP) $(IVERILOG_CHANNEL_OUT) | tee $(BUILD_DIR)/iverilog/channel-test.log
	@grep -q PWM_CHANNEL_TEST_PASS $(BUILD_DIR)/iverilog/channel-test.log

test-verilator:
	@mkdir -p $(VERILATOR_DIR) $(BUILD_DIR)/ccache-tmp $(BUILD_DIR)/tmp
	CCACHE_DISABLE=1 CCACHE_TEMPDIR=$(BUILD_DIR)/ccache-tmp TMPDIR=$(BUILD_DIR)/tmp \
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-GENUNNAMED \
	-Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -DSV_ASSRT_DISABLE \
	--Mdir $(VERILATOR_DIR) --top-module apb4_pwm_tb -Irtl -I$(COMMON_ROOT)/rtl \
	$(COMMON_APB) $(COMMON_REGISTER) $(COMMON_FIFO) $(COMMON_CDC) $(RTL_SRCS) \
	dv/unit/apb4_pwm_tb.sv
	$(VERILATOR_DIR)/Vapb4_pwm_tb | tee $(VERILATOR_DIR)/test.log
	@grep -q APB4_PWM_TEST_PASS $(VERILATOR_DIR)/test.log

$(HOST_TEST): $(C_SRCS) $(C_HDRS)
	@mkdir -p $(@D)
	$(HOST_CC) -std=c11 -Wall -Wextra -Werror -pedantic -Isw/include $(C_SRCS) -o $@

test-host: $(HOST_TEST)
	$(HOST_TEST)

test: test-iverilog test-verilator test-host

synth:
	@mkdir -p $(BUILD_DIR)/synth
	$(SV2V) --top pwm_core -Irtl -I$(COMMON_ROOT)/rtl $(COMMON_REGISTER) $(COMMON_FIFO) \
		$(COMMON_CDC) rtl/pwm_tickgen.sv rtl/pwm_timer.sv rtl/pwm_channel.sv \
		rtl/pwm_deadtime.sv rtl/pwm_carrier.sv rtl/pwm_capture.sv rtl/pwm_core.sv \
		--write=$(BUILD_DIR)/synth/pwm_core.v
	yosys -p 'read_verilog $(BUILD_DIR)/synth/pwm_core.v; hierarchy -top pwm_core; proc; opt; check; stat' \
		| tee $(BUILD_DIR)/synth/yosys.log

formal:
	@mkdir -p $(BUILD_DIR)/formal-src
	$(SV2V) --top pwm_formal -DFORMAL -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl \
		$(COMMON_REGISTER) rtl/pwm_deadtime.sv formal/pwm_formal.sv \
		--write=$(BUILD_DIR)/formal-src/pwm_formal.v
	$(SBY) -f -d $(BUILD_DIR)/formal formal/pwm.sby

clean:
	rm -rf $(BUILD_DIR)