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
module dcache_sram #(
    parameter integer NUM_LINES = 256,
    parameter integer LINE_BYTES = 4,
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter ASIC = 0
) (
    input  wire                                                       clk,
    input  wire                                                       resetn,
    input  wire                                                       flush,
    input  wire [                              $clog2(NUM_LINES)-1:0] idx,
    input  wire [ADDR_WIDTH-$clog2(NUM_LINES)-$clog2(LINE_BYTES)-1:0] tag,
    input  wire                                                       we,
    input  wire                                                       re,
    input  wire [                                     DATA_WIDTH-1:0] wdata,
    output reg  [                                     DATA_WIDTH-1:0] rdata,
    output reg                                                        hit
);
  localparam integer OFFSET_BITS = $clog2(LINE_BYTES);
  localparam integer IDX_BITS = $clog2(NUM_LINES);
  localparam integer TAG_BITS = ADDR_WIDTH - OFFSET_BITS - IDX_BITS;
  localparam integer SUM_BITS = TAG_BITS + DATA_WIDTH;
  localparam integer PACK_BYTES = (SUM_BITS + 7) / 8;
  localparam integer PACK_BITS = 8 * PACK_BYTES;
  localparam integer PAD_BITS = PACK_BITS - SUM_BITS;
  initial begin
    if (NUM_LINES != 256 && NUM_LINES != 64) $fatal(1, "cache_sram_D$: NUM_LINES (%0d) must be 64 or 256.", NUM_LINES);
    if ((LINE_BYTES * 8) != DATA_WIDTH)
      $fatal(
          1,
          "cache_sram_D$: LINE_BYTES*8 (%0d) must equal DATA_WIDTH (%0d).",
          LINE_BYTES * 8,
          DATA_WIDTH
      );
  end
  reg  [NUM_LINES-1:0] valid_ff;
  wire [PACK_BITS-1:0] packed_out;
  generate
    if (NUM_LINES == 64) begin : gen_sram64
      sram_sp_64x56 #(
          .ASIC(ASIC)
      ) u_mem (
          .clk (clk),
          .we  (we),
          .re  (re),
          .addr(idx),
          .din ({{PAD_BITS{1'b0}}, tag, wdata}),
          .dout(packed_out)
      );
    end else begin : gen_sram256
      sram_sp_256x56 #(
          .ASIC(ASIC)
      ) u_mem (
          .clk (clk),
          .we  (we),
          .re  (re),
          .addr(idx),
          .din ({{PAD_BITS{1'b0}}, tag, wdata}),
          .dout(packed_out)
      );
    end
  endgenerate
  localparam DATA_LO = 0;
  localparam DATA_HI = DATA_LO + DATA_WIDTH - 1;
  localparam TAG_LO = DATA_HI + 1;
  localparam TAG_HI = TAG_LO + TAG_BITS - 1;
  always @* begin
    rdata = packed_out[DATA_HI:DATA_LO];
    hit   = valid_ff[idx] && (packed_out[TAG_HI:TAG_LO] == tag);
  end
  always @(posedge clk) begin
    if (!resetn) begin
      valid_ff <= {NUM_LINES{1'b0}};
    end else if (flush) begin
      valid_ff <= {NUM_LINES{1'b0}};
    end else if (we) begin
      valid_ff[idx] <= 1'b1;
    end
  end
endmodule
`default_nettype wire
/* verilator lint_on UNUSEDSIGNAL */
