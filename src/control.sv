import isa_shared::*;

module control #(parameter DATA_WIDTH = 32) (
    input wire clk,
    input wire rst_n
);

  // State machine for control logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 0;
      alu_a <= 0;
      alu_b <= 0;
      addr <= 0;
      data_in <= 0;
    end else begin
      // Control logic goes here (simplified example)
      pc <= pc + 1; // Increment PC by instruction size (assuming 4 bytes)
    end
  end


  // central
  reg [DATA_WIDTH-1:0] pc;
  wire [DATA_WIDTH-1:0] instruction;

  reg [DATA_WIDTH-1:0] alu_a;
  reg [DATA_WIDTH-1:0] alu_b;
  wire [DATA_WIDTH-1:0] alu_result;
  wire zero;
  wire carry;
  wire overflow;

  wire [2:0] alu_op;
  wire [2:0] imm_op;
  wire mem_write;
  wire reg_write;
  wire mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;

  reg [DATA_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] data_in;

  wire [DATA_WIDTH-1:0] data_out;

  wire [DATA_WIDTH-1:0] rs1_data;
  wire [DATA_WIDTH-1:0] rs2_data;
  reg [DATA_WIDTH-1:0] rd_data;

  wire [DATA_WIDTH-1:0] sign_extended_data;


  always @* begin
    alu_a = rs1_data;
    alu_b = (imm_op != IMM_NOP) ? sign_extended_data : rs2_data;

    addr   = alu_result; // always computed, used by load/store as address & pure alu ops as value
    data_in = rs2_data;  // value to write to memory (for stores)

    // default (don’t care)
    rd_data = 0;

    /*
    * is_load  => reg_write=1, mem_write=0, mem_read = 1, rd_data=data_out
    * is_store => reg_write=0, mem_write=1, mem_read = 0, rd_data=0
    * is_alu   => reg_write=1, mem_write=0, mem_read = 0, rd_data=alu_result
    */
    if (mem_read) begin
      rd_data = data_out; // load instruction, read from memory
    end else if (mem_write) begin
      rd_data = 0; // store instruction, no data to write back to register file
    end else if (reg_write) begin
      rd_data = alu_result; // ALU operation, write result back to register file
    end else begin
      rd_data = 0; // default case, no operation
    end
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
    .alu_op(alu_op),
    .imm_op(imm_op),
    .mem_write(mem_write),
    .reg_write(reg_write),
    .mem_read(mem_read),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd)
  );

  // data memory (ram)
  memory #(
    .DATA_WIDTH(DATA_WIDTH)
  ) data_memory_inst (
    .clk(clk),
    .addr(addr),
    .data_in(data_in),
    .mem_write(mem_write),
    .data_out(data_out)
  );

  // instruction memory (rom)
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_INIT("./memory/test_rom.hex")
  ) instruction_memory_inst (
    .clk(clk),
    .addr(pc),
    .data_in(0), // No write to instruction memory
    .mem_write('0), // No write to instruction memory
    .data_out(instruction)
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

  // sign extender
  signext #(
    .DATA_WIDTH(DATA_WIDTH)
  ) sign_extender_inst (
    .instruction(instruction),
    .imm_op(imm_op),
    .sign_extended_data(sign_extended_data)
  );

endmodule
