import isa_shared::*;

module alu #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] a,
    input wire [DATA_WIDTH-1:0] b,
    input alu_ops_e alu_op, // ALU operation code

    output reg [DATA_WIDTH-1:0] result,
    output wire zero, // zero flag
    output wire carry, // carry flag
    output wire overflow // overflow flag
);

  always_comb begin
    case (alu_op)
      ALU_ADD: result = a + b;
      default: result = '0; // Default case to avoid latches
    endcase
  end

  assign zero = (result == 0);

endmodule
