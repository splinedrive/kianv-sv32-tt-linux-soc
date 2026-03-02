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
module spi #(
    parameter [3:0] CPOL_INIT = 4'b0000
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        ctrl,
    output wire [31:0] rdata,
    input  wire [31:0] wdata,
    input  wire [ 3:0] wstrb,
    input  wire [15:0] div,
    input  wire        valid,
    output reg         ready,
    output wire        busy,
    output wire [ 3:0] cen,
    output reg         sclk,
    output reg         mosi,
    input  wire        miso
);
  localparam S_IDLE = 1'b0, S_XFER = 1'b1;
  reg         state;
  reg  [ 5:0] xfer_cycles;
  reg  [ 7:0] shreg;
  reg  [31:0] rx_data;

  reg  [ 3:0] spi_cen;
  reg  [ 3:0] cpol;
  reg  [17:0] tick_cnt;
  wire        in_xfer = |xfer_cycles;
  wire [17:0] div_eff = (div == 16'd0) ? 18'd1 : {2'b0, div};
  wire        tick = (div_eff == 18'd1) || (tick_cnt == div_eff - 1'b1);
  wire        ctrl_access = valid && !ctrl;
  wire        data_write = valid && ctrl && wstrb[0];
  wire        data_read = valid && ctrl && !wstrb[0];
  wire        accept = ctrl_access || data_write || data_read;
  wire [ 3:0] cs_w = wdata[3:0];
  wire        cs_onehot_or_zero = (cs_w == 4'b0000) || ((cs_w & (cs_w - 1'b1)) == 4'b0000);
  reg  [ 1:0] active_cs;

  assign busy = in_xfer;

  always @(*) begin
    casez (~spi_cen)
      4'b???1: active_cs = 2'd0;
      4'b??10: active_cs = 2'd1;
      4'b?100: active_cs = 2'd2;
      4'b1000: active_cs = 2'd3;
      default: active_cs = 2'd0;
    endcase
  end
  wire active_cpol = cpol[active_cs];

  assign rdata = ctrl ? rx_data : {in_xfer, 23'b0, cpol, ~spi_cen};

  assign cen   = spi_cen;
  always @(posedge clk) begin
    if (!resetn) begin
      state       <= S_IDLE;
      xfer_cycles <= 6'd0;
      shreg       <= 8'h00;
      rx_data     <= 32'h0;
      spi_cen     <= 4'b1111;
      cpol        <= CPOL_INIT;
      sclk        <= CPOL_INIT[0];
      mosi        <= 1'b0;
      tick_cnt    <= 18'd0;
      ready       <= 1'b0;
    end else begin
      ready <= accept;
      if (ctrl_access && wstrb[0]) begin
        if (cs_onehot_or_zero) begin
          spi_cen <= ~cs_w;
          cpol    <= wdata[7:4];
        end
      end
      if (data_write) begin
        shreg       <= wdata[7:0];
        xfer_cycles <= 6'd8;
        state       <= S_XFER;
        sclk        <= active_cpol;
        mosi        <= wdata[7];
      end else begin

        case (state)
          S_IDLE: begin
            sclk <= active_cpol;
          end
          S_XFER: begin
            if (in_xfer && tick) begin
              sclk <= ~sclk;
              if (!sclk) begin
                shreg       <= {shreg[6:0], miso};
                xfer_cycles <= xfer_cycles - 1'b1;
              end else begin
                mosi <= shreg[7];
              end
            end
            if (!in_xfer) begin
              state   <= S_IDLE;
              mosi    <= 1'b0;
              sclk    <= active_cpol;
              rx_data <= {24'h0, shreg};
            end
          end
        endcase
      end
      if (!in_xfer) tick_cnt <= 18'd0;
      else if (tick) tick_cnt <= 18'd0;
      else tick_cnt <= tick_cnt + 18'd1;
    end
  end
endmodule
`default_nettype wire
