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
module gpio (
    input  wire        clk,
    input  wire        resetn,
    input  wire [ 3:0] addr,
    input  wire [ 3:0] wrstb,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        valid,
    output reg         ready,

    input  wire [7:0] in,
    output wire [7:0] out,
    output wire [7:0] oe
);

  reg [7:0] out_en;
  reg [7:0] out_val;

  assign out = out_val;
  assign oe  = out_en;

  wire wr = |wrstb;

  always @(posedge clk) ready <= !resetn ? 1'b0 : valid;

  always @(posedge clk) begin
    if (!resetn) begin
      out_en  <= 8'b0;
      out_val <= 8'b0;
      rdata   <= 32'b0;
    end else if (valid) begin
      case (addr)
        4'h0: begin
          if (wr) out_en <= wdata[15:8];
          else rdata <= {16'b0, out_en, 8'b0};
        end

        4'h4: begin
          if (wr) out_val <= wdata[15:8];
          else rdata <= {16'b0, out_val, 8'b0};
        end

        4'h8: begin
          if (!wr) rdata <= {24'b0, in};
        end

        default: rdata <= 32'b0;
      endcase
    end
  end

endmodule
/* verilator lint_on UNUSEDSIGNAL */

