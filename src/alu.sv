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

      // bitwise operations
      ALU_EQUALS: result = (a == b) ? 1 : 0;
      ALU_NOT_EQUALS: result = (a != b) ? 1 : 0;

      // comparison operations
      // a<b signed (ALU_LT), a>=b signed (ALU_GE), a<b unsigned (ALU_LTU), a >=b unsigned (ALU_GEU)
      ALU_LT: result = ($signed(a) < $signed(b)) ? 1 : 0;
      ALU_GE: result = ($signed(a) >= $signed(b)) ? 1 : 0;
      ALU_LTU: result = (a < b) ? 1 : 0;
      ALU_GEU: result = (a >= b) ? 1 : 0;

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
