`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module control #(parameter DATA_WIDTH = 32, WORDS = 64) (
    input wire clk,
    input wire rst_n
);

  // central
  reg [DATA_WIDTH-1:0] pc;
  wire [DATA_WIDTH-1:0] instruction;

  reg [DATA_WIDTH-1:0] alu_a;
  reg [DATA_WIDTH-1:0] alu_b;
  wire [DATA_WIDTH-1:0] alu_result;
  wire zero;
  wire carry;
  wire overflow;

  wire [2:0] f3;
  wire [6:0] f7;
  wire [2:0] alu_op;
  logic [2:0] sx_op;
  logic [2:0] sx_op2;
  wire mem_write;
  wire reg_write;
  wire mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;
  wire [1:0] mem_access_type;

  reg [DATA_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] data_in;

  wire [DATA_WIDTH-1:0] data_out;

  wire [DATA_WIDTH-1:0] rs1_data;
  wire [DATA_WIDTH-1:0] rs2_data;
  reg [DATA_WIDTH-1:0] rd_data;

  logic [DATA_WIDTH-1:0] unextended_data;
  logic [DATA_WIDTH-1:0] unextended_data2; // not driven by decoder but by control itself.
  logic [DATA_WIDTH-1:0] sign_extended_data;
  logic [DATA_WIDTH-1:0] sign_extended_data2;

  localparam int ADDR_WIDTH = $clog2(WORDS);

  // state machine for control logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 0;
      alu_a <= 0;
      alu_b <= 0;
      addr <= 0;
      data_in <= 0;
    end else begin
      // Control logic goes here (simplified example)
      pc <= pc + 4; // Increment PC by instruction size (assuming 4 bytes)
    end
  end

  always @* begin
    /*
    * is_store => reg_write=0, mem_write=1, mem_read = 0, rd_data=0
    * is_alu   => reg_write=1, mem_write=0, mem_read = 0, rd_data=alu_result
    * is_load  => reg_write=1, mem_write=0, mem_read = 1, rd_data=data_out
    */
    if (!reg_write && mem_write && !mem_read) begin
      rd_data = 0; // store instruction, no data to write back to register file
    end
    else if (reg_write && !mem_write && !mem_read) begin
      rd_data = alu_result; // ALU operation, write result back to register file
    end
    else if (reg_write && !mem_write && mem_read) begin
      // rd_data = data_memory[rs1_data + sign_extended_data];
      // alu_a must contain register mem [ rs1 ]
      alu_a = rs1_data; // rs1 is set by decoeder, so rs1_data = register_mem[rs1]
      alu_b = (sx_op != SX_NOP) ? sign_extended_data : rs2_data; // rs2 is set by decoder, so rs2_data = register_mem[rs2]
      addr = alu_result; // memory_address = alu_a + alu_b

      // might be redundant, but just to be sure; use this block as a post
      // processor before final result.
      case (f3)
        I_LW: unextended_data2 = data_out;
        I_LH: unextended_data2 = data_out;
        I_LB: unextended_data2 = data_out;
        I_LBU: unextended_data2 = data_out;
        I_LHU: unextended_data2 = data_out;
        default: unextended_data2 = '0; // default case, no operation
      endcase

      rd_data = unextended_data2;
    end
    else rd_data = 0; // default case, no operation
  end


  // alu
  alu #(
    .DATA_WIDTH(DATA_WIDTH)
  ) alu_inst (
    .a(alu_a),
    .b(alu_b),
    .alu_op(alu_op),
    .result(alu_result),
    .zero(zero),
    .carry(carry),
    .overflow(overflow)
  );

  // decoder
  decoder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) decoder_inst (
    .instruction(instruction),
    .f3(f3),
    .f7(f7),
    .alu_op(alu_op),
    .sx_op(sx_op),
    .sx_op2(sx_op2),
    .mem_write(mem_write),
    .reg_write(reg_write),
    .mem_read(mem_read),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .unextended_data(unextended_data),
    .mem_access_type(mem_access_type)
  );

  // data memory (ram)
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .WORDS(WORDS)
  ) data_memory_inst (
    .clk(clk),
    .addr(addr),
    .data_in(data_in),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .data_out(data_out),
    .mem_access_type(mem_access_type) // Use the access type from decoder
  );

  // instruction memory (rom)
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_INIT("./memory/test_rom.hex"),
    .WORDS(WORDS)
  ) instruction_memory_inst (
    .clk(clk),
    .addr(pc),
    .data_in(0), // No write to instruction memory
    .mem_read('1), // Always read from instruction memory
    .mem_write('0), // No write to instruction memory
    .data_out(instruction),
    .mem_access_type(isa_shared::WORD_MEM_ACCESS)
  );

  // register file
  regfile #(
    .DATA_WIDTH(DATA_WIDTH)
  ) regfile_inst (
    .clk(clk),
    .rst_n(rst_n),
    .rs1(rs1),
    .rs2(rs2),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .reg_write(reg_write),
    .rd(rd),
    .rd_data(rd_data)
  );

  // sign extender (for extendings immediates)
  signext #(
    .DATA_WIDTH(DATA_WIDTH)
  ) sign_extender_inst (
    .unextended_data(unextended_data),
    .sx_op(sx_op),
    .sign_extended_data(sign_extended_data)
  );

  // sign extender (for extending other stuff)
  signext #(
    .DATA_WIDTH(DATA_WIDTH)
  ) sign_extender_inst2 (
    .unextended_data(unextended_data2),
    .sx_op(sx_op2),
    .sign_extended_data(sign_extended_data2)
  );

endmodule
