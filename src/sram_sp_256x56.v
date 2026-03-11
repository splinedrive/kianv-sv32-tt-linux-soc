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
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSEDSIGNAL */
module sram_sp_256x56 #(
    parameter ASIC = 0
) (
    input  wire        clk,
    input  wire        we,
    input  wire        re,
    input  wire [ 7:0] addr,
    input  wire [55:0] din,
    output wire [55:0] dout
);

  wire [55:0] dout_asic;
  wire [55:0] dout_fpga;

  assign dout = (ASIC != 0) ? dout_asic : dout_fpga;

  generate
    if (ASIC != 0) begin : gen_ihp_sg13
      wire        a_men = we | re;
      wire        a_wen = we;
      wire        a_ren = re & ~we;
      wire [ 7:0] a_addr = addr;
      wire [63:0] a_din = {8'h00, din};
      wire [63:0] a_bm = 64'h00FF_FFFF_FFFF_FFFF;
      wire [63:0] a_dout;

      RM_IHPSG13_1P_256x64_c2_bm_bist u_sram64 (
          .A_CLK      (clk),
          .A_MEN      (a_men),
          .A_WEN      (a_wen),
          .A_REN      (a_ren),
          .A_ADDR     (a_addr),
          .A_DIN      (a_din),
          .A_DLY      (1'b1),
          .A_DOUT     (a_dout),
          .A_BM       (a_bm),
          .A_BIST_CLK (1'b0),
          .A_BIST_EN  (1'b0),
          .A_BIST_MEN (1'b0),
          .A_BIST_WEN (1'b0),
          .A_BIST_REN (1'b0),
          .A_BIST_ADDR(8'b0),
          .A_BIST_DIN (64'b0),
          .A_BIST_BM  (64'b0)
      );

      assign dout_asic = a_dout[55:0];

    end else begin : gen_fpga
      (* ram_style = "block" *) reg [55:0] mem[0:255];
      reg [55:0] dout_r;

      assign dout_fpga = dout_r;

      always @(posedge clk) begin
        if (we) mem[addr] <= din;
        if (re & ~we) dout_r <= mem[addr];
      end
    end
  endgenerate

endmodule
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
`default_nettype wire
