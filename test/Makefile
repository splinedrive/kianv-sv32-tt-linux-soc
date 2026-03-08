# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = \
	RM_IHPSG13_1P_256x64_c2_bm_bist.v \
	RM_IHPSG13_1P_64x64_c2_bm_bist.v \
  RM_IHPSG13_1P_core_behavioral_bm_bist.v \
	cache.v \
	clint.v \
	dcache.v \
	dcache_sram.v \
	fifo.v \
	gpio.v \
	icache.v \
	icache_sram.v \
	kianv_smem.v \
	rx_uart.v \
	sg13g2_stdcell.v \
	soc.v \
	spi.v \
	spi_nor_flash.v \
	sram_sp_256x56.v \
	sram_sp_64x56.v \
	tt_um_kianv_sv32_soc.v \
	tx_uart.v \
	kianv-sv32-tt/alu.v \
	kianv-sv32-tt/alu_decoder.v \
	kianv-sv32-tt/associative_cache.v \
	kianv-sv32-tt/control_unit.v \
	kianv-sv32-tt/csr_decoder.v \
	kianv-sv32-tt/csr_exception_handler.v \
	kianv-sv32-tt/csr_unit.v \
	kianv-sv32-tt/datapath_unit.v \
	kianv-sv32-tt/design_elements.v \
	kianv-sv32-tt/divider.v \
	kianv-sv32-tt/divider_decoder.v \
	kianv-sv32-tt/extend.v \
	kianv-sv32-tt/interrupt_controller.v \
	kianv-sv32-tt/kianv_harris_mc_edition.v \
	kianv-sv32-tt/load_alignment.v \
	kianv-sv32-tt/load_decoder.v \
	kianv-sv32-tt/main_fsm.v \
	kianv-sv32-tt/multiplier.v \
	kianv-sv32-tt/multiplier_decoder.v \
	kianv-sv32-tt/multiplier_extension_decoder.v \
	kianv-sv32-tt/register_file.v \
	kianv-sv32-tt/store_alignment.v \
	kianv-sv32-tt/store_decoder.v \
	kianv-sv32-tt/sv32.v \
	kianv-sv32-tt/sv32_table_walk.v \
	kianv-sv32-tt/sv32_translate_data_to_physical.v \
	kianv-sv32-tt/sv32_translate_instruction_to_physical.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)
COMPILE_ARGS 		+= -I$(SRC_DIR)/kianv-sv32-tt
COMPILE_ARGS 		+= -DSIM
COMPILE_ARGS 		+= -DSYSTEM_CLK=10000000
COMPILE_ARGS 		+= -DASIC=1
COMPILE_ARGS 		+= -DFUNCTIONAL

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/spiflash.v
VERILOG_SOURCES += $(PWD)/psram.v
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
