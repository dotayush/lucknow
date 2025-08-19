`ifndef ISA_SHARED_IMPORT
import isa_shared::*;
`endif

module alu #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] a,
    input wire [DATA_WIDTH-1:0] b,
    input wire [2:0] alu_op, // ALU operation code

    output reg [DATA_WIDTH-1:0] result,
    output reg zero, // zero flag
    output reg carry, // carry flag
    output reg overflow // overflow flag
);

  always_comb begin
    case (alu_op)
      ALU_ADD: result = a + b;
      default: result = '0; // Default case to avoid latches
    endcase
  end

  assign zero = (result == 0);

endmodule
