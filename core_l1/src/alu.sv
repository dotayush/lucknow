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
  reg [2*DATA_WIDTH-1:0] math_a_ext;
  reg [2*DATA_WIDTH-1:0] math_b_ext;
  reg [2*DATA_WIDTH-1:0] math_result_ext;

  always @* begin
    a_ext = {1'b0, a};
    b_ext = {1'b0, b};
    result = '0;
    result_ext = '0;
    math_a_ext = '0;
    math_b_ext = '0;
    math_result_ext = '0;
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
        result = a << b;
      end
      ALU_SRL: begin
        result = a >> b;
      end
      ALU_SRA: begin
        result = $signed(a) >>> b;
      end

      // multiplication operations
      ALU_MUL: begin
        result = a * b; // lower DATA_WIDTH bits of the product
      end
      ALU_MULH: begin
        math_a_ext = {{(DATA_WIDTH){a[DATA_WIDTH-1]}}, a}; // sign-extend a
        math_b_ext = {{(DATA_WIDTH){b[DATA_WIDTH-1]}}, b}; // sign-extend b
        math_result_ext = math_a_ext * math_b_ext;
        result = math_result_ext[2*DATA_WIDTH-1:DATA_WIDTH]; // upper DATA_WIDTH bits of the product
      end
      ALU_MULHSU: begin
        math_a_ext = {{(DATA_WIDTH){a[DATA_WIDTH-1]}}, a}; // sign-extend a
        math_b_ext = { {DATA_WIDTH{1'b0}}, b}; // zero-extend b
        math_result_ext = math_a_ext * math_b_ext;
        result = math_result_ext[2*DATA_WIDTH-1:DATA_WIDTH];
      end
      ALU_MULHU: begin
        math_a_ext = { {DATA_WIDTH{1'b0}}, a}; // zero-extend a
        math_b_ext = { {DATA_WIDTH{1'b0}}, b}; // zero-extend b
        math_result_ext = math_a_ext * math_b_ext;
        result = math_result_ext[2*DATA_WIDTH-1:DATA_WIDTH];
      end
      ALU_DIV: begin
        if (b == 0) begin
          result = 32'hFFFFFFFF; // return all 1s on division by zero
        end else if (a == 32'h80000000 && b == 32'hFFFFFFFF) begin
          result = 32'h80000000; // in case of overflow return min int
        end else begin
          result = $signed(a) / $signed(b); // else go for it.
        end
      end
      ALU_DIVU: begin
        if (b == 0) begin
          result = 32'hFFFFFFFF; // return all 1s on division by zero
        end else begin
          result = a / b; // else go for it.
        end
      end
      ALU_REM: begin
        if (b == 0) begin
          result = a; // return dividend on division by zero
        end else if (a == 32'h80000000 && b == 32'hFFFFFFFF) begin
          result = 0; // in case of overflow return 0
        end else begin
          result = $signed(a) % $signed(b); // else go for it.
        end
      end
      ALU_REMU: begin
        if (b == 0) begin
          result = a; // return dividend on division by zero
        end else begin
          result = a % b; // else go for it.
        end
      end

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
