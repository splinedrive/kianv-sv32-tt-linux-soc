// SPDX-License-Identifier: Apache-2.0
/*
 * KianV RISC-V Linux/XV6 SoC — Register File
 * Uses 1x RM_IHPSG13_2P_64x32_c2 SRAM macro on ASIC, FF-based in sim.
 * Multi-cycle CPU: reads and writes happen in different FSM states,
 * so Port A handles rd1 reads + writes (time-multiplexed),
 * Port B handles rd2 reads only.
 *
 * Copyright (c) 2026 Hirosh Dabui <hirosh@dabui.de>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

`default_nettype none

module register_file (
    input  wire        clk,
    input  wire        we,
    input  wire [ 4:0] A1,
    input  wire [ 4:0] A2,
    input  wire [ 4:0] A3,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);

`ifdef SYNTHESIS
  // SRAM macro instance for ASIC synthesis
  wire [31:0] sram_a_dout;
  wire [31:0] sram_b_dout;

  // Port A: reads A1 when idle, writes A3 during writeback
  // Port B: always reads A2 (never writes)
  RM_IHPSG13_2P_64x32_c2 u_sram_rd1 (
      .A_CLK (clk),
      .A_MEN (1'b1),
      .A_WEN (we),
      .A_REN (~we),
      .A_ADDR({1'b0, we ? A3 : A1}),
      .A_DIN (wd),
      .A_DLY (1'b0),
      .A_DOUT(sram_a_dout),
      .B_CLK (clk),
      .B_MEN (1'b1),
      .B_WEN (1'b0),
      .B_REN (1'b1),
      .B_ADDR({1'b0, A2}),
      .B_DIN (32'b0),
      .B_DLY (1'b0),
      .B_DOUT(sram_b_dout)
  );

  // Write forwarding: if reading address being written, bypass with write data
  reg        fwd_a, fwd_b;
  reg [31:0] fwd_data;

  always @(posedge clk) begin
    fwd_a    <= we && (A1 == A3);
    fwd_b    <= we && (A2 == A3);
    fwd_data <= wd;
  end

  wire [31:0] ra_data = fwd_a ? fwd_data : sram_a_dout;
  wire [31:0] rb_data = fwd_b ? fwd_data : sram_b_dout;

`else
  // Behavioral model for simulation
  reg [31:0] ra_data;
  reg [31:0] rb_data;
  reg [31:0] storage[0:31];

  always @(posedge clk) begin
    if (we) storage[A3] <= wd;

    if (we && (A1 == A3)) ra_data <= wd;
    else ra_data <= storage[A1];

    if (we && (A2 == A3)) rb_data <= wd;
    else rb_data <= storage[A2];
  end
`endif

  assign rd1 = A1 != 0 ? ra_data : 32'b0;
  assign rd2 = A2 != 0 ? rb_data : 32'b0;

endmodule
