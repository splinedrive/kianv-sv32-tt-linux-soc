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
module dcache #(

    parameter integer NUM_LINES  = 256,
    parameter integer LINE_BYTES = 4,
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,

    parameter FULL_STORE_MISS_ALLOCATE = 1'b0,

    parameter integer HASH_ON       = 0,
    parameter integer HASH_MODE     = 2,
    parameter integer HASH_XOR_LO   = 0,
    parameter integer HASH_XOR_HI   = 1,
    parameter         ASIC          = 0,
    parameter         DEBUG         = 0,
    parameter         STATS_ONLY    = 1,
    parameter integer STATS_DUMP_AT = 500
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

  localparam S_IDLE   = 3'd0,
             S_READ   = 3'd1,
             S_CHECK  = 3'd2,
             S_RD_REQ = 3'd3,
             S_REFILL = 3'd4,
             S_WR_REQ = 3'd5;

  reg [2:0] state, next_state;

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

  function [8*8-1:0] state_name;
    input [2:0] s;
    begin
      case (s)
        S_IDLE:   state_name = "IDLE";
        S_READ:   state_name = "READ";
        S_CHECK:  state_name = "CHECK";
        S_RD_REQ: state_name = "RD_REQ";
        S_REFILL: state_name = "REFILL";
        S_WR_REQ: state_name = "WR_REQ";
        default:  state_name = "UNKNOWN";
      endcase
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
    if (NUM_LINES != 512 && NUM_LINES != 256 && NUM_LINES != 64) $fatal(1, "dcache: NUM_LINES (%0d) must be 64, 256 or 512.", NUM_LINES);
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
  reg                  read_sample_valid_q;
  reg [ADDR_WIDTH-1:0] cpu_addr_q;
  reg [  IDX_BITS-1:0] idx_q;
  reg [  TAG_BITS-1:0] tag_q;

  always @(posedge clk) begin
    if (!resetn) begin
      cache_rdata_q       <= {DATA_WIDTH{1'b0}};
      cache_hit_q         <= 1'b0;
      read_sample_valid_q <= 1'b0;
      cpu_addr_q          <= {ADDR_WIDTH{1'b0}};
      idx_q               <= {IDX_BITS{1'b0}};
      tag_q               <= {TAG_BITS{1'b0}};
    end else if (flush) begin
      cache_rdata_q       <= {DATA_WIDTH{1'b0}};
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
      if (state == S_IDLE && cpu_valid_i) begin
        cpu_wmask_q <= cpu_wmask_i;
        cpu_din_q   <= cpu_din_i;
      end
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

  reg op_is_read, op_is_full, op_is_partial;
  reg wr_from_hit;

  reg pending_we;
  reg [DATA_WIDTH-1:0] pending_data;

  wire want_alloc_full_miss = op_is_full && !wr_from_hit && FULL_STORE_MISS_ALLOCATE;
  wire want_alloc = wr_from_hit || op_is_partial || want_alloc_full_miss;

  always @(posedge clk) begin
    if (!resetn) state <= S_IDLE;
    else if (flush) state <= S_IDLE;
    else state <= next_state;
  end

  always @(*) begin
    next_state = state;
    case (state)
      S_IDLE:   if (cpu_valid_i) next_state = S_READ;
      S_READ:   next_state = S_CHECK;
      S_CHECK: begin
        if (read_sample_valid_q && cache_hit_q) begin
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

          if (read_sample_valid_q && cache_hit_q) begin
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
    ram_addr_o  = cpu_addr_q;

    cache_re    = 1'b0;
    cache_we    = 1'b0;
    cache_wdata = {DATA_WIDTH{1'b0}};

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
        if (read_sample_valid_q && cache_hit_q && is_read_req) begin
          cpu_ready_o = 1'b1;
          cpu_dout_o  = cache_rdata_q;
        end
      end

      S_RD_REQ: begin
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

      S_WR_REQ: begin
        ram_addr_o  = cpu_addr_q;
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
      default: ;
    endcase
  end

`ifdef SIM
  reg [31:0] dbg_reqs;
  reg [31:0] dbg_read_reqs;
  reg [31:0] dbg_write_reqs;
  reg [31:0] dbg_read_hits;
  reg [31:0] dbg_read_misses;
  reg [31:0] dbg_write_hits;
  reg [31:0] dbg_write_misses;
  reg [31:0] dbg_refills;
  reg [31:0] dbg_flushes;
  reg [31:0] dbg_reset_cycles;
  reg [31:0] dbg_classified;
  reg [31:0] dbg_pending_reqs;
  reg [31:0] dbg_write_allocs;
  reg [31:0] dbg_ram_writes;
  reg [31:0] dbg_dumped;

  task automatic dcache_print_stats;
    reg [31:0] dbg_hits_total;
    reg [31:0] dbg_misses_total;
    begin
      dbg_hits_total   = dbg_read_hits + dbg_write_hits;
      dbg_misses_total = dbg_read_misses + dbg_write_misses;

      $display("============================================================");
      $display("DCACHE TOTAL STATS");
      $display("  reqs         = %0d", dbg_reqs);
      $display("  classified   = %0d", dbg_classified);
      $display("  pending      = %0d", dbg_pending_reqs);
      $display("  read_reqs    = %0d", dbg_read_reqs);
      $display("  write_reqs   = %0d", dbg_write_reqs);
      $display("  hits         = %0d", dbg_hits_total);
      $display("  misses       = %0d", dbg_misses_total);
      $display("  read_hits    = %0d", dbg_read_hits);
      $display("  read_misses  = %0d", dbg_read_misses);
      $display("  write_hits   = %0d", dbg_write_hits);
      $display("  write_misses = %0d", dbg_write_misses);
      $display("  refills      = %0d", dbg_refills);
      $display("  ram_writes   = %0d", dbg_ram_writes);
      $display("  write_allocs = %0d", dbg_write_allocs);
      $display("  flushes      = %0d", dbg_flushes);
      $display("  resets       = %0d", dbg_reset_cycles);
      if (dbg_classified != 0) begin
        $display("  hitrate      = %0d.%02d %%", (dbg_hits_total * 100) / dbg_classified,
                 ((dbg_hits_total * 10000) / dbg_classified) % 100);
        $display("  missrate     = %0d.%02d %%", (dbg_misses_total * 100) / dbg_classified,
                 ((dbg_misses_total * 10000) / dbg_classified) % 100);
      end
      if ((dbg_read_hits + dbg_read_misses) != 0) begin
        $display("  read_hitrate = %0d.%02d %%",
                 (dbg_read_hits * 100) / (dbg_read_hits + dbg_read_misses),
                 ((dbg_read_hits * 10000) / (dbg_read_hits + dbg_read_misses)) % 100);
      end
      if ((dbg_write_hits + dbg_write_misses) != 0) begin
        $display("  write_hitrate= %0d.%02d %%",
                 (dbg_write_hits * 100) / (dbg_write_hits + dbg_write_misses),
                 ((dbg_write_hits * 10000) / (dbg_write_hits + dbg_write_misses)) % 100);
      end
      $display("============================================================");
    end
  endtask

  initial begin
    dbg_reqs         = 32'd0;
    dbg_read_reqs    = 32'd0;
    dbg_write_reqs   = 32'd0;
    dbg_read_hits    = 32'd0;
    dbg_read_misses  = 32'd0;
    dbg_write_hits   = 32'd0;
    dbg_write_misses = 32'd0;
    dbg_refills      = 32'd0;
    dbg_flushes      = 32'd0;
    dbg_reset_cycles = 32'd0;
    dbg_classified   = 32'd0;
    dbg_pending_reqs = 32'd0;
    dbg_write_allocs = 32'd0;
    dbg_ram_writes   = 32'd0;
    dbg_dumped       = 32'd0;
  end

  always @(posedge clk) begin
    if (!resetn) begin
      dbg_reset_cycles <= dbg_reset_cycles + 1'b1;
    end else begin
      if (flush) dbg_flushes <= dbg_flushes + 1'b1;

      if (state == S_IDLE && cpu_valid_i) begin
        dbg_reqs <= dbg_reqs + 1'b1;
        if (cpu_wmask_i == {LANES{1'b0}}) dbg_read_reqs <= dbg_read_reqs + 1'b1;
        else dbg_write_reqs <= dbg_write_reqs + 1'b1;
      end

      if (state == S_CHECK && read_sample_valid_q && cache_hit_q) begin
        dbg_classified <= dbg_classified + 1'b1;
        if (is_read_req) dbg_read_hits <= dbg_read_hits + 1'b1;
        else dbg_write_hits <= dbg_write_hits + 1'b1;
      end

      if (state == S_CHECK && read_sample_valid_q && !cache_hit_q) begin
        dbg_classified <= dbg_classified + 1'b1;
        if (is_read_req) dbg_read_misses <= dbg_read_misses + 1'b1;
        else dbg_write_misses <= dbg_write_misses + 1'b1;
      end

      if (state == S_REFILL) dbg_refills <= dbg_refills + 1'b1;

      if (state == S_WR_REQ && ram_ready_i) dbg_ram_writes <= dbg_ram_writes + 1'b1;

      if (state == S_WR_REQ && ram_ready_i && pending_we && want_alloc)
        dbg_write_allocs <= dbg_write_allocs + 1'b1;

      dbg_pending_reqs <= dbg_reqs - dbg_classified;

      if (!dbg_dumped && STATS_DUMP_AT != 0 && dbg_reqs >= STATS_DUMP_AT) begin
        dcache_print_stats();
        dbg_dumped <= 32'd1;
      end

      if (DEBUG && !STATS_ONLY) begin
        if (state != next_state) begin
          $display(
              "[DCACHE] state %0s -> %0s | cpu_valid=%0b addr=%08x addr_q=%08x idx=%02x idx_q=%02x tag=%08x tag_q=%08x wmask_i=%0h wmask_q=%0h hit=%0b hit_q=%0b sample=%0b ram_valid=%0b ram_ready=%0b",
              state_name(state), state_name(next_state), cpu_valid_i, cpu_addr_i, cpu_addr_q, idx,
              idx_q, tag, tag_q, cpu_wmask_i, cpu_wmask_q, cache_hit, cache_hit_q,
              read_sample_valid_q, ram_valid_o, ram_ready_i);
        end

        if (state == S_IDLE && cpu_valid_i) begin
          $display("[DCACHE] CPU REQ  addr=%08x idx_raw=%02x idx=%02x tag=%08x wmask=%0h din=%08x",
                   cpu_addr_i, idx_raw, idx, tag, cpu_wmask_i, cpu_din_i);
        end

        if (cache_re) begin
          $display("[DCACHE] SRAM READ addr_q=%08x idx_q=%02x tag_q=%08x -> rdata=%08x hit=%0b",
                   cpu_addr_q, idx_q, tag_q, cache_rdata, cache_hit);
        end

        if (state == S_CHECK) begin
          if (read_sample_valid_q && cache_hit_q) begin
            $display("[DCACHE] HIT     addr_q=%08x idx_q=%02x tag_q=%08x rdata=%08x wmask=%0h",
                     cpu_addr_q, idx_q, tag_q, cache_rdata_q, cpu_wmask_q);
          end else if (read_sample_valid_q && !cache_hit_q) begin
            $display("[DCACHE] MISS    addr_q=%08x idx_q=%02x tag_q=%08x wmask=%0h", cpu_addr_q,
                     idx_q, tag_q, cpu_wmask_q);
          end
        end

        if (state == S_RD_REQ && ram_ready_i) begin
          $display("[DCACHE] RAM READ READY addr_q=%08x data=%08x", cpu_addr_q, ram_rdata_i);
        end

        if (state == S_REFILL) begin
          $display("[DCACHE] REFILL  addr_q=%08x idx_q=%02x tag_q=%08x data=%08x", cpu_addr_q,
                   idx_q, tag_q, ram_rdata_i);
        end

        if (state == S_WR_REQ && ram_ready_i) begin
          $display(
              "[DCACHE] WRITE   addr_q=%08x wmask=%0h wdata=%08x pending_we=%0b want_alloc=%0b pending_data=%08x",
              cpu_addr_q, cpu_wmask_q, cpu_din_q, pending_we, want_alloc, pending_data);
        end
      end
    end
  end
`endif

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
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNUSEDPARAM */
`default_nettype wire
