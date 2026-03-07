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
module dcache #(

    parameter integer NUM_LINES  = 256,
    parameter integer LINE_BYTES = 4,
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,

    parameter FULL_STORE_MISS_ALLOCATE = 1'b0,

    parameter integer HASH_ON     = 0,
    parameter integer HASH_MODE   = 2,
    parameter integer HASH_XOR_LO = 0,
    parameter integer HASH_XOR_HI = 1,
    parameter         ASIC        = 0
) (
    input wire clk,
    input wire resetn,
    input wire flush,

    input  wire [    ADDR_WIDTH-1:0] cpu_addr_i,
    input  wire [(DATA_WIDTH/8)-1:0] cpu_wmask_i,
    input  wire [    DATA_WIDTH-1:0] cpu_din_i,
    output reg  [    DATA_WIDTH-1:0] cpu_dout_o,
    input  wire                      cpu_valid_i,
    output reg                       cpu_ready_o,

    output reg  [    ADDR_WIDTH-1:0] ram_addr_o,
    output reg  [(DATA_WIDTH/8)-1:0] ram_wmask_o,
    output reg  [    DATA_WIDTH-1:0] ram_wdata_o,
    input  wire [    DATA_WIDTH-1:0] ram_rdata_i,
    output reg                       ram_valid_o,
    input  wire                      ram_ready_i
);

  localparam integer OFFSET_BITS = $clog2(LINE_BYTES);
  localparam integer IDX_BITS = $clog2(NUM_LINES);
  localparam integer TAG_BITS = ADDR_WIDTH - OFFSET_BITS - IDX_BITS;
  localparam integer LANES = DATA_WIDTH / 8;

  wire [IDX_BITS-1:0] idx_raw = cpu_addr_i[OFFSET_BITS+IDX_BITS-1 : OFFSET_BITS];
  wire [TAG_BITS-1:0] tag = cpu_addr_i[ADDR_WIDTH-1 : OFFSET_BITS+IDX_BITS];

  function [IDX_BITS-1:0] fold_tag_to_idx;
    input [TAG_BITS-1:0] t;
    integer i;
    reg [IDX_BITS-1:0] f;
    begin
      f = {IDX_BITS{1'b0}};
      for (i = 0; i < TAG_BITS; i = i + 1) f[i%IDX_BITS] = f[i%IDX_BITS] ^ t[i];
      fold_tag_to_idx = f;
    end
  endfunction

  function [IDX_BITS-1:0] rot1;
    input [IDX_BITS-1:0] x;
    begin
      rot1 = {x[0], x[IDX_BITS-1:1]};
    end
  endfunction

  localparam integer HASH_WIDTH = (HASH_XOR_HI >= HASH_XOR_LO) ? (HASH_XOR_HI - HASH_XOR_LO + 1) : 0;
  wire [IDX_BITS-1:0] hash_mask =
      (HASH_ON && (HASH_MODE==1) && (HASH_WIDTH > 0)) ?
          { { (IDX_BITS-HASH_WIDTH){1'b0} }, tag[HASH_XOR_HI:HASH_XOR_LO] } :
          { IDX_BITS{1'b0} };

  wire [IDX_BITS-1:0] tag_fold = fold_tag_to_idx(tag);
  wire [IDX_BITS-1:0] idx_hash_strong = idx_raw ^ tag_fold ^ rot1(tag_fold);
  wire [IDX_BITS-1:0] idx_hash_xor = idx_raw ^ hash_mask;

  wire [IDX_BITS-1:0] idx =
        (HASH_ON==0)   ? idx_raw        :
        (HASH_MODE==2) ? idx_hash_strong:
        (HASH_MODE==1) ? idx_hash_xor   :
                         idx_raw;

  initial begin
    if (NUM_LINES != 256) $fatal(1, "dcache: NUM_LINES (%0d) must equal 256.", NUM_LINES);
    if ((LINE_BYTES * 8) != DATA_WIDTH)
      $fatal(
          1, "dcache: LINE_BYTES*8 (%0d) must equal DATA_WIDTH (%0d).", LINE_BYTES * 8, DATA_WIDTH
      );
    if (HASH_ON && HASH_MODE == 1) begin
      if (HASH_XOR_HI < HASH_XOR_LO) $fatal(1, "dcache: HASH_XOR_HI < HASH_XOR_LO.");
      if (HASH_WIDTH > TAG_BITS) $fatal(1, "dcache: XOR slice wider than TAG bits.");
      if (HASH_WIDTH > IDX_BITS) $fatal(1, "dcache: XOR slice wider than index width.");
    end
  end

  wire [DATA_WIDTH-1:0] cache_rdata;
  wire                  cache_hit;
  reg cache_re, cache_we;
  reg [DATA_WIDTH-1:0] cache_wdata;

  dcache_sram #(
      .NUM_LINES (NUM_LINES),
      .LINE_BYTES(LINE_BYTES),
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .ASIC      (ASIC)
  ) cache_D (
      .clk   (clk),
      .resetn(resetn),
      .flush (flush),
      .idx   (idx),
      .tag   (tag),
      .we    (cache_we),
      .re    (cache_re),
      .wdata (cache_wdata),
      .rdata (cache_rdata),
      .hit   (cache_hit)
  );

  reg [DATA_WIDTH-1:0] cache_rdata_q;
  reg                  cache_hit_q;
  always @(posedge clk) begin
    if (!resetn) begin
      cache_rdata_q <= {DATA_WIDTH{1'b0}};
      cache_hit_q   <= 1'b0;
    end else if (flush) begin
      cache_rdata_q <= {DATA_WIDTH{1'b0}};
      cache_hit_q   <= 1'b0;
    end else begin
      cache_rdata_q <= cache_rdata;
      cache_hit_q   <= cache_hit;
    end
  end

  reg [     LANES-1:0] cpu_wmask_q;
  reg [DATA_WIDTH-1:0] cpu_din_q;
  always @(posedge clk) begin
    if (!resetn) begin
      cpu_wmask_q <= {LANES{1'b0}};
      cpu_din_q   <= {DATA_WIDTH{1'b0}};
    end else if (flush) begin
      cpu_wmask_q <= {LANES{1'b0}};
      cpu_din_q   <= {DATA_WIDTH{1'b0}};
    end else begin
      cpu_wmask_q <= cpu_wmask_i;
      cpu_din_q   <= cpu_din_i;
    end
  end

  wire is_read_req = (cpu_wmask_q == {LANES{1'b0}});
  wire is_full_write = (cpu_wmask_q == {LANES{1'b1}});
  wire is_part_write = (cpu_wmask_q != {LANES{1'b0}}) && !is_full_write;

  function [DATA_WIDTH-1:0] apply_wmask;
    input [DATA_WIDTH-1:0] old_data;
    input [DATA_WIDTH-1:0] new_data;
    input [LANES-1:0] wmask;
    integer i;
    begin
      for (i = 0; i < LANES; i = i + 1)
      apply_wmask[i*8+:8] = wmask[i] ? new_data[i*8+:8] : old_data[i*8+:8];
    end
  endfunction

  localparam S_IDLE    = 3'd0,
             S_READ    = 3'd1,
             S_CHECK   = 3'd2,
             S_RD_REQ  = 3'd3,
             S_REFILL  = 3'd4,
             S_WR_REQ  = 3'd5;

  reg [2:0] state, next_state;
  always @(posedge clk) begin
    if (!resetn) state <= S_IDLE;
    else if (flush) state <= S_IDLE;
    else state <= next_state;
  end

  reg op_is_read, op_is_full, op_is_partial;
  reg wr_from_hit;

  reg pending_we;
  reg [DATA_WIDTH-1:0] pending_data;

  wire want_alloc_full_miss = op_is_full && !wr_from_hit && FULL_STORE_MISS_ALLOCATE;
  wire want_alloc = wr_from_hit || op_is_partial || want_alloc_full_miss;

  always @(*) begin
    next_state = state;
    case (state)
      S_IDLE:   if (cpu_valid_i) next_state = S_READ;
      S_READ:   next_state = S_CHECK;
      S_CHECK: begin
        if (cache_hit_q) begin
          next_state = is_read_req ? S_IDLE : S_WR_REQ;
        end else begin
          if (is_read_req) next_state = S_RD_REQ;
          else if (is_full_write) next_state = S_WR_REQ;
          else next_state = S_RD_REQ;
        end
      end
      S_RD_REQ: if (ram_ready_i) next_state = op_is_read ? S_REFILL : S_WR_REQ;
      S_REFILL: next_state = S_IDLE;
      S_WR_REQ: if (ram_ready_i) next_state = S_IDLE;
      default:  next_state = S_IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (!resetn) begin
      op_is_read    <= 1'b0;
      op_is_full    <= 1'b0;
      op_is_partial <= 1'b0;
      wr_from_hit   <= 1'b0;
      pending_we    <= 1'b0;
      pending_data  <= {DATA_WIDTH{1'b0}};
    end else if (flush) begin
      op_is_read    <= 1'b0;
      op_is_full    <= 1'b0;
      op_is_partial <= 1'b0;
      wr_from_hit   <= 1'b0;
      pending_we    <= 1'b0;
      pending_data  <= {DATA_WIDTH{1'b0}};
    end else begin
      if (state == S_WR_REQ && ram_ready_i && pending_we) pending_we <= 1'b0;

      case (state)
        S_CHECK: begin
          op_is_read    <= is_read_req;
          op_is_full    <= is_full_write;
          op_is_partial <= is_part_write;

          if (cache_hit_q) begin
            wr_from_hit <= !is_read_req;
            if (!is_read_req) begin
              pending_data <= is_full_write ? cpu_din_q : apply_wmask(
                  cache_rdata_q, cpu_din_q, cpu_wmask_q
              );
              pending_we <= 1'b1;
            end
          end else begin
            wr_from_hit <= 1'b0;
            if (is_full_write) begin
              pending_data <= cpu_din_q;
              pending_we   <= 1'b1;
            end
          end
        end

        S_RD_REQ:
        if (ram_ready_i && op_is_partial) begin
          pending_data <= apply_wmask(ram_rdata_i, cpu_din_q, cpu_wmask_q);
          pending_we   <= 1'b1;
        end
        default: ;
      endcase
    end
  end

  always @(*) begin
    cpu_ready_o = 1'b0;
    cpu_dout_o  = {DATA_WIDTH{1'b0}};

    ram_valid_o = 1'b0;
    ram_wmask_o = {LANES{1'b0}};
    ram_wdata_o = cpu_din_q;
    ram_addr_o  = cpu_addr_i;

    cache_re    = 1'b0;
    cache_we    = 1'b0;
    cache_wdata = {DATA_WIDTH{1'b0}};

    case (state)
      S_IDLE:   if (cpu_valid_i) cache_re = 1'b1;
      S_READ:   cache_re = 1'b1;
      S_CHECK:
      if (cache_hit_q && is_read_req) begin
        cpu_ready_o = 1'b1;
        cpu_dout_o  = cache_rdata_q;
      end
      S_RD_REQ: ram_valid_o = 1'b1;
      S_REFILL: begin
        cache_we    = 1'b1;
        cache_wdata = ram_rdata_i;
        cpu_ready_o = 1'b1;
        cpu_dout_o  = ram_rdata_i;
      end
      S_WR_REQ: begin
        ram_valid_o = 1'b1;
        ram_wmask_o = cpu_wmask_q;
        ram_wdata_o = cpu_din_q;
        if (ram_ready_i) begin
          if (pending_we && want_alloc) begin
            cache_we    = 1'b1;
            cache_wdata = pending_data;
          end
          cpu_ready_o = 1'b1;
        end
      end
      default:  ;
    endcase
  end

`ifdef CACHE_DBG

  initial begin
    $display("[D$] Geometry: NUM_LINES=%0d LINE_BYTES=%0d DATA_BITS=%0d TAG_BITS=%0d", NUM_LINES,
             LINE_BYTES, DATA_WIDTH, TAG_BITS);
    if (!HASH_ON) $display("[D$] Index hashing: OFF");
    else if (HASH_MODE == 1)
      $display("[D$] Index hashing: ON  (XOR tag[%0d:%0d])", HASH_XOR_HI, HASH_XOR_LO);
    else $display("[D$] Index hashing: ON  (fold+rotate)");
  end

`endif

endmodule
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on WIDTHEXPAND */
`default_nettype wire
