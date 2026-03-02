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

module associative_cache #(
    parameter         TAG_WIDTH     = 29,
    parameter         PAYLOAD_WIDTH = 32,
    parameter         ENTRIES       = 64,
    parameter integer PTE_G_BIT     = 5
) (
    input  wire                     clk,
    input  wire                     resetn,
    input  wire                     flush,
    input  wire [    TAG_WIDTH-1:0] tag,
    input  wire                     we,
    input  wire                     valid_i,
    output wire                     hit_o,
    input  wire [PAYLOAD_WIDTH-1:0] payload_i,
    output wire [PAYLOAD_WIDTH-1:0] payload_o
);
  localparam IDX_WIDTH = $clog2(ENTRIES);
  localparam VPN_WIDTH = 20;
  localparam ASID_WIDTH = TAG_WIDTH - VPN_WIDTH;

  wire [    VPN_WIDTH-1:0] vpn_i = tag[VPN_WIDTH-1:0];
  wire [   ASID_WIDTH-1:0] asid_i = tag[TAG_WIDTH-1:VPN_WIDTH];
  wire [    IDX_WIDTH-1:0] idx = vpn_i[IDX_WIDTH-1:0];

  reg                      val_ram                             [0:ENTRIES-1];
  reg  [    VPN_WIDTH-1:0] vpn_ram                             [0:ENTRIES-1];
  reg  [   ASID_WIDTH-1:0] asid_ram                            [0:ENTRIES-1];
  reg  [PAYLOAD_WIDTH-1:0] pte_ram                             [0:ENTRIES-1];
  reg                      g_ram                               [0:ENTRIES-1];

  assign hit_o     = valid_i &&
                     val_ram[idx] &&
                     (vpn_ram[idx] == vpn_i) &&
                     (g_ram[idx] || (asid_ram[idx] == asid_i));
  assign payload_o = hit_o ? pte_ram[idx] : {PAYLOAD_WIDTH{1'b0}};

  wire g_from_pte = payload_i[PTE_G_BIT];
  integer i;

  always @(posedge clk) begin
    if (!resetn) begin
      for (i = 0; i < ENTRIES; i = i + 1) val_ram[i] <= 1'b0;
    end else if (flush) begin
      for (i = 0; i < ENTRIES; i = i + 1) val_ram[i] <= 1'b0;
    end else if (valid_i && we) begin
      val_ram[idx] <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (valid_i && we) begin
      vpn_ram[idx]  <= vpn_i;
      asid_ram[idx] <= g_from_pte ? {ASID_WIDTH{1'b0}} : asid_i;
      pte_ram[idx]  <= payload_i;
      g_ram[idx]    <= g_from_pte;
    end
  end

endmodule
