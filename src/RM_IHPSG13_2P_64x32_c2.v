// Behavioral simulation model for RM_IHPSG13_2P_64x32_c2
// For synthesis: the actual macro is provided as GDS/LEF during hardening.
// For simulation: provides a simple dual-port SRAM model.

`default_nettype none

module RM_IHPSG13_2P_64x32_c2 (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [ 5:0] A_ADDR,
    input  wire [31:0] A_DIN,
    input  wire        A_DLY,
    output wire [31:0] A_DOUT,
    input  wire        B_CLK,
    input  wire        B_MEN,
    input  wire        B_WEN,
    input  wire        B_REN,
    input  wire [ 5:0] B_ADDR,
    input  wire [31:0] B_DIN,
    input  wire        B_DLY,
    output wire [31:0] B_DOUT
);

`ifdef SYNTHESIS
  // Synthesis stub — macro provided externally via GDS/LEF
  assign A_DOUT = 32'b0;
  assign B_DOUT = 32'b0;
`else
  reg [31:0] mem [0:63];
  reg [31:0] dr_a, dr_b;

  always @(posedge A_CLK) begin
    if (A_MEN && A_WEN) begin
      mem[A_ADDR] <= A_DIN;
      if (A_REN) dr_a <= A_DIN;
    end else if (A_MEN && A_REN) begin
      dr_a <= mem[A_ADDR];
    end
  end

  always @(posedge B_CLK) begin
    if (B_MEN && B_WEN) begin
      mem[B_ADDR] <= B_DIN;
      if (B_REN) dr_b <= B_DIN;
    end else if (B_MEN && B_REN) begin
      dr_b <= mem[B_ADDR];
    end
  end

  assign A_DOUT = dr_a;
  assign B_DOUT = dr_b;
`endif

endmodule

`default_nettype wire
