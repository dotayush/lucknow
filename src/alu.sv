module alu #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] a,
    input wire [DATA_WIDTH-1:0] b,
    input wire [2:0] alu_op, // ALU operation code

    output reg [DATA_WIDTH-1:0] result,
    output wire zero, // zero flag
    output wire carry, // carry flag
    output wire overflow // overflow flag
);

  typedef enum logic [2:0] {
    LW = 3'b000 // Load Word
  } alu_ops_e;

  always_comb begin
    case (alu_op)
      LW: result = a + b;
      default: result = '0; // Default case to avoid latches
    endcase
  end

  assign zero = (result == 0);

endmodule
