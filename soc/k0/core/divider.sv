`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

// div, divu, rem and remu, one bit per clock. a restoring divider on the absolute values, signs fixed at the end.
//
// run is held high while a divide instruction is the one being executed (control.sv drops it when the instruction
// is abandoned, for example for an interrupt). the first clock loads the operands, the next DATA_WIDTH clocks produce
// one quotient bit each, then done is high for one clock with the result valid: that is the clock the instruction
// retires, which drops run's effect and clears done. an instruction takes DATA_WIDTH + 2 clocks.
//
// division by zero and overflow follow the spec: x / 0 = all ones and x % 0 = x; min int / -1 = min int and min int % -1 = 0
// (the second falls out of the absolute value arithmetic by itself).
module divider #(parameter DATA_WIDTH = 32) (
    input wire clk,
    input wire rst_n,
    input wire run,
    input wire [4:0] alu_op,                  // ALU_DIV, ALU_DIVU, ALU_REM or ALU_REMU, stable while run is high
    input wire [DATA_WIDTH-1:0] a,            // dividend, stable while run is high
    input wire [DATA_WIDTH-1:0] b,            // divisor, stable while run is high
    output wire done,
    output wire [DATA_WIDTH-1:0] result
);

  localparam int CNT_W = $clog2(DATA_WIDTH + 1);

  reg [CNT_W-1:0] cnt;      // 0: not started, 1 to DATA_WIDTH: the bit being produced
  reg done_r;
  reg [DATA_WIDTH-1:0] n;   // the dividend shifts out of the top while the quotient shifts in at the bottom
  reg [DATA_WIDTH:0] r;     // partial remainder
  reg [DATA_WIDTH-1:0] d;   // divisor, absolute value
  reg [DATA_WIDTH-1:0] a_orig;
  reg a_neg, b_neg, b_zero, want_rem;

  wire is_signed = (alu_op == ALU_DIV) || (alu_op == ALU_REM);
  wire [DATA_WIDTH:0] r_shift = {r[DATA_WIDTH-1:0], n[DATA_WIDTH-1]};
  wire ge = (r_shift >= {1'b0, d});

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= 0;
      done_r <= 0;
      n <= 0;
      r <= 0;
      d <= 0;
      a_orig <= 0;
      a_neg <= 0;
      b_neg <= 0;
      b_zero <= 0;
      want_rem <= 0;
    end
    else if (!run || done_r) begin
      // idle, or the clock the instruction retires: ready for the next one
      cnt <= 0;
      done_r <= 0;
    end
    else if (cnt == 0) begin
      a_neg <= is_signed && a[DATA_WIDTH-1];
      b_neg <= is_signed && b[DATA_WIDTH-1];
      n <= (is_signed && a[DATA_WIDTH-1]) ? -a : a;
      d <= (is_signed && b[DATA_WIDTH-1]) ? -b : b;
      r <= '0;
      a_orig <= a;
      b_zero <= (b == '0);
      want_rem <= (alu_op == ALU_REM) || (alu_op == ALU_REMU);
      cnt <= 1;
    end
    else begin
      n <= {n[DATA_WIDTH-2:0], ge};     // quotient bit in at the bottom
      r <= ge ? (r_shift - {1'b0, d}) : r_shift;
      cnt <= cnt + 1'b1;
      if (cnt == DATA_WIDTH) done_r <= 1;
    end
  end

  wire [DATA_WIDTH-1:0] q = n;
  wire [DATA_WIDTH-1:0] rem = r[DATA_WIDTH-1:0];
  wire [DATA_WIDTH-1:0] q_signed = (a_neg ^ b_neg) ? -q : q;
  wire [DATA_WIDTH-1:0] rem_signed = a_neg ? -rem : rem;

  assign done = done_r;
  assign result = want_rem ? (b_zero ? a_orig : rem_signed)
                           : (b_zero ? {DATA_WIDTH{1'b1}} : q_signed);

endmodule
