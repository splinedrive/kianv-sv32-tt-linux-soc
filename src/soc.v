// SPDX-License-Identifier: Apache-2.0
/*
 * KianV RISC-V Linux/XV6 SoC
 * RISC-V SoC/ASIC Design
 *
 * Copyright (c) 2026 Hirosh Dabui <hirosh@dabui.de>
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

`default_nettype none
`include "defines_soc.vh"

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off UNUSEDSIGNAL */
module soc #(
`ifdef SIM
    parameter integer SIM_MEM_LATENCY = 8
`endif
) (
    input  wire       clk_osc,
    input  wire       ext_resetn,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire       kvsmem_sclk,
    output wire       kvsmem_ss_n,
    output wire [1:0] kvsmem_csn,
    input  wire       kvsmem_sio0_i,
    input  wire       kvsmem_sio1_i,
    input  wire       kvsmem_sio2_i,
    input  wire       kvsmem_sio3_i,
    output wire       kvsmem_sio0_o,
    output wire       kvsmem_sio1_o,
    output wire       kvsmem_sio2_o,
    output wire       kvsmem_sio3_o,
    output wire [3:0] kvsmem_sio_oe,

    output wire spi_cen0,
    output wire spi_cen1,
    output wire spi_cen2,
    output wire spi_cen3,
    output wire spi_sclk0,
    input  wire spi_sio1_so_miso0,
    output wire spi_sio0_si_mosi0,

    input  wire [7:0] gpio_in,
    output wire gpio_out,
    output wire gpio_oe
);

  wire clk = clk_osc;

  localparam integer RST_CYCLES = 200;
  localparam integer RSTW = $clog2(RST_CYCLES);
  reg  [RSTW-1:0] rst_cnt;

  wire            rst_done = (rst_cnt == RST_CYCLES - 1);

  reg             is_reboot_valid_r;

  always @(posedge clk) begin
    if (!ext_resetn || is_reboot_valid_r) rst_cnt <= '0;
    else if (!rst_done) rst_cnt <= rst_cnt + 1'b1;
  end

  wire        resetn_soc = ext_resetn & (rst_cnt == RST_CYCLES - 1);

  wire        cpu_mem_ready;
  wire        cpu_mem_valid;
  wire [ 3:0] cpu_mem_wstrb;
  wire [33:0] cpu_mem_addr_phy;
  wire [31:0] cpu_mem_wdata;
  wire [31:0] cpu_mem_rdata;

  wire [31:0] cpu_mem_addr = cpu_mem_addr_phy[31:0];
  wire        wr = |cpu_mem_wstrb;
  wire        rd = ~wr;

  wire is_instruction, icache_flush;

  wire is_reboot_addr = (cpu_mem_addr == `REBOOT_ADDR);
  wire is_reboot_data = (cpu_mem_wdata[15:0] == `REBOOT_DATA);
  wire is_reboot = is_reboot_addr || is_reboot_data;
  wire is_reboot_valid = cpu_mem_valid && is_reboot_addr && is_reboot_data && wr;

  always @(posedge clk) begin
    if (!resetn_soc) is_reboot_valid_r <= 1'b0;
    else is_reboot_valid_r <= is_reboot_valid;
  end

  wire is_sdram = (cpu_mem_addr >= `SDRAM_MEM_ADDR_START && cpu_mem_addr < `SDRAM_MEM_ADDR_END);
  wire is_flash = (cpu_mem_addr >= `SPI_NOR_MEM_ADDR_START && cpu_mem_addr < `SPI_NOR_MEM_ADDR_END);
  wire hit_spi = (cpu_mem_addr == `KIANV_SPI_CTRL0) || (cpu_mem_addr == `KIANV_SPI_DATA0);
  wire hit_shared_spi = is_flash || hit_spi;

  wire hit_gpio = (cpu_mem_addr == `KIANV_GPIO_DIR   ||
                   cpu_mem_addr == `KIANV_GPIO_OUTPUT ||
                   cpu_mem_addr == `KIANV_GPIO_INPUT);

  wire [31:0] cache_addr_o;
  wire [31:0] cache_din_o;
  wire [3:0] cache_wmask_o;
  wire cache_valid_o;
  wire [31:0] cache_dout_i;
  wire cache_ready_i;

  reg mem_pend;
  reg [31:0] mem_addr_q;
  reg [31:0] mem_wdata_q;
  reg [3:0] mem_wstrb_q;
  reg mem_is_instr_q;

  wire mem_req_fire = cpu_mem_valid && is_sdram && !mem_pend;

  wire mem_sdram_ready;
  wire [31:0] mem_sdram_rdata;

  always @(posedge clk) begin
    if (!resetn_soc) begin
      mem_pend       <= 1'b0;
      mem_addr_q     <= 32'h0;
      mem_wdata_q    <= 32'h0;
      mem_wstrb_q    <= 4'h0;
      mem_is_instr_q <= 1'b0;
    end else begin
      if (mem_req_fire) begin
        mem_pend       <= 1'b1;
        mem_addr_q     <= cpu_mem_addr;
        mem_wdata_q    <= cpu_mem_wdata;
        mem_wstrb_q    <= cpu_mem_wstrb;
        mem_is_instr_q <= is_instruction;
      end else if (mem_pend && mem_sdram_ready) begin
        mem_pend <= 1'b0;
      end
    end
  end

  wire        mem_sdram_valid = mem_pend;
  wire        sdram_resp = mem_pend && mem_sdram_ready;

  wire        shared_spi_ready;
  wire [31:0] shared_spi_rdata;
  wire [ 3:0] shared_spi_cen;

  wire [31:0] div_reg_bus0, div_reg_bus1;
  wire div0_valid_seen, div1_valid_seen;

  spi_nor_spi_if #(
      .SPI_CTRL_ADDR(`KIANV_SPI_CTRL0),
      .SPI_DATA_ADDR(`KIANV_SPI_DATA0),
      .START_ADDR   (`SPI_NOR_MEM_ADDR_START),
      .END_ADDR     (`SPI_NOR_MEM_ADDR_END),
      .NOR_CS_IDX   (2),
`ifdef SIM
      .SCLK_DIV     (1),
`endif
      .CPOL_INIT    (4'b0000),
      .DIV_MAP      (4'b1110)
  ) spi_shared_I (
      .clk   (clk),
      .resetn(resetn_soc),

      .bus_valid_i(cpu_mem_valid),
      .bus_addr_i (cpu_mem_addr),
      .bus_wstrb_i(cpu_mem_wstrb),
      .bus_wdata_i(cpu_mem_wdata),
      .bus_rdata_o(shared_spi_rdata),
      .bus_ready_o(shared_spi_ready),

      .div0_i(div_reg_bus0[31:16]),
      .div1_i(div_reg_bus1[31:16]),

      .cen (shared_spi_cen),
      .sclk(spi_sclk0),
      .miso(spi_sio1_so_miso0),
      .mosi(spi_sio0_si_mosi0)
  );

  assign spi_cen0 = shared_spi_cen[0];
  assign spi_cen1 = shared_spi_cen[1];
  assign spi_cen2 = shared_spi_cen[2];
  assign spi_cen3 = shared_spi_cen[3];

  wire        gpio_ready;
  wire [31:0] gpio_rdata;

  gpio_if #(
      .DIR_ADDR(`KIANV_GPIO_DIR),
      .OUT_ADDR(`KIANV_GPIO_OUTPUT),
      .IN_ADDR (`KIANV_GPIO_INPUT)
  ) gpio_if_I (
      .clk        (clk),
      .resetn     (resetn_soc),
      .bus_valid_i(cpu_mem_valid),
      .bus_addr_i (cpu_mem_addr),
      .bus_wstrb_i(cpu_mem_wstrb),
      .bus_wdata_i(cpu_mem_wdata),
      .bus_rdata_o(gpio_rdata),
      .bus_ready_o(gpio_ready),
      .gpio_oe    (gpio_oe),
      .gpio_in    (gpio_in),
      .gpio_out   (gpio_out)
  );

  wire        div_ready;
  wire [31:0] div_rdata;

