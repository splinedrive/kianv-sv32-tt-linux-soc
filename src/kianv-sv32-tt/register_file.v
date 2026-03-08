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

module register_file #(
    parameter ASIC = 0
) (
    input  wire        clk,
    input  wire        we,
    input  wire [ 4:0] A1,
    input  wire [ 4:0] A2,
    input  wire [ 4:0] A3,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
  generate
    if (ASIC != 0) begin : g_asic
      wire [31:0] sram_a_dout;
      wire [31:0] sram_b_dout;

      RM_IHPSG13_2P_64x32_c2 u_sram_rd1 (
          .A_CLK (clk),
          .A_MEN (1'b1),
          .A_WEN (we && (A3 != 5'd0)),
          .A_REN (~we),
          .A_ADDR({1'b0, we ? A3 : A1}),
          .A_DIN (wd),
          .A_DLY (1'b1),
          .A_DOUT(sram_a_dout),

          .B_CLK (clk),
          .B_MEN (~we),
          .B_WEN (1'b0),
          .B_REN (~we),
          .B_ADDR({1'b0, A2}),
          .B_DIN (32'b0),
          .B_DLY (1'b1),
          .B_DOUT(sram_b_dout)
      );

      assign rd1 = (A1 != 5'd0) ? sram_a_dout : 32'b0;
      assign rd2 = (A2 != 5'd0) ? sram_b_dout : 32'b0;
    end else begin : g_gen
      reg [31:0] mem[0:31];
      reg [31:0] rd1_r;
      reg [31:0] rd2_r;
      integer i;

      initial begin
        for (i = 0; i < 32; i = i + 1) mem[i] = 32'b0;
        rd1_r = 32'b0;
        rd2_r = 32'b0;
      end

      always @(posedge clk) begin
        if (we) begin
          if (A3 != 5'd0) mem[A3] <= wd;
        end else begin
          rd1_r <= (A1 != 5'd0) ? mem[A1] : 32'b0;
          rd2_r <= (A2 != 5'd0) ? mem[A2] : 32'b0;
        end

        mem[0] <= 32'b0;
      end

      assign rd1 = rd1_r;
      assign rd2 = rd2_r;
    end
  endgenerate

endmodule
