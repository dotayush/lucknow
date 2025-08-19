`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module signext #(parameter DATA_WIDTH = 32) (
    input logic [DATA_WIDTH-1:0] unextended_data, // '0 || whatever bits = 32 bits which can then be extracted
    input logic [2:0] sx_op,

    output logic [DATA_WIDTH-1:0] sign_extended_data
);

  always @* begin
    case (sx_op)
      SX_1100: sign_extended_data = {{(DATA_WIDTH-1-11){unextended_data[11]}}, unextended_data[11:0]};
      SX_3100: sign_extended_data = unextended_data; // since unextended_data [31:0] = sign_extended_data [31:0]
      SX_1500: sign_extended_data = {{(DATA_WIDTH-1-15){unextended_data[15]}}, unextended_data[15:0]};
      SX_0700: sign_extended_data = {{(DATA_WIDTH-1-7){unextended_data[7]}}, unextended_data[7:0]};
      default: sign_extended_data = '0;
    endcase
  end


endmodule