`ifdef SIM
  localparam SIM_DEF_EN = 1'b1;
`else
  localparam SIM_DEF_EN = 1'b0;
`endif

  div_if #(
      .DIV_ADDR0    (`DIV_ADDR0),
      .DIV_ADDR1    (`DIV_ADDR1),
      .SYSTEM_CLK_HZ(`SYSTEM_CLK),
      .SIM_DEFAULTS (SIM_DEF_EN)
  ) div_if_I (
      .clk         (clk),
      .resetn      (resetn_soc),
      .bus_valid_i (cpu_mem_valid),
      .bus_addr_i  (cpu_mem_addr),
      .bus_wstrb_i (cpu_mem_wstrb),
      .bus_wdata_i (cpu_mem_wdata),
      .bus_rdata_o (div_rdata),
      .bus_ready_o (div_ready),
      .div_reg0_o  (div_reg_bus0),
      .div_reg1_o  (div_reg_bus1),
      .div0_valid_o(div0_valid_seen),
      .div1_valid_o(div1_valid_seen),
      .div_reg_o   (),
      .div_valid_o ()
  );

  wire        kvsmem_ctrl_ready;
  wire [31:0] kvsmem_ctrl_rdata;
  wire        qqspi_half_clock_cfg;

  kvsmem_ctrl_if #(
      .CTRL_ADDR(`KIANV_KIANV_SMEM_CTRL)
  ) kvsmem_ctrl_if_I (
      .clk         (clk),
      .resetn      (resetn_soc),
      .bus_valid_i (cpu_mem_valid),
      .bus_addr_i  (cpu_mem_addr),
      .bus_wstrb_i (cpu_mem_wstrb),
      .bus_wdata_i (cpu_mem_wdata),
      .bus_rdata_o (kvsmem_ctrl_rdata),
      .bus_ready_o (kvsmem_ctrl_ready),
      .half_clock_o(qqspi_half_clock_cfg)
  );

  cache #(
      .ASIC         (`ASIC),
      .BYPASS_CACHES(`BYPASS_CACHES),
      .NUM_SETS     (`CACHE_NUM_SETS)
  ) cache_I (
      .clk           (clk),
      .resetn        (resetn_soc),
      .iflush        (icache_flush),
      .is_instruction(mem_is_instr_q),
      .cpu_addr_i    (mem_addr_q),
      .cpu_din_i     (mem_wdata_q),
      .cpu_wmask_i   (mem_wstrb_q),
      .cpu_valid_i   (mem_sdram_valid),
      .cpu_dout_o    (mem_sdram_rdata),
      .cpu_ready_o   (mem_sdram_ready),
      .cache_addr_o  (cache_addr_o),
      .cache_din_o   (cache_din_o),
      .cache_wmask_o (cache_wmask_o),
      .cache_valid_o (cache_valid_o),
      .cache_dout_i  (cache_dout_i),
      .cache_ready_i (cache_ready_i)
  );

  kvsmem_if #(
      .START_ADDR     (`SDRAM_MEM_ADDR_START),
      .END_ADDR       (`SDRAM_MEM_ADDR_END),
      .CHIP_SELECTS   (2),
      .ADDR_WORD_SHIFT(2),
      .ADDR_WORD_WIDTH(21)
  ) qqspi_psram_backend_I (
      .clk   (clk),
      .resetn(resetn_soc),

      .half_clock_i(qqspi_half_clock_cfg),
      .bus_valid_i (cache_valid_o),
      .bus_addr_i  (cache_addr_o),
      .bus_wstrb_i (cache_wmask_o),
      .bus_wdata_i (cache_din_o),
      .bus_rdata_o (cache_dout_i),
      .bus_ready_o (cache_ready_i),

      .sclk    (kvsmem_sclk),
      .sio0_i  (kvsmem_sio0_i),
      .sio1_i  (kvsmem_sio1_i),
      .sio2_i  (kvsmem_sio2_i),
      .sio3_i  (kvsmem_sio3_i),
      .sio0_o  (kvsmem_sio0_o),
      .sio1_o  (kvsmem_sio1_o),
      .sio2_o  (kvsmem_sio2_o),
      .sio3_o  (kvsmem_sio3_o),
      .sio_oe  (kvsmem_sio_oe),
      .csn     (kvsmem_csn),
      .spi_ss_n(kvsmem_ss_n)
  );

  wire        uart_if_ready;
  wire [31:0] uart_if_rdata;
  wire [31:0] uart_rx_data_obs;
  wire        uart_tx_busy_obs;

  uart_if #(
      .LSR_ADDR(`UART_LSR_ADDR0),
      .TX_ADDR (`UART_TX_ADDR0),
      .RX_ADDR (`UART_RX_ADDR0),
      .HAS_TEMT(1'b1),
      .HAS_THRE(1'b1)
  ) uart_if_I (
      .clk        (clk),
      .resetn     (resetn_soc),
      .bus_valid_i(cpu_mem_valid),
      .bus_addr_i (cpu_mem_addr),
      .bus_wstrb_i(cpu_mem_wstrb),
      .bus_wdata_i(cpu_mem_wdata),
      .bus_rdata_o(uart_if_rdata),
      .bus_ready_o(uart_if_ready),
      .div_i      (div_reg_bus0[15:0]),
      .uart_tx    (uart_tx),
      .uart_rx    (uart_rx),
      .rx_data_o  (uart_rx_data_obs),
      .tx_busy_o  (uart_tx_busy_obs),
      .tx_ready_o (),
      .lsr_ready_o()
  );

  wire        clint_ready;
  wire [31:0] clint_rdata;
  wire        clint_valid_vis;
  wire IRQ3, IRQ7;
  wire [63:0] timer_counter;
  wire [63:0] mtime_for_system;

  mtime_source mtime_src_I (
      .clk            (clk),
      .resetn         (resetn_soc),
      .timer_counter_i(timer_counter),
      .mtime_div_i    (div_reg_bus1[15:0]),
      .mtime_o        (mtime_for_system)
  );

  clint_if #(
      .BASE_HI(8'h02)
  ) clint_if_I (
      .clk            (clk),
      .resetn         (resetn_soc),
      .bus_valid_i    (cpu_mem_valid),
      .bus_addr_i     (cpu_mem_addr),
      .bus_wstrb_i    (cpu_mem_wstrb),
      .bus_wdata_i    (cpu_mem_wdata),
      .bus_rdata_o    (clint_rdata),
      .bus_ready_o    (clint_ready),
      .is_valid_o     (clint_valid_vis),
      .timer_counter_i(mtime_for_system),
      .IRQ3           (IRQ3),
      .IRQ7           (IRQ7)
  );

  wire        sys_ready;
  wire [31:0] sys_rdata;
  wire sys_cpu_freq_valid, sys_mem_size_valid;
  wire [15:0] sysclk_mhz_q8_8;

  sysinfo_if #(
      .CPU_FREQ_ADDR(`CPU_FREQ_REG_ADDR),
      .MEM_SIZE_ADDR(`CPU_MEMSIZE_REG_ADDR)
  ) sysinfo_if_I (
      .clk             (clk),
      .resetn          (resetn_soc),
      .sysclk_mhz_q8_8 (sysclk_mhz_q8_8),
      .bus_valid_i     (cpu_mem_valid),
      .bus_addr_i      (cpu_mem_addr),
      .bus_wstrb_i     (cpu_mem_wstrb),
      .bus_wdata_i     (cpu_mem_wdata),
      .bus_rdata_o     (sys_rdata),
      .bus_ready_o     (sys_ready),
      .cpu_freq_valid_o(sys_cpu_freq_valid),
      .mem_size_valid_o(sys_mem_size_valid)
  );

  wire match_lsr = (cpu_mem_addr == `UART_LSR_ADDR0);
  wire match_tx = (cpu_mem_addr == `UART_TX_ADDR0);
  wire match_rx = (cpu_mem_addr == `UART_RX_ADDR0);

  wire is_io = (cpu_mem_addr >= 32'h10_000_000 && cpu_mem_addr <= 32'h12_000_000) ||
               (cpu_mem_addr[31:24] == 8'h0C) || (cpu_mem_addr[31:24] == 8'h02);

  wire shared_spi_valid = cpu_mem_valid && hit_shared_spi;
  wire gpio_valid = cpu_mem_valid && hit_gpio;

  wire kvsmem_ctrl_valid = cpu_mem_valid && (cpu_mem_addr == `KIANV_KIANV_SMEM_CTRL);

  wire unmatched_io = !(match_lsr || match_tx || match_rx ||
                        clint_valid_vis                    ||
                        shared_spi_valid                   ||
                        div0_valid_seen || div1_valid_seen ||
                        gpio_valid                         ||
                        sys_cpu_freq_valid || sys_mem_size_valid ||
                        kvsmem_ctrl_valid);

  reg unmatched_io_ready;
  always @(posedge clk) begin
    if (!resetn_soc) unmatched_io_ready <= 1'b0;
    else unmatched_io_ready <= unmatched_io;
  end

  reg is_io_ready;
  always @(posedge clk) begin
    if (!resetn_soc) is_io_ready <= 1'b0;
    else is_io_ready <= is_io;
  end

  reg        io_ready;
  reg [31:0] io_rdata;
  always @(*) begin
    io_ready = 1'b0;
    io_rdata = 32'h0;

    if (is_io_ready) begin
      if (uart_if_ready) begin
        io_ready = 1'b1;
        io_rdata = uart_if_rdata;
      end else if (sys_ready) begin
        io_ready = 1'b1;
        io_rdata = sys_rdata;
      end else if (clint_ready) begin
        io_ready = 1'b1;
        io_rdata = clint_rdata;
      end else if (div_ready) begin
        io_ready = 1'b1;
        io_rdata = div_rdata;
      end else if (gpio_ready) begin
        io_ready = 1'b1;
        io_rdata = gpio_rdata;
      end else if (kvsmem_ctrl_ready) begin
        io_ready = 1'b1;
        io_rdata = kvsmem_ctrl_rdata;
      end else if (unmatched_io_ready) begin
        io_ready = 1'b1;
        io_rdata = 32'h0;
      end
    end
  end

  reg access_fault_ready;

  wire non_instruction_invalid_access =
      !is_instruction && !(is_io || is_sdram || hit_shared_spi || is_reboot);

  wire instruction_invalid_access = is_instruction && !(is_sdram || hit_shared_spi);

  wire hit_access_fault_valid = `ENABLE_ACCESS_FAULT &&
                                (cpu_mem_valid &&
                                 (non_instruction_invalid_access || instruction_invalid_access));

  always @(posedge clk) begin
    if (!resetn_soc) access_fault_ready <= 1'b0;
    else access_fault_ready <= hit_access_fault_valid;
  end

  (* keep_hierarchy *)
  kianv_harris_mc_edition #(
      .RESET_ADDR      (`RESET_ADDR),
      .NUM_ENTRIES_ITLB(`NUM_ENTRIES_ITLB),
      .NUM_ENTRIES_DTLB(`NUM_ENTRIES_DTLB)
  ) kianv_I (
      .clk            (clk),
      .resetn         (resetn_soc),
      .sysclk_mhz_q8_8(sysclk_mhz_q8_8),
      .mem_ready      (cpu_mem_ready),
      .mem_valid      (cpu_mem_valid),
      .mem_wstrb      (cpu_mem_wstrb),
      .mem_addr       (cpu_mem_addr_phy),
      .mem_wdata      (cpu_mem_wdata),
      .mem_rdata      (cpu_mem_rdata),
      .access_fault   (access_fault_ready),
      .timer_counter  (timer_counter),
      .is_instruction (is_instruction),
      .icache_flush   (icache_flush),
      .IRQ3           (IRQ3),
      .IRQ7           (IRQ7),
      .IRQ9           (1'b0),
      .IRQ11          (1'b0),
      .PC             ()
  );

  assign cpu_mem_ready =
      (sdram_resp)                              ||
      (hit_shared_spi && shared_spi_ready)      ||
      (hit_gpio && gpio_ready)                  ||
      (is_io    && io_ready)                    ||
      (hit_access_fault_valid && access_fault_ready);

  assign cpu_mem_rdata =
      (sdram_resp)                             ? mem_sdram_rdata  :
      (hit_shared_spi && shared_spi_ready)     ? shared_spi_rdata :
      (hit_gpio       && gpio_ready)           ? gpio_rdata       :
      (is_io          && io_ready)             ? io_rdata         :
      32'h0000_0000;

endmodule
`default_nettype wire

`default_nettype none
module kvsmem_if #(
    parameter         [31:0] START_ADDR      = 32'h8000_0000,
    parameter         [31:0] END_ADDR        = (START_ADDR + 32 * 1024 * 1024),
    parameter integer        CHIP_SELECTS    = 2,
    parameter integer        ADDR_WORD_SHIFT = 2,
    parameter integer        ADDR_WORD_WIDTH = 21
) (
    input wire clk,
    input wire resetn,

    input wire half_clock_i,

    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,

    output wire       sclk,
    input  wire       sio0_i,
    input  wire       sio1_i,
    input  wire       sio2_i,
    input  wire       sio3_i,
    output wire       sio0_o,
    output wire       sio1_o,
    output wire       sio2_o,
    output wire       sio3_o,
    output wire [3:0] sio_oe,

    output wire [CHIP_SELECTS-1:0] csn,
    output wire                    spi_ss_n
);

  wire        in_range = (bus_addr_i >= START_ADDR) && (bus_addr_i < END_ADDR);
  wire        hit = bus_valid_i && in_range;

  reg         pend;
  reg  [31:0] addr_q;
  reg  [31:0] wdata_q;
  reg  [ 3:0] wstrb_q;

  reg         resp_valid;
  reg  [31:0] resp_rdata;

  wire        req_fire = hit && !pend && !resp_valid;


  wire [31:0] mem_rdata;
  wire mem_ready;
  wire [CHIP_SELECTS-1:0] ce_from_core;

  wire [31:0] win_off = addr_q - START_ADDR;
  wire [1:0] region = win_off[24:23];

  wire [ADDR_WORD_WIDTH-1:0] word_addr =
      win_off[ADDR_WORD_SHIFT + ADDR_WORD_WIDTH - 1 : ADDR_WORD_SHIFT];

  wire [22:0] kvsmem = {{(23 - ADDR_WORD_WIDTH) {1'b0}}, word_addr};

  always @(posedge clk) begin
    if (!resetn) begin
      pend       <= 1'b0;
      addr_q     <= 32'h0;
      wdata_q    <= 32'h0;
      wstrb_q    <= 4'h0;
      resp_valid <= 1'b0;
      resp_rdata <= 32'h0;
    end else begin
      if (resp_valid) resp_valid <= 1'b0;

      if (req_fire) begin
        pend    <= 1'b1;
        addr_q  <= bus_addr_i;
        wdata_q <= bus_wdata_i;
        wstrb_q <= bus_wstrb_i;
      end

      if (pend && mem_ready) begin
        pend       <= 1'b0;
        resp_valid <= 1'b1;
        resp_rdata <= mem_rdata;
      end
    end
  end

  kianv_smem #(
      .CHIP_SELECTS(CHIP_SELECTS),
      .ASIC        (`ASIC)
  ) kv_smem_I (
      .addr (kvsmem),
      .rdata(mem_rdata),
      .wdata(wdata_q),
      .wstrb(wstrb_q),
      .ready(mem_ready),
      .valid(pend),

      .clk   (clk),
      .resetn(resetn),

      .PSRAM_SPIFLASH(1'b1),
      .QUAD_MODE     (1'b1),
      .HALF_CLOCK    (half_clock_i),

      .sclk(sclk),

      .sio0_si_mosi_i(sio0_i),
      .sio1_so_miso_i(sio1_i),
      .sio2_i        (sio2_i),
      .sio3_i        (sio3_i),

      .sio0_si_mosi_o(sio0_o),
      .sio1_so_miso_o(sio1_o),
      .sio2_o        (sio2_o),
      .sio3_o        (sio3_o),

      .sio_oe(sio_oe),

      .ce_ctrl(region),
      .ce     (ce_from_core),
      .ss_n   (spi_ss_n)
  );

  assign csn = ce_from_core;

  assign bus_ready_o = resp_valid;
  assign bus_rdata_o = resp_rdata;

endmodule
`default_nettype wire

`default_nettype none
module kvsmem_ctrl_if #(
    parameter [31:0] CTRL_ADDR = 32'h10_600_000
) (
    input wire clk,
    input wire resetn,

    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,

    output reg half_clock_o
);

  wire hit = bus_valid_i && (bus_addr_i == CTRL_ADDR);
  wire wr = |bus_wstrb_i;

  reg seen_q, ready_q;
  wire accept = hit && !seen_q;

  always @(posedge clk) begin
    if (!resetn) begin
      seen_q       <= 1'b0;
      ready_q      <= 1'b0;
      half_clock_o <= 1'b1;
    end else begin
      ready_q <= accept;

      if (!hit) seen_q <= 1'b0;
      else if (accept) seen_q <= 1'b1;

      if (accept && wr && bus_wstrb_i[0]) half_clock_o <= bus_wdata_i[0];
    end
  end

  assign bus_ready_o = ready_q;
  assign bus_rdata_o = {31'b0, half_clock_o};

endmodule
`default_nettype wire

module uart_if #(
    parameter [31:0] LSR_ADDR = 32'h1000_0005,
    parameter [31:0] TX_ADDR  = 32'h1000_0000,
    parameter [31:0] RX_ADDR  = 32'h1000_0004,
    parameter        HAS_TEMT = 1'b1,
    parameter        HAS_THRE = 1'b1
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,

    input wire [15:0] div_i,

    output wire uart_tx,
    input  wire uart_rx,

    output wire [31:0] rx_data_o,
    output wire        tx_busy_o,
    output wire        tx_ready_o,
    output wire        lsr_ready_o
);
  wire wr = |bus_wstrb_i;
  wire rd = ~wr;

  wire match_lsr = bus_valid_i && (bus_addr_i == LSR_ADDR) && rd;
  wire match_tx = bus_valid_i && (bus_addr_i == TX_ADDR) && wr;
  wire match_rx = bus_valid_i && (bus_addr_i == RX_ADDR) && rd;

  wire uart_tx_rdy;
  wire uart_tx_busy;
  reg  tx_seen;
  wire tx_accept = match_tx && !tx_seen && uart_tx_rdy;
  reg  uart_tx_ready;

  always @(posedge clk) begin
    if (!resetn) uart_tx_ready <= 1'b0;
    else uart_tx_ready <= tx_accept;
  end
  always @(posedge clk) begin
    if (!resetn) tx_seen <= 1'b0;
    else if (!match_tx) tx_seen <= 1'b0;
    else if (tx_accept) tx_seen <= 1'b1;
  end

  tx_uart tx_uart_i (
      .clk    (clk),
      .resetn (resetn),
      .valid  (tx_accept),
      .tx_data(bus_wdata_i[7:0]),
      .div    (div_i),
      .tx_out (uart_tx),
      .ready  (uart_tx_rdy),
      .busy   (uart_tx_busy)
  );
  assign tx_busy_o  = uart_tx_busy;
  assign tx_ready_o = uart_tx_rdy;

  reg         uart_rx_ready;
  wire [31:0] rx_uart_data;
  wire        uart_rx_valid_rd = (~uart_rx_ready) && match_rx;
  always @(posedge clk) begin
    if (!resetn) uart_rx_ready <= 1'b0;
    else uart_rx_ready <= uart_rx_valid_rd;
  end

  rx_uart rx_uart_i (
      .clk    (clk),
      .resetn (resetn),
      .rx_in  (uart_rx),
      .div    (div_i),
      .error  (),
      .data_rd(uart_rx_ready),
      .data   (rx_uart_data)
  );
  assign rx_data_o = rx_uart_data;

  reg lsr_thre;
  always @(posedge clk) begin
    if (!resetn) lsr_thre <= 1'b1;
    else if (tx_accept) lsr_thre <= 1'b0;
    else if (uart_tx_rdy) lsr_thre <= 1'b1;
  end

  wire       temt_bit = HAS_TEMT ? (~uart_tx_busy) : 1'b0;
  wire       thre_bit = HAS_THRE ? lsr_thre : 1'b0;
  wire [7:0] lsr = {1'b0, temt_bit, thre_bit, 1'b0, 3'b000, ~(&rx_uart_data)};

  reg        lsr_rdy_q;
  always @(posedge clk) begin
    if (!resetn) lsr_rdy_q <= 1'b0;
    else lsr_rdy_q <= (~lsr_rdy_q) && match_lsr;
  end
  assign lsr_ready_o = lsr_rdy_q;

  reg [31:0] rdata_r;
  reg        ready_r;
  always @(*) begin
    rdata_r = 32'h0;
    ready_r = 1'b0;

    if (lsr_rdy_q) begin
      rdata_r = {16'h0000, lsr, 8'h00};
      ready_r = 1'b1;
    end else if (uart_rx_ready) begin
      rdata_r = rx_uart_data;
      ready_r = 1'b1;
    end else if (uart_tx_ready) begin
      rdata_r = 32'h0000_0000;
      ready_r = 1'b1;
    end
  end

  assign bus_rdata_o = ready_r ? rdata_r : 32'h0;
  assign bus_ready_o = ready_r;
endmodule

module gpio_if #(
    parameter [31:0] DIR_ADDR = 32'h1100_0000,
    parameter [31:0] OUT_ADDR = 32'h1100_0004,
    parameter [31:0] IN_ADDR  = 32'h1100_0008
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,
    output wire        gpio_oe,
    input  wire  [7:0] gpio_in,
    output wire        gpio_out
);
  wire hit = bus_valid_i &&
            ((bus_addr_i == DIR_ADDR) || (bus_addr_i == OUT_ADDR) || (bus_addr_i == IN_ADDR));

  gpio gpio_I (
      .clk   (clk),
      .resetn(resetn),
      .addr  (bus_addr_i[3:0]),
      .wrstb (bus_wstrb_i),
      .wdata (bus_wdata_i),
      .rdata (bus_rdata_o),
      .valid (hit),
      .ready (bus_ready_o),
      .oe    (gpio_oe),
      .in    (gpio_in),
      .out   (gpio_out)
  );
endmodule

module clint_if #(
    parameter [7:0] BASE_HI = 8'h02
) (
    input wire clk,
    input wire resetn,

    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,
    output wire        is_valid_o,

    input wire [63:0] timer_counter_i,

    output wire IRQ3,
    output wire IRQ7
);

  wire is_clint = (bus_addr_i[31:24] == BASE_HI);

  clint clint_I (
      .clk          (clk),
      .resetn       (resetn),
      .valid        (is_clint && bus_valid_i),
      .addr         (bus_addr_i[23:0]),
      .wmask        (bus_wstrb_i),
      .wdata        (bus_wdata_i),
      .rdata        (bus_rdata_o),
      .is_valid     (is_valid_o),
      .ready        (bus_ready_o),
      .IRQ3         (IRQ3),
      .IRQ7         (IRQ7),
      .timer_counter(timer_counter_i)
  );
endmodule

module sysinfo_if #(

    parameter [31:0] CPU_FREQ_ADDR     = `CPU_FREQ_REG_ADDR,
    parameter [31:0] MEM_SIZE_ADDR     = `CPU_MEMSIZE_REG_ADDR,
    parameter        CPU_FREQ_WRITABLE = 1'b1
) (
    input wire clk,
    input wire resetn,

    output wire [15:0] sysclk_mhz_q8_8,

    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,

    output wire cpu_freq_valid_o,
    output wire mem_size_valid_o
);

  wire wr = |bus_wstrb_i;

  localparam [31:0] RESET_Q8_8_32 =
      ( ((`SYSTEM_CLK / 1_000_000) << 8)
      + ((((`SYSTEM_CLK % 1_000_000) * 256) + 500_000) / 1_000_000) );
  localparam [15:0] RESET_Q8_8 = (RESET_Q8_8_32 > 32'h0000_FFFF) ? 16'hFFFF : RESET_Q8_8_32[15:0];

  reg  [15:0] cpu_freq_reg;
  reg         cpu_freq_ready;

  wire        cpu_freq_hit = bus_valid_i && (bus_addr_i == CPU_FREQ_ADDR);
  wire        cpu_freq_valid = (!cpu_freq_ready) && cpu_freq_hit;

  always @(posedge clk) begin
    if (!resetn) begin
      cpu_freq_reg   <= RESET_Q8_8;
      cpu_freq_ready <= 1'b0;
    end else begin
      cpu_freq_ready <= cpu_freq_valid;
      if (CPU_FREQ_WRITABLE && cpu_freq_valid && wr) begin

        if (bus_wdata_i[15:0] < 16'h0100) cpu_freq_reg <= 16'h0100;
        else cpu_freq_reg <= bus_wdata_i[15:0];
      end
    end
  end

  reg  mem_size_ready;
  wire mem_size_hit = bus_valid_i && (bus_addr_i == MEM_SIZE_ADDR) && !wr;
  wire mem_size_valid = (!mem_size_ready) && mem_size_hit;

  always @(posedge clk) begin
    if (!resetn) mem_size_ready <= 1'b0;
    else mem_size_ready <= mem_size_valid;
  end

  assign bus_ready_o = cpu_freq_ready | mem_size_ready;

  assign bus_rdata_o = cpu_freq_ready ? {16'b0, cpu_freq_reg} :
                       mem_size_ready ? `SDRAM_SIZE :
                                        32'h0;

  assign sysclk_mhz_q8_8 = cpu_freq_reg;
  assign cpu_freq_valid_o = cpu_freq_valid;
  assign mem_size_valid_o = mem_size_valid;

endmodule

module div_if #(
    parameter [31:0] DIV_ADDR0 = 32'h1000_000C,
    parameter [31:0] DIV_ADDR1 = 32'h1000_0010,

    parameter integer SYSTEM_CLK_HZ    = 50_000_000,
    parameter         SIM_DEFAULTS     = 1'b0,
    parameter integer UART_BAUD_SIM    = 115_200,
    parameter integer SPI0_SCLK_HZ_SIM = 12_000_000,
    parameter integer SPI1_SCLK_HZ_SIM = 24_000_000,

    parameter integer CLINT_US_PER_TICK_SIM = 1
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,

    output reg  [31:0] div_reg0_o,
    output reg  [31:0] div_reg1_o,
    output wire        div0_valid_o,
    output wire        div1_valid_o,

    output wire [31:0] div_reg_o,
    output wire        div_valid_o
);
  wire wr = |bus_wstrb_i;

  function [15:0] div_from_hz16;
    input integer fclk_hz;
    input integer target_hz;
    integer d;
    begin
      if (target_hz <= 0) d = 1;
      else d = (fclk_hz + (target_hz / 2)) / target_hz;
      if (d < 1) d = 1;
      if (d > 65535) d = 65535;
      div_from_hz16 = d[15:0];
    end
  endfunction

  localparam [15:0] UART_DIV_SIM = div_from_hz16(SYSTEM_CLK_HZ, UART_BAUD_SIM);
  localparam [15:0] SPI0_DIV_SIM = div_from_hz16(SYSTEM_CLK_HZ, SPI0_SCLK_HZ_SIM);
  localparam [15:0] SPI1_DIV_SIM = div_from_hz16(SYSTEM_CLK_HZ, SPI1_SCLK_HZ_SIM);
  localparam [15:0] CLINT_DIV_SIM  =
      (CLINT_US_PER_TICK_SIM < 1)    ? 16'd1 :
      (CLINT_US_PER_TICK_SIM > 65535)? 16'hFFFF :
                                       CLINT_US_PER_TICK_SIM[15:0];

  localparam [31:0] DIV0_RESET_SIM = {SPI0_DIV_SIM, UART_DIV_SIM};
  localparam [31:0] DIV1_RESET_SIM = {SPI1_DIV_SIM, CLINT_DIV_SIM};

  reg div0_ready_q, div1_ready_q;

  wire div0_access = bus_valid_i && (bus_addr_i == DIV_ADDR0);
  wire div1_access = bus_valid_i && (bus_addr_i == DIV_ADDR1);

  wire div0_valid = (!div0_ready_q) && div0_access;
  wire div1_valid = (!div1_ready_q) && div1_access;

  always @(posedge clk) begin
    if (!resetn) begin
      div0_ready_q <= 1'b0;
      div1_ready_q <= 1'b0;
    end else begin
      div0_ready_q <= div0_valid;
      div1_ready_q <= div1_valid;
    end
  end

  always @(posedge clk) begin
    if (!resetn) begin
      if (SIM_DEFAULTS) begin
        div_reg0_o <= DIV0_RESET_SIM;
        div_reg1_o <= DIV1_RESET_SIM;
      end else begin
        div_reg0_o <= 32'd1;
        div_reg1_o <= 32'd1;
      end
    end else begin
      if (div0_valid && wr) div_reg0_o <= bus_wdata_i;
      if (div1_valid && wr) div_reg1_o <= bus_wdata_i;
    end
  end

  assign bus_ready_o = div0_ready_q | div1_ready_q;
  assign bus_rdata_o = div0_ready_q ? div_reg0_o : div1_ready_q ? div_reg1_o : 32'h0;

  assign div0_valid_o = div0_valid;
  assign div1_valid_o = div1_valid;

  assign div_reg_o = div_reg0_o;
  assign div_valid_o = div0_valid;
endmodule

module mtime_source (
    input  wire        clk,
    input  wire        resetn,
    input  wire [63:0] timer_counter_i,
    input  wire [15:0] mtime_div_i,
    output wire [63:0] mtime_o
);

  reg  [63:0] prev_mtime;
  wire        tick_1us = (timer_counter_i != prev_mtime);

  reg [15:0] presc, div_lat;
  reg  [63:0] mtime_div;

  wire [15:0] div_safe = (mtime_div_i == 16'd0) ? 16'd1 : mtime_div_i;

  always @(posedge clk) begin
    if (!resetn) begin
      prev_mtime <= 64'd0;
      presc      <= 16'd0;
      div_lat    <= 16'd1;
      mtime_div  <= 64'd0;
    end else if (tick_1us) begin
      prev_mtime <= timer_counter_i;

      if (div_lat == 16'd1) begin
        presc   <= 16'd0;
        div_lat <= div_safe;
      end else begin
        if (presc == div_lat - 16'd1) begin
          presc    <= 16'd0;
          mtime_div<= mtime_div + 64'd1;
          div_lat  <= div_safe;
        end else begin
          presc <= presc + 16'd1;
        end
      end
    end
  end

  assign mtime_o = (div_lat == 16'd1) ? timer_counter_i : mtime_div;

endmodule
`default_nettype wire
module spi_nor_spi_if #(
    parameter         [31:0] SPI_CTRL_ADDR   = 32'h10_500_000,
    parameter         [31:0] SPI_DATA_ADDR   = 32'h10_500_004,
    parameter         [31:0] START_ADDR      = 32'h20_000_000,
    parameter         [31:0] END_ADDR        = 32'h24_000_000,
    parameter integer        ADDR_WORD_SHIFT = 2,
    parameter integer        ADDR_WORD_WIDTH = 22,
    parameter integer        NOR_CS_IDX      = 2,
    parameter integer        SCLK_DIV        = 30,
    parameter         [ 3:0] CPOL_INIT       = 4'b0000,
    parameter         [ 3:0] DIV_MAP         = 4'b1110
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output wire [31:0] bus_rdata_o,
    output wire        bus_ready_o,
    input  wire [15:0] div0_i,
    input  wire [15:0] div1_i,
    output wire [ 3:0] cen,
    output wire        sclk,
    input  wire        miso,
    output wire        mosi
);

  wire in_nor_range = (bus_addr_i >= START_ADDR) && (bus_addr_i < END_ADDR);
  wire is_read = (bus_wstrb_i == 4'b0000);
  wire hit_nor = bus_valid_i && in_nor_range && is_read;
  wire hit_spi = bus_valid_i && ((bus_addr_i == SPI_CTRL_ADDR) || (bus_addr_i == SPI_DATA_ADDR));

  reg  mode_r;
  always @(posedge clk) begin
    if (!resetn) mode_r <= 1'b0;
    else if (hit_nor) mode_r <= 1'b0;
    else if (hit_spi) mode_r <= 1'b1;
  end
  wire        nor_sel = ~mode_r;

  wire [31:0] spi_rdata;
  wire        spi_ready_int;
  wire [ 3:0] spi_cen_int;
  wire        spi_sclk_int;
  wire        spi_mosi_int;

  reg  [ 1:0] act_cs;
  always @(*) begin
    casez (~spi_cen_int)
      4'b???1: act_cs = 2'd0;
      4'b??10: act_cs = 2'd1;
      4'b?100: act_cs = 2'd2;
      4'b1000: act_cs = 2'd3;
      default: act_cs = 2'd0;
    endcase
  end
  wire [15:0] active_div = DIV_MAP[act_cs] ? div1_i : div0_i;

  spi #(
      .CPOL_INIT(CPOL_INIT)
  ) spi_I (
      .clk   (clk),
      .resetn(resetn),
      .ctrl  (bus_addr_i[2]),
      .rdata (spi_rdata),
      .wdata (bus_wdata_i),
      .wstrb (bus_wstrb_i),
      .div   (active_div),
      .valid (hit_spi),
      .ready (spi_ready_int),
      .cen   (spi_cen_int),
      .sclk  (spi_sclk_int),
      .miso  (miso),
      .mosi  (spi_mosi_int),
      .busy  ()
  );

  wire [ADDR_WORD_WIDTH-1:0] nor_word_addr =
      bus_addr_i[ADDR_WORD_SHIFT + ADDR_WORD_WIDTH - 1 : ADDR_WORD_SHIFT];

  wire nor_done;
  wire nor_cs_n;
  wire nor_sclk;
  wire nor_mosi;
  wire [31:0] nor_rdata;

  spi_nor_flash #(
      .SCLK_DIV     (SCLK_DIV),
      .LITTLE_ENDIAN(1)
  ) u_flash (
      .clk     (clk),
      .resetn  (resetn),
      .addr    (nor_word_addr),
      .data    (nor_rdata),
      .ready   (nor_done),
      .valid   (hit_nor),
      .spi_cs  (nor_cs_n),
      .spi_sclk(nor_sclk),
      .spi_mosi(nor_mosi),
      .spi_miso(miso)
  );

  assign sclk = nor_sel ? nor_sclk : spi_sclk_int;
  assign mosi = nor_sel ? nor_mosi : spi_mosi_int;

  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : GEN_CEN
      if (i == NOR_CS_IDX) begin : GEN_NOR_CS
        assign cen[i] = nor_sel ? nor_cs_n : spi_cen_int[i];
      end else begin : GEN_SPI_CS
        assign cen[i] = spi_cen_int[i];
      end
    end
  endgenerate

  assign bus_ready_o = nor_done || (mode_r && spi_ready_int);
  assign bus_rdata_o = nor_done ? nor_rdata : (mode_r && spi_ready_int) ? spi_rdata : 32'h0;

endmodule

`default_nettype wire
/* verilator lint_on PINCONNECTEMPTY */
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on UNUSEDSIGNAL */
