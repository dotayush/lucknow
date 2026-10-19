`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module alu #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] a,
    input wire [DATA_WIDTH-1:0] b,
    input wire [4:0] alu_op, // ALU operation code

    output reg [DATA_WIDTH-1:0] result,
    output reg zero, // zero flag
    output reg carry, // carry flag
    output reg overflow // overflow flag
);

  reg [DATA_WIDTH:0] a_ext;
  reg [DATA_WIDTH:0] b_ext;
  reg [DATA_WIDTH:0] result_ext;
  // multiplier: 33 bit operands and a signed product cover mul, mulh, mulhsu and mulhu (the low half is the same for all of them)
  wire a_signed = (alu_op == ALU_MULH) || (alu_op == ALU_MULHSU);
  wire b_signed = (alu_op == ALU_MULH);
  wire signed [DATA_WIDTH:0] mul_a = {a_signed & a[DATA_WIDTH-1], a};
  wire signed [DATA_WIDTH:0] mul_b = {b_signed & b[DATA_WIDTH-1], b};
  wire signed [2*DATA_WIDTH+1:0] mul_p = mul_a * mul_b;

  // divider: an unsigned restoring array on the absolute values, signs fixed afterwards. quotient and remainder come out of the same array
  function automatic [2*DATA_WIDTH-1:0] udivmod(input [DATA_WIDTH-1:0] n, input [DATA_WIDTH-1:0] d);
    reg [DATA_WIDTH-1:0] q;
    reg [DATA_WIDTH:0] r;
    integer i;
    begin
      q = '0;
      r = '0;
      for (i = DATA_WIDTH - 1; i >= 0; i = i - 1) begin
        r = {r[DATA_WIDTH-1:0], n[i]};
        if (r >= {1'b0, d}) begin
          r = r - {1'b0, d};
          q[i] = 1'b1;
        end
      end
      udivmod = {r[DATA_WIDTH-1:0], q};
    end
  endfunction

  wire div_signed = (alu_op == ALU_DIV) || (alu_op == ALU_REM);
  wire a_neg = div_signed & a[DATA_WIDTH-1];
  wire b_neg = div_signed & b[DATA_WIDTH-1];
  wire [DATA_WIDTH-1:0] div_n = a_neg ? -a : a;
  wire [DATA_WIDTH-1:0] div_d = b_neg ? -b : b;
  wire [2*DATA_WIDTH-1:0] div_qr = udivmod(div_n, div_d);
  wire [DATA_WIDTH-1:0] div_q = div_qr[DATA_WIDTH-1:0];
  wire [DATA_WIDTH-1:0] div_r = div_qr[2*DATA_WIDTH-1:DATA_WIDTH];
  wire [DATA_WIDTH-1:0] div_q_signed = (a_neg ^ b_neg) ? -div_q : div_q;
  wire [DATA_WIDTH-1:0] div_r_signed = a_neg ? -div_r : div_r;

  always @* begin
    a_ext = {1'b0, a};
    b_ext = {1'b0, b};
    result = '0;
    result_ext = '0;
    overflow = '0;

    case (alu_op)

      // arithmetic operations
      ALU_ADD: begin
        result_ext = a_ext + b_ext;
        result = result_ext[DATA_WIDTH-1:0];
        overflow = (a[DATA_WIDTH-1] == b[DATA_WIDTH-1]) && (result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
      end
      ALU_SUB: begin
        result_ext = a_ext - b_ext;
        result = result_ext[DATA_WIDTH-1:0];
        overflow = (a[DATA_WIDTH-1] != b[DATA_WIDTH-1]) && (result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
      end
      ALU_XOR: begin
        result = a ^ b;
      end
      ALU_OR: begin
        result = a | b;
      end
      ALU_AND: begin
        result = a & b;
      end

      // bitwise operations
      ALU_EQUALS: result = (a == b) ? 1 : 0;
      ALU_NOT_EQUALS: result = (a != b) ? 1 : 0;

      // comparison operations
      // a<b signed (ALU_LT), a>=b signed (ALU_GE), a<b unsigned (ALU_LTU), a >=b unsigned (ALU_GEU)
      ALU_LT: result = ($signed(a) < $signed(b)) ? 1 : 0;
      ALU_GE: result = ($signed(a) >= $signed(b)) ? 1 : 0;
      ALU_LTU: result = (a < b) ? 1 : 0;
      ALU_GEU: result = (a >= b) ? 1 : 0;

      ALU_SLL: begin
        result = a << b[$clog2(DATA_WIDTH)-1:0]; // only the low log2(width) bits are the shift amount
      end
      ALU_SRL: begin
        result = a >> b[$clog2(DATA_WIDTH)-1:0];
      end
      ALU_SRA: begin
        result = $signed(a) >>> b[$clog2(DATA_WIDTH)-1:0];
      end

      // multiplication and division: one multiplier and one divider shared by the four operations of each
      ALU_MUL: result = mul_p[DATA_WIDTH-1:0]; // lower DATA_WIDTH bits of the product
      ALU_MULH, ALU_MULHSU, ALU_MULHU: result = mul_p[2*DATA_WIDTH-1:DATA_WIDTH]; // upper bits
      ALU_DIV: result = (b == 0) ? 32'hFFFFFFFF : div_q_signed; // overflow (min int / -1) comes out as min int by itself
      ALU_DIVU: result = (b == 0) ? 32'hFFFFFFFF : div_q;
      ALU_REM: result = (b == 0) ? a : div_r_signed; // overflow gives 0
      ALU_REMU: result = (b == 0) ? a : div_r;

      default: begin
        result = '0;
        overflow = 0;
        carry = 0;
        a_ext = '0;
        b_ext = '0;
      end
    endcase

    zero = (result == 'b0);
    carry = result_ext[DATA_WIDTH];
  end

endmodule
