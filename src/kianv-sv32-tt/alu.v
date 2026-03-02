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
`include "riscv_defines.vh"

module alu (
    input  wire [                31:0] a,
    input  wire [                31:0] b,
    input  wire [`ALU_CTRL_WIDTH -1:0] alucontrol,
    output reg  [                31:0] result,
    output wire                        zero
);

  wire is_beq = alucontrol == `ALU_CTRL_BEQ;
  wire is_bne = alucontrol == `ALU_CTRL_BNE;
  wire is_blt = alucontrol == `ALU_CTRL_BLT;
  wire is_bge = alucontrol == `ALU_CTRL_BGE;
  wire is_bltu = alucontrol == `ALU_CTRL_BLTU;
  wire is_bgeu = alucontrol == `ALU_CTRL_BGEU;
  wire is_slt_slti = alucontrol == `ALU_CTRL_SLT_SLTI;
  wire is_sltu_sltiu = alucontrol == `ALU_CTRL_SLTU_SLTIU;
  wire is_sub_ctrl = alucontrol == `ALU_CTRL_SUB;
  wire is_amo_min_max = alucontrol == `ALU_CTRL_MIN || alucontrol == `ALU_CTRL_MAX ||
         alucontrol == `ALU_CTRL_MINU || alucontrol == `ALU_CTRL_MAXU;

  wire is_sub = is_sub_ctrl || is_beq || is_bne || is_blt || is_bge ||
         is_bltu || is_bgeu || is_slt_slti || is_amo_min_max || is_sltu_sltiu;

  wire [31:0] condinv = is_sub ? ~b : b;

  wire [32:0] sum = {1'b1, condinv} + {1'b0, a} + {32'b0, is_sub};
  wire LT = (a[31] ^ b[31]) ? a[31] : sum[32];
  wire LTU = sum[32];

  wire [31:0] sltx_sltux_rslt = {31'b0, is_slt_slti ? LT : LTU};
  wire [63:0] sext_rs1 = {{32{a[31]}}, a};
  wire [63:0] sra_srai_rslt = sext_rs1 >> b[4:0];

  wire is_sum_zero = sum[31:0] == 32'b0;

  always @* begin
    case (alucontrol)
      `ALU_CTRL_ADD_ADDI:   result = sum[31:0];
      `ALU_CTRL_SUB:        result = sum[31:0];
      `ALU_CTRL_XOR_XORI:   result = a ^ b;
      `ALU_CTRL_OR_ORI:     result = a | b;
      `ALU_CTRL_AND_ANDI:   result = a & b;
      `ALU_CTRL_SLL_SLLI:   result = a << b[4:0];
      `ALU_CTRL_SRL_SRLI:   result = a >> b[4:0];
      `ALU_CTRL_SRA_SRAI:   result = sra_srai_rslt[31:0];
      `ALU_CTRL_SLT_SLTI:   result = (a[31] == b[31]) ? sltx_sltux_rslt : {31'b0, a[31]};
      `ALU_CTRL_SLTU_SLTIU: result = sltx_sltux_rslt;
      `ALU_CTRL_MIN:        result = LT ? a : b;
      `ALU_CTRL_MAX:        result = !LT ? a : b;
      `ALU_CTRL_MINU:       result = LTU ? a : b;
      `ALU_CTRL_MAXU:       result = !LTU ? a : b;
      `ALU_CTRL_LUI:        result = b;
      `ALU_CTRL_AUIPC:      result = sum[31:0];
      default: begin
        case (1'b1)
          is_beq:  result = {31'b0, is_sum_zero};
          is_bne:  result = {31'b0, !is_sum_zero};
          is_blt:  result = {31'b0, LT};
          is_bge:  result = {31'b0, !LT};
          is_bltu: result = {31'b0, LTU};
          is_bgeu: result = {31'b0, !LTU};
          default: result = 32'b0;
        endcase
      end
    endcase
  end

  assign zero = !result[0];
endmodule
