.PHONY: compile test_% lab3 lab4

# Default lab if none provided
LAB ?= lab1

LAB_SRC_DIR := $(LAB)/src
BUILD_DIR   := build/$(LAB)

# Cocotb args for Icarus vvp
EXTRA_VVP_ARGS = -M $(shell cocotb-config --prefix)/cocotb/libs \
                 -m libcocotbvpi_icarus

# "make lab3 test_matmul" => re-run make with LAB=lab3 and remaining goals
lab1:
	@$(MAKE) LAB=$@ $(filter-out $@,$(MAKECMDGOALS))
lab3:
	@$(MAKE) LAB=$@ $(filter-out $@,$(MAKECMDGOALS))


# Ensure build directory exists
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ---- compile ----
compile: $(BUILD_DIR)
	$(MAKE) compile_alu
	sv2v -I $(LAB_SRC_DIR)/* -w $(BUILD_DIR)/gpu.v
	echo "" >> $(BUILD_DIR)/gpu.v
	cat $(BUILD_DIR)/alu.v >> $(BUILD_DIR)/gpu.v
	echo '`timescale 1ns/1ns' > $(BUILD_DIR)/temp.v
	cat $(BUILD_DIR)/gpu.v >> $(BUILD_DIR)/temp.v
	mv $(BUILD_DIR)/temp.v $(BUILD_DIR)/gpu.v

compile_%: $(BUILD_DIR)
	sv2v -w $(BUILD_DIR)/$*.v $(LAB_SRC_DIR)/$*.sv

# ---- tests ----
test_%: compile
	iverilog -o $(BUILD_DIR)/sim.vvp -s gpu -g2012 $(BUILD_DIR)/gpu.v
	MODULE=test.test_$* vvp $(EXTRA_VVP_ARGS) $(BUILD_DIR)/sim.vvp

# Swallow unknown targets so "lab3 test_matmul" doesn't error on leftovers
%:
	@:


# TODO: Get gtkwave visualizaiton

show_%: %.vcd %.gtkw
	gtkwave $^
