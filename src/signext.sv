import isa_shared::*;

module signext #(parameter DATA_WIDTH = 32) (
    input wire [24:0] instruction,
    input wire [2:0] imm_op,

    output reg [DATA_WIDTH-1:0] sign_extended_data
);
  reg [11:0] extracted_immediate;

  always @* begin
    case (imm_op)
      IMM_3120: extracted_immediate = instruction[24:13]; // extract immediate from 31:20 bits of raw instruction = 24:13 bits of minus opcode instruction
      default: extracted_immediate = '0;
    endcase

    // (32-12 = 20) repeat 11th bit + [11:0]imm => 32 bits
    sign_extended_data = {{(DATA_WIDTH-$bits(extracted_immediate)){extracted_immediate[11]}}, extracted_immediate};
  end


endmodule
