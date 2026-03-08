// Behavioral simulation model for RM_IHPSG13_1P_64x64_c2_bm_bist
// For synthesis: the actual macro is provided as GDS/LEF during hardening.
// For simulation: provides a simple single-port SRAM model.

`default_nettype none

module RM_IHPSG13_1P_64x64_c2_bm_bist (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [5:0]  A_ADDR,
    input  wire [63:0] A_DIN,
    input  wire        A_DLY,
    output wire [63:0] A_DOUT,
    input  wire [63:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire [5:0]  A_BIST_ADDR,
    input  wire [63:0] A_BIST_DIN,
    input  wire [63:0] A_BIST_BM
);

`ifdef SYNTHESIS
  // Synthesis stub — macro provided externally
  assign A_DOUT = 64'b0;
`else
  // Behavioral model for simulation
  reg [63:0] mem [0:63];
  reg [63:0] dout_r;

  assign A_DOUT = dout_r;

  always @(posedge A_CLK) begin
    if (A_MEN) begin
      if (A_WEN) begin
        mem[A_ADDR] <= (mem[A_ADDR] & ~A_BM) | (A_DIN & A_BM);
      end
      if (A_REN) begin
        dout_r <= mem[A_ADDR];
      end
    end
  end
`endif

endmodule

`default_nettype wire
