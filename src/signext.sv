module signext #(parameter DATA_WIDTH = 32) (
    input wire [24:0] instruction,
    input wire [2:0] alu_op,

    output reg [DATA_WIDTH-1:0] sign_extended_data
);
  reg [11:0] extracted_immediate;
  typedef enum logic [2:0] {
    LW = 3'b000 // Load Word
  } alu_ops_e;

  always @* begin
    case (alu_op)
      LW: extracted_immediate = instruction[24:13]; // Extract immediate for Load Word
      default: extracted_immediate = '0; // Default case to avoid latches
    endcase

    // (32-12) 20 repeat of 11th bit + [11:0]imm => 32 bits
    sign_extended_data = {{(DATA_WIDTH-$bits(extracted_immediate)){extracted_immediate[11]}}, extracted_immediate};
  end


endmodule
