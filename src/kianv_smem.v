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
/* verilator lint_off UNUSEDSIGNAL */
module kianv_smem #(
    parameter integer CHIP_SELECTS = 2,
    parameter         ASIC         = 0
) (
    input  wire [            22:0] addr,
    output reg  [            31:0] rdata,
    input  wire [            31:0] wdata,
    input  wire [             3:0] wstrb,
    output reg                     ready,
    input  wire                    valid,
    input  wire                    clk,
    input  wire                    resetn,
    input  wire                    PSRAM_SPIFLASH,
    input  wire                    QUAD_MODE,
    input  wire                    HALF_CLOCK,
    output wire                    sclk,
    input  wire                    sio0_si_mosi_i,
    input  wire                    sio1_so_miso_i,
    input  wire                    sio2_i,
    input  wire                    sio3_i,
    output wire                    sio0_si_mosi_o,
    output wire                    sio1_so_miso_o,
    output wire                    sio2_o,
    output wire                    sio3_o,
    output reg  [             3:0] sio_oe,
    input  wire [CHIP_SELECTS-1:0] ce_ctrl,
    output reg  [CHIP_SELECTS-1:0] ce,
    output reg                     ss_n
);
  localparam [7:0] CMD_QUAD_WRITE = 8'h38;
  localparam [7:0] CMD_FAST_READ_QUAD = 8'hEB;
  localparam [7:0] CMD_WRITE = 8'h02;
  localparam [7:0] CMD_READ = 8'h03;
  localparam [2:0] S0_IDLE = 3'd0;
  localparam [2:0] S1_LATCH = 3'd1;
  localparam [2:0] S2_SELECT_EN = 3'd2;
  localparam [2:0] S3_CMD = 3'd3;
  localparam [2:0] S4_ADDR = 3'd4;
  localparam [2:0] S5_WAIT = 3'd5;
  localparam [2:0] S6_XFER = 3'd6;
  localparam [2:0] S7_DONE = 3'd7;
  reg  [             2:0] state;
  reg  [            31:0] spi_buf;
  reg  [             5:0] xfer_cycles;
  reg                     is_quad;
  reg                     valid_d;
  wire                    start_pulse = valid & ~valid_d;
  reg  [            22:0] addr_lat;
  reg  [CHIP_SELECTS-1:0] ce_lat;
  reg                     half_lat;
  wire                    write = |wstrb;
  wire                    read = ~write;
  wire [             3:0] sio_in = {sio3_i, sio2_i, sio1_so_miso_i, sio0_si_mosi_i};
  assign {sio3_o, sio2_o, sio1_so_miso_o, sio0_si_mosi_o} =
         is_quad ? spi_buf[31:28] : {3'b0, spi_buf[31]};
  wire [ 1:0] byte_offset;
  wire [ 5:0] wr_cycles;
  wire [31:0] wr_buffer;
  align_wdata align_wdata_i (
      .wstrb      (wstrb),
      .wdata      (wdata),
      .byte_offset(byte_offset),
      .wr_cycles  (wr_cycles),
      .wr_buffer  (wr_buffer)
  );
  reg        sclk_en;
  reg        sclk_div2;
  (* keep *)wire       sclk_fast;
  reg  [3:0] sio_sampled_full_rise;
  reg  [3:0] sio_sampled_half;
  wire [3:0] sio_shift_in = (half_lat != 0) ? sio_sampled_half : sio_sampled_full_rise;
  wire       xfer_step = (half_lat != 0) ? sclk_div2 : 1'b1;
  wire [5:0] step_bits = is_quad ? 6'd4 : 6'd1;

  generate
    if (ASIC == 1) begin : gen_ihp_sg13
      (* keep, dont_touch = "true" *) wire clk_inv;
      (* keep, dont_touch = "true" *)
      sg13g2_inv_1 u_clk_inv (
          .A(clk),
          .Y(clk_inv)
      );
      (* keep, dont_touch = "true" *)
      sg13g2_lgcp_1 u_sclk_cg (
          .CLK (clk_inv),
          .GATE(sclk_en),
          .GCLK(sclk_fast)
      );

      always @(posedge clk) begin
        if (!resetn) sio_sampled_full_rise <= 4'b0000;
        else if (sclk_en) sio_sampled_full_rise <= sio_in;
      end
    end else begin : gen_generic_fpga
      assign sclk_fast = (~clk) & sclk_en;

      always @(posedge clk) begin
        if (!resetn) sio_sampled_full_rise <= 4'b0000;
        else if (sclk_en) sio_sampled_full_rise <= sio_in;
      end
    end
  endgenerate

  assign sclk = (half_lat != 0) ? sclk_div2 : sclk_fast;

  always @(posedge clk) begin
    if (!resetn) begin
      valid_d          <= 1'b0;
      addr_lat         <= 23'd0;
      ce_lat           <= {CHIP_SELECTS{1'b0}};
      half_lat         <= 1'b0;
      ce               <= {CHIP_SELECTS{1'b0}};
      ss_n             <= 1'b1;
      sio_oe           <= 4'b0000;
      spi_buf          <= 32'd0;
      is_quad          <= 1'b0;
      xfer_cycles      <= 6'd0;
      sclk_en          <= 1'b0;
      sclk_div2        <= 1'b0;
      sio_sampled_half <= 4'b0000;
      ready            <= 1'b0;
      rdata            <= 32'd0;
      state            <= S0_IDLE;
    end else begin
      valid_d <= valid;
      ready   <= 1'b0;

      if (start_pulse) begin
        addr_lat <= addr;
        ce_lat   <= ce_ctrl;
        half_lat <= HALF_CLOCK;
      end

      if (half_lat) begin
        if (!sclk_en) begin
          sclk_div2 <= 1'b0;
        end else begin
          if (sclk_div2 == 1'b0) sio_sampled_half <= sio_in;
          sclk_div2 <= ~sclk_div2;
        end
      end else begin
        sclk_div2 <= 1'b0;
      end

      if (|xfer_cycles) begin
        if (xfer_step) begin
          if (is_quad) spi_buf <= {spi_buf[27:0], sio_shift_in[3:0]};
          else spi_buf <= {spi_buf[30:0], sio_shift_in[1]};
          xfer_cycles <= xfer_cycles - step_bits;
          if (xfer_cycles == step_bits) sclk_en <= 1'b0;
        end
      end else begin
        case (state)
          S0_IDLE: begin
            ss_n    <= 1'b1;
            sio_oe  <= 4'b0001;
            is_quad <= 1'b0;
            sclk_en <= 1'b0;
            if (start_pulse) state <= S1_LATCH;
          end

          S1_LATCH: begin
            ss_n  <= 1'b1;
            ce    <= ce_lat;
            state <= S2_SELECT_EN;
          end

          S2_SELECT_EN: begin
            ce    <= ce_lat;
            ss_n  <= 1'b0;
            state <= S3_CMD;
          end

          S3_CMD: begin
            is_quad <= 1'b0;
            spi_buf[31:24] <= QUAD_MODE
                              ? (write ? CMD_QUAD_WRITE : CMD_FAST_READ_QUAD)
                              : (write ? CMD_WRITE      : CMD_READ);
            xfer_cycles <= 6'd8;
            sclk_en <= 1'b1;
            state <= S4_ADDR;
          end

          S4_ADDR: begin
            if (PSRAM_SPIFLASH)
              spi_buf[31:8] <= {1'b0, addr_lat[20:0], write ? byte_offset : 2'b00};
            else spi_buf[31:8] <= {addr_lat[21:0], write ? byte_offset : 2'b00};
            sio_oe      <= QUAD_MODE ? 4'b1111 : 4'b0001;
            xfer_cycles <= 6'd24;
            sclk_en     <= 1'b1;
            is_quad     <= QUAD_MODE;
            state       <= (QUAD_MODE && read) ? S5_WAIT : S6_XFER;
          end

          S5_WAIT: begin

            sio_oe      <= 4'b0000;
            is_quad     <= 1'b0;
            xfer_cycles <= 6'd6;
            sclk_en     <= 1'b1;
            state       <= S6_XFER;
          end

          S6_XFER: begin
            is_quad <= QUAD_MODE;
            if (write) begin

              sio_oe      <= QUAD_MODE ? 4'b1111 : 4'b0001;
              spi_buf     <= wr_buffer;
              xfer_cycles <= wr_cycles;
            end else begin
              sio_oe <= QUAD_MODE ? 4'b0000 : 4'b0001;

              xfer_cycles <= half_lat ? 6'd32 : (QUAD_MODE ? 6'd36 : 6'd33);
            end
            sclk_en <= 1'b1;
            state   <= S7_DONE;
          end

          S7_DONE: begin
            rdata <= PSRAM_SPIFLASH
                     ? spi_buf
                     : {spi_buf[7:0], spi_buf[15:8], spi_buf[23:16], spi_buf[31:24]};
            ready <= 1'b1;
            ss_n <= 1'b1;
            sclk_en <= 1'b0;
            state <= S0_IDLE;
          end

          default: begin
            sclk_en <= 1'b0;
            state   <= S0_IDLE;
          end
        endcase
      end
    end
  end
endmodule

module align_wdata (
    input  wire [ 3:0] wstrb,
    input  wire [31:0] wdata,
    output reg  [ 1:0] byte_offset,
    output reg  [ 5:0] wr_cycles,
    output reg  [31:0] wr_buffer
);
  always @(*) begin
    wr_buffer = wdata;
    case (wstrb)
      4'b0001: begin
        byte_offset      = 2'd3;
        wr_buffer[31:24] = wdata[7:0];
        wr_cycles        = 6'd8;
      end
      4'b0010: begin
        byte_offset      = 2'd2;
        wr_buffer[31:24] = wdata[15:8];
        wr_cycles        = 6'd8;
      end
      4'b0100: begin
        byte_offset      = 2'd1;
        wr_buffer[31:24] = wdata[23:16];
        wr_cycles        = 6'd8;
      end
      4'b1000: begin
        byte_offset      = 2'd0;
        wr_buffer[31:24] = wdata[31:24];
        wr_cycles        = 6'd8;
      end
      4'b0011: begin
        byte_offset      = 2'd2;
        wr_buffer[31:16] = wdata[15:0];
        wr_cycles        = 6'd16;
      end
      4'b1100: begin
        byte_offset      = 2'd0;
        wr_buffer[31:16] = wdata[31:16];
        wr_cycles        = 6'd16;
      end
      4'b1111: begin
        byte_offset = 2'd0;
        wr_buffer   = wdata;
        wr_cycles   = 6'd32;
      end
      default: begin
        byte_offset = 2'd0;
        wr_buffer   = wdata;
        wr_cycles   = 6'd32;
      end
    endcase
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
`default_nettype wire
