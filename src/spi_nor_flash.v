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

/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDSIGNAL */
`default_nettype none
module spi_nor_flash #(

    parameter integer SCLK_DIV      = 30,
    parameter         LITTLE_ENDIAN = 1
) (
    input wire clk,
    input wire resetn,

    input  wire [21:0] addr,
    output wire [31:0] data,
    output wire        ready,
    input  wire        valid,

    output reg  spi_cs,
    input  wire spi_miso,
    output wire spi_mosi,
    output reg  spi_sclk
);

  function integer clog2_int;
    input integer v;
    integer i;
    begin
      if (v <= 1) begin
        clog2_int = 1;
      end else begin
        v = v - 1;
        i = 0;
        while (v > 0) begin
          v = v >> 1;
          i = i + 1;
        end
        if (i < 1) i = 1;
        clog2_int = i;
      end
    end
  endfunction

  localparam integer CNT_W = clog2_int(SCLK_DIV);

  reg [CNT_W-1:0] divcnt;
  wire tick = (SCLK_DIV <= 1) ? 1'b1 : (divcnt == {CNT_W{1'b0}});

  localparam [2:0] ST_IDLE = 3'd0, ST_CMD = 3'd1, ST_RD = 3'd2, ST_DONE = 3'd3;
  reg [2:0] state;

  wire active = (state == ST_CMD) || (state == ST_RD);

  wire sclk_rise = active && tick && (spi_sclk == 1'b0);
  wire sclk_fall = active && tick && (spi_sclk == 1'b1);

  wire [31:0] cmd_init = {8'h03, addr, 2'b00};

  reg [31:0] cmd_sr;
  reg [5:0] cmd_cnt;

  reg [7:0] rx_sr;
  reg [2:0] bit_cnt;
  reg [1:0] byte_idx;
  reg [31:0] rcv_buff;

  reg done;
  reg mosi_bit;

  reg valid_d;
  wire start_pulse = valid & ~valid_d;

  assign data     = rcv_buff;
  assign ready    = done;
  assign spi_mosi = mosi_bit;

  always @(posedge clk) begin
    if (!resetn) begin
      state    <= ST_IDLE;
      spi_cs   <= 1'b1;
      spi_sclk <= 1'b0;

      divcnt   <= (SCLK_DIV <= 1) ? {CNT_W{1'b0}} : (SCLK_DIV - 1);

      cmd_sr   <= 32'h0;
      cmd_cnt  <= 6'd0;

      rx_sr    <= 8'h00;
      bit_cnt  <= 3'd0;
      byte_idx <= 2'd0;

      rcv_buff <= 32'h0;
      done     <= 1'b0;
      mosi_bit <= 1'b0;

      valid_d  <= 1'b0;
    end else begin
      valid_d <= valid;
      done    <= 1'b0;

      if (!active) begin
        spi_sclk <= 1'b0;
        divcnt   <= (SCLK_DIV <= 1) ? {CNT_W{1'b0}} : (SCLK_DIV - 1);
      end else begin
        if (SCLK_DIV <= 1) begin
          spi_sclk <= ~spi_sclk;
          divcnt   <= {CNT_W{1'b0}};
        end else begin
          if (tick) begin
            spi_sclk <= ~spi_sclk;
            divcnt   <= (SCLK_DIV - 1);
          end else begin
            divcnt <= divcnt - {{(CNT_W - 1) {1'b0}}, 1'b1};
          end
        end
      end

      case (state)
        ST_IDLE: begin
          spi_cs   <= 1'b1;
          mosi_bit <= 1'b0;

          if (start_pulse) begin
            spi_cs   <= 1'b0;
            cmd_sr   <= cmd_init;
            cmd_cnt  <= 6'd31;
            mosi_bit <= cmd_init[31];
            state    <= ST_CMD;
          end
        end

        ST_CMD: begin

          if (sclk_fall) begin
            mosi_bit <= cmd_sr[31];
          end

          if (sclk_rise) begin
            cmd_sr <= {cmd_sr[30:0], 1'b0};

            if (cmd_cnt == 0) begin
              rx_sr    <= 8'h00;
              bit_cnt  <= 3'd7;
              byte_idx <= 2'd0;
              state    <= ST_RD;
            end else begin
              cmd_cnt <= cmd_cnt - 6'd1;
            end
          end
        end

        ST_RD: begin

          if (sclk_rise) begin
            rx_sr <= {rx_sr[6:0], spi_miso};

            if (bit_cnt == 0) begin
              if (LITTLE_ENDIAN) begin
                case (byte_idx)
                  2'd0: rcv_buff[7:0] <= {rx_sr[6:0], spi_miso};
                  2'd1: rcv_buff[15:8] <= {rx_sr[6:0], spi_miso};
                  2'd2: rcv_buff[23:16] <= {rx_sr[6:0], spi_miso};
                  2'd3: rcv_buff[31:24] <= {rx_sr[6:0], spi_miso};
                endcase
              end else begin
                case (byte_idx)
                  2'd0: rcv_buff[31:24] <= {rx_sr[6:0], spi_miso};
                  2'd1: rcv_buff[23:16] <= {rx_sr[6:0], spi_miso};
                  2'd2: rcv_buff[15:8] <= {rx_sr[6:0], spi_miso};
                  2'd3: rcv_buff[7:0] <= {rx_sr[6:0], spi_miso};
                endcase
              end

              if (byte_idx == 2'd3) begin
                state <= ST_DONE;
              end else begin
                byte_idx <= byte_idx + 2'd1;
                bit_cnt  <= 3'd7;
              end
            end else begin
              bit_cnt <= bit_cnt - 3'd1;
            end
          end
        end

        ST_DONE: begin
          spi_cs   <= 1'b1;
          mosi_bit <= 1'b0;
          done     <= 1'b1;
          state    <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on UNUSEDSIGNAL */
`default_nettype wire
