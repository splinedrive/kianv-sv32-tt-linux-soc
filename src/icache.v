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
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
module icache #(
    parameter integer NUM_SETS   = 256,
    parameter integer LINE_BYTES = 4,
    parameter integer ADDR_WIDTH = 32,

    parameter integer HASH_ON       = 0,
    parameter integer HASH_MODE     = 2,
    parameter integer HASH_XOR_LO   = 0,
    parameter integer HASH_XOR_HI   = 1,
    parameter         ASIC          = 0,
    parameter         DEBUG         = 0,
    parameter         STATS_ONLY    = 1,
    parameter integer STATS_DUMP_AT = 300
) (
    input wire clk,
    input wire resetn,
    input wire flush,

    input  wire [ADDR_WIDTH-1:0] cpu_addr_i,
    input  wire                  cpu_valid_i,
    output reg  [          31:0] cpu_dout_o,
    output reg                   cpu_ready_o,

    output reg  [ADDR_WIDTH-1:0] ram_addr_o,
    input  wire [          31:0] ram_rdata_i,
    output reg                   ram_valid_o,
    input  wire                  ram_ready_i
);

  localparam integer OFFSET_BITS = $clog2(LINE_BYTES);
  localparam integer IDX_BITS = $clog2(NUM_SETS);
  localparam integer TAG_BITS = ADDR_WIDTH - OFFSET_BITS - IDX_BITS;

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

  localparam integer HASH_WIDTH =
      (HASH_XOR_HI >= HASH_XOR_LO) ? (HASH_XOR_HI - HASH_XOR_LO + 1) : 0;

  wire [IDX_BITS-1:0] hash_mask =
      (HASH_ON && (HASH_MODE == 1) && (HASH_WIDTH > 0)) ?
          { {(IDX_BITS-HASH_WIDTH){1'b0}}, tag[HASH_XOR_HI:HASH_XOR_LO] } :
          { IDX_BITS{1'b0} };

  wire [IDX_BITS-1:0] tag_fold = fold_tag_to_idx(tag);
  wire [IDX_BITS-1:0] idx_hash_strong = idx_raw ^ tag_fold ^ rot1(tag_fold);
  wire [IDX_BITS-1:0] idx_hash_xor = idx_raw ^ hash_mask;

  wire [IDX_BITS-1:0] idx =
      (HASH_ON == 0)   ? idx_raw         :
      (HASH_MODE == 2) ? idx_hash_strong :
      (HASH_MODE == 1) ? idx_hash_xor    :
                         idx_raw;

  initial begin
    if (NUM_SETS != 256 && NUM_SETS != 64) $fatal(1, "icache: NUM_SETS (%0d) must be 64 or 256.", NUM_SETS);
    if ((LINE_BYTES * 8) != 32)
      $fatal(1, "icache: LINE_BYTES*8 (%0d) must equal DATA_WIDTH=32.", LINE_BYTES * 8);
    if (HASH_ON && HASH_MODE == 1) begin
      if (HASH_XOR_HI < HASH_XOR_LO) $fatal(1, "icache: HASH_XOR_HI < HASH_XOR_LO.");
      if (HASH_WIDTH > TAG_BITS) $fatal(1, "icache: XOR slice wider than TAG bits.");
      if (HASH_WIDTH > IDX_BITS) $fatal(1, "icache: XOR slice wider than index width.");
    end
  end

  wire [31:0] cache_rdata;
  wire        cache_hit;
  reg cache_re, cache_we;
  reg [31:0] cache_wdata;

  icache_sram #(
      .NUM_LINES (NUM_SETS),
      .LINE_BYTES(LINE_BYTES),
      .ADDR_WIDTH(ADDR_WIDTH),
      .ASIC      (ASIC)
  ) cache_I (
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

  reg [          31:0] cache_rdata_q;
  reg                  cache_hit_q;
  reg                  read_sample_valid_q;
  reg [ADDR_WIDTH-1:0] cpu_addr_q;
  reg [  IDX_BITS-1:0] idx_q;
  reg [  TAG_BITS-1:0] tag_q;

  localparam S_IDLE = 3'd0;
  localparam S_READ = 3'd1;
  localparam S_CHECK = 3'd2;
  localparam S_MREQ = 3'd3;
  localparam S_REFILL = 3'd4;

  reg [2:0] state, next_state;

  function [8*8-1:0] state_name;
    input [2:0] s;
    begin
      case (s)
        S_IDLE:   state_name = "IDLE";
        S_READ:   state_name = "READ";
        S_CHECK:  state_name = "CHECK";
        S_MREQ:   state_name = "MREQ";
        S_REFILL: state_name = "REFILL";
        default:  state_name = "UNKNOWN";
      endcase
    end
  endfunction

  always @(posedge clk) begin
    if (!resetn) state <= S_IDLE;
    else if (flush) state <= S_IDLE;
    else state <= next_state;
  end

  always @* begin
    next_state = state;
    case (state)
      S_IDLE:   if (cpu_valid_i) next_state = S_READ;
      S_READ:   next_state = S_CHECK;
      S_CHECK:  next_state = (read_sample_valid_q && cache_hit_q) ? S_IDLE : S_MREQ;
      S_MREQ:   next_state = ram_ready_i ? S_REFILL : S_MREQ;
      S_REFILL: next_state = S_IDLE;
      default:  next_state = S_IDLE;
    endcase
  end

  always @* begin
    cpu_ready_o = 1'b0;
    cpu_dout_o  = 32'b0;

    ram_valid_o = 1'b0;
    ram_addr_o  = cpu_addr_q;

    cache_re    = 1'b0;
    cache_we    = 1'b0;
    cache_wdata = 32'b0;

    case (state)
      S_IDLE: begin
        ram_addr_o = cpu_addr_i;
        if (cpu_valid_i) cache_re = 1'b1;
      end

      S_READ: begin
        ram_addr_o = cpu_addr_q;
        cache_re   = 1'b1;
      end

      S_CHECK: begin
        ram_addr_o = cpu_addr_q;
        if (read_sample_valid_q && cache_hit_q) begin
          cpu_ready_o = 1'b1;
          cpu_dout_o  = cache_rdata_q;
        end
      end

      S_MREQ: begin
        ram_addr_o  = cpu_addr_q;
        ram_valid_o = 1'b1;
      end

      S_REFILL: begin
        ram_addr_o  = cpu_addr_q;
        cache_we    = 1'b1;
        cache_wdata = ram_rdata_i;
        cpu_ready_o = 1'b1;
        cpu_dout_o  = ram_rdata_i;
      end

      default: begin
        ram_addr_o = cpu_addr_q;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!resetn) begin
      cache_rdata_q       <= 32'b0;
      cache_hit_q         <= 1'b0;
      read_sample_valid_q <= 1'b0;
      cpu_addr_q          <= {ADDR_WIDTH{1'b0}};
      idx_q               <= {IDX_BITS{1'b0}};
      tag_q               <= {TAG_BITS{1'b0}};
    end else if (flush) begin
      cache_rdata_q       <= 32'b0;
      cache_hit_q         <= 1'b0;
      read_sample_valid_q <= 1'b0;
      cpu_addr_q          <= {ADDR_WIDTH{1'b0}};
      idx_q               <= {IDX_BITS{1'b0}};
      tag_q               <= {TAG_BITS{1'b0}};
    end else begin
      if (state == S_IDLE && cpu_valid_i) begin
        cpu_addr_q <= cpu_addr_i;
        idx_q      <= idx;
        tag_q      <= tag;
      end

      if (cache_re) begin
        cache_rdata_q       <= cache_rdata;
        cache_hit_q         <= cache_hit;
        read_sample_valid_q <= 1'b1;
      end else begin
        read_sample_valid_q <= 1'b0;
      end
    end
  end

`ifdef SIM
  reg [31:0] dbg_hits;
  reg [31:0] dbg_misses;
  reg [31:0] dbg_refills;
  reg [31:0] dbg_cpu_reqs;
  reg [31:0] dbg_flushes;
  reg [31:0] dbg_reset_cycles;
  reg [31:0] dbg_dumped;

  task automatic icache_print_stats;
    begin
      $display("============================================================");
      $display("ICACHE TOTAL STATS");
      $display("  reqs    = %0d", dbg_cpu_reqs);
      $display("  hits    = %0d", dbg_hits);
      $display("  misses  = %0d", dbg_misses);
      $display("  refills = %0d", dbg_refills);
      $display("  flushes = %0d", dbg_flushes);
      $display("  resets  = %0d", dbg_reset_cycles);
      if (dbg_cpu_reqs != 0) begin
        $display("  hitrate = %0d.%02d %%", (dbg_hits * 100) / dbg_cpu_reqs,
                 ((dbg_hits * 10000) / dbg_cpu_reqs) % 100);
        $display("  missrate= %0d.%02d %%", (dbg_misses * 100) / dbg_cpu_reqs,
                 ((dbg_misses * 10000) / dbg_cpu_reqs) % 100);
      end
      $display("============================================================");
    end
  endtask

  initial begin
    dbg_hits         = 32'd0;
    dbg_misses       = 32'd0;
    dbg_refills      = 32'd0;
    dbg_cpu_reqs     = 32'd0;
    dbg_flushes      = 32'd0;
    dbg_reset_cycles = 32'd0;
    dbg_dumped       = 32'd0;
  end

  always @(posedge clk) begin
    if (!resetn) begin
      dbg_reset_cycles <= dbg_reset_cycles + 1'b1;
    end else begin
      if (flush) dbg_flushes <= dbg_flushes + 1'b1;

      if (state == S_IDLE && cpu_valid_i) dbg_cpu_reqs <= dbg_cpu_reqs + 1'b1;

      if (state == S_CHECK && read_sample_valid_q && cache_hit_q) dbg_hits <= dbg_hits + 1'b1;

      if (state == S_CHECK && read_sample_valid_q && !cache_hit_q) dbg_misses <= dbg_misses + 1'b1;

      if (state == S_REFILL) dbg_refills <= dbg_refills + 1'b1;

      if (!dbg_dumped && STATS_DUMP_AT != 0 && dbg_cpu_reqs >= STATS_DUMP_AT) begin
        icache_print_stats();
        dbg_dumped <= 32'd1;
      end

      if (DEBUG && !STATS_ONLY) begin
        if (state != next_state) begin
          $display(
              "[ICACHE] state %0s -> %0s | cpu_valid=%0b addr=%08x addr_q=%08x idx=%02x idx_q=%02x tag=%08x tag_q=%08x hit=%0b hit_q=%0b sample=%0b ram_valid=%0b ram_ready=%0b",
              state_name(state), state_name(next_state), cpu_valid_i, cpu_addr_i, cpu_addr_q, idx,
              idx_q, tag, tag_q, cache_hit, cache_hit_q, read_sample_valid_q, ram_valid_o,
              ram_ready_i);
        end

        if (state == S_IDLE && cpu_valid_i) begin
          $display("[ICACHE] CPU REQ   addr=%08x idx_raw=%02x idx=%02x tag=%08x", cpu_addr_i,
                   idx_raw, idx, tag);
        end

        if (cache_re) begin
          $display("[ICACHE] SRAM READ addr_q=%08x idx_q=%02x tag_q=%08x -> rdata=%08x hit=%0b",
                   cpu_addr_q, idx_q, tag_q, cache_rdata, cache_hit);
        end

        if (state == S_CHECK) begin
          if (read_sample_valid_q && cache_hit_q) begin
            $display(
                "[ICACHE] HIT      addr_q=%08x idx_q=%02x tag_q=%08x data=%08x | hits=%0d misses=%0d refills=%0d reqs=%0d",
                cpu_addr_q, idx_q, tag_q, cache_rdata_q, dbg_hits + 1, dbg_misses, dbg_refills,
                dbg_cpu_reqs);
          end else if (read_sample_valid_q && !cache_hit_q) begin
            $display(
                "[ICACHE] MISS     addr_q=%08x idx_q=%02x tag_q=%08x | hits=%0d misses=%0d refills=%0d reqs=%0d",
                cpu_addr_q, idx_q, tag_q, dbg_hits, dbg_misses + 1, dbg_refills, dbg_cpu_reqs);
          end
        end

        if (state == S_MREQ && ram_ready_i) begin
          $display("[ICACHE] RAM READY addr_q=%08x data=%08x", cpu_addr_q, ram_rdata_i);
        end

        if (state == S_REFILL) begin
          $display(
              "[ICACHE] REFILL    addr_q=%08x idx_q=%02x tag_q=%08x data=%08x | hits=%0d misses=%0d refills=%0d reqs=%0d",
              cpu_addr_q, idx_q, tag_q, ram_rdata_i, dbg_hits, dbg_misses, dbg_refills + 1,
              dbg_cpu_reqs);
        end
      end
    end
  end
`endif

endmodule
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNUSEDPARAM */
`default_nettype wire
