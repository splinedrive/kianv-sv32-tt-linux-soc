// SPDX-License-Identifier: Apache-2.0
/*
 * KianV RISC-V Linux/XV6 SoC
 * RISC-V SoC/ASIC Design
 *
 * Copyright (c) 2025 Hirosh Dabui <hirosh@dabui.de>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

`ifndef KIANV_SOC
`define KIANV_SOC
`ifndef SYSTEM_CLK
`define SYSTEM_CLK 30_000_000
`endif

`ifndef ASIC
`define ASIC 1'b1
`endif

`define NUM_ENTRIES_ITLB 8
`define NUM_ENTRIES_DTLB 8

// `define ENABLE_M_EXT 1


// ============================================================================
// Feature toggles / global controls
// ============================================================================
`define KIANV_SPI_CTRL0_FREQ 35_000_000 // sdcard
`define ENABLE_ACCESS_FAULT (1'b1)


// ============================================================================
// CACHE parameters
// ============================================================================

`ifndef BYPASS_CACHES
`define BYPASS_CACHES 1'b0
`endif

`ifndef CACHE_NUM_SETS
`define CACHE_NUM_SETS 256
`endif

// ============================================================================
// System control values
// ============================================================================
`define REBOOT_ADDR 32'h 11_100_000
`define REBOOT_DATA 16'h 7777
`define HALT_DATA   16'h 5555

// Divider / CPU info registers
`define DIV_ADDR0              32'h 10_000_00C
`define DIV_ADDR1              32'h 10_000_010
`define CPU_FREQ_REG_ADDR      32'h 10_000_014
`define CPU_MEMSIZE_REG_ADDR   32'h10_000_018

// ============================================================================
// GPIO
// ============================================================================
`define KIANV_GPIO_DIR    32'h10_000_700
`define KIANV_GPIO_OUTPUT 32'h10_000_704
`define KIANV_GPIO_INPUT  32'h10_000_708

// ============================================================================
// UARTs
// ============================================================================
`define UART_TX_ADDR0 32'h10_000_000
`define UART_RX_ADDR0 32'h10_000_000
`define UART_LSR_ADDR0 32'h10_000_005

`define UART_TX_ADDR1 32'h10_000_100
`define UART_RX_ADDR1 32'h10_000_100
`define UART_LSR_ADDR1 32'h10_000_105

`define UART_TX_ADDR2 32'h10_000_200
`define UART_RX_ADDR2 32'h10_000_200
`define UART_LSR_ADDR2 32'h10_000_205

`define UART_TX_ADDR3 32'h10_000_300
`define UART_RX_ADDR3 32'h10_000_300
`define UART_LSR_ADDR3 32'h10_000_305

`define UART_TX_ADDR4 32'h10_000_400
`define UART_RX_ADDR4 32'h10_000_400
`define UART_LSR_ADDR4 32'h10_000_405

// ============================================================================
// SPI
// ============================================================================
  // sd card
`define KIANV_SPI_CTRL0 32'h10_500_000
`define KIANV_SPI_DATA0 32'h10_500_004

// ============================================================================
// QSPI
// ============================================================================
`define KIANV_KIANV_SMEM_CTRL 32'h10_600_000


// ============================================================================
// Memory map
// ============================================================================
`define SDRAM_MEM_ADDR_START 32'h80_000_000
`define SDRAM_SIZE (1024*1024*32)
`define SDRAM_MEM_ADDR_END ((`SDRAM_MEM_ADDR_START) + (`SDRAM_SIZE))

`define SPI_NOR_MEM_ADDR_START 32'h20_000_000
`define SPI_MEMORY_OFFSET      (1024*1024*0)
`define SPI_NOR_MEM_ADDR_END   ((`SPI_NOR_MEM_ADDR_START) + (16*1024*1024))

`define KVSMEM_MEM_ADDR_START `SDRAM_MEM_ADDR_START
`define KVSMEM_MEM_ADDR_END `SDRAM_MEM_ADDR_END

`define RESET_ADDR               (`SPI_NOR_MEM_ADDR_START + `SPI_MEMORY_OFFSET)

`endif  // KIANV_SOC

