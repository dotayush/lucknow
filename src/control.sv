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
  reg [DATA_WIDTH-1:0] next_pc;
  wire [DATA_WIDTH-1:0] instruction;

  reg [DATA_WIDTH-1:0] alu_a;
  reg [DATA_WIDTH-1:0] alu_b;
  wire [DATA_WIDTH-1:0] alu_result;
  wire zero;
  wire carry;
  wire overflow;

  wire [2:0] f3;
  wire [6:0] f7;
  reg [4:0] alu_op;
  logic [4:0] sx_op;
  reg [4:0] sx_op2;
  wire [6:0] opcode;
  wire mem_write;
  wire reg_write;
  wire mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;
  reg [1:0] mem_access_type;

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
      next_pc <= 4;
    end else begin
      pc = next_pc; // warning: blocking assign, we want pc to update immediately.
      next_pc <= next_pc + 4; // warning: non-blocking assign, we want next_pc to be updated at the end of the current clock cycle.
    end
  end

  always @* begin
    /*
    * is_store => reg_write=0, mem_write=1, mem_read = 0, rd_data=0
    * is_alu   => reg_write=1, mem_write=0, mem_read = 0, rd_data=alu_result
    * is_load  => reg_write=1, mem_write=0, mem_read = 1, rd_data=data_out
    */
    if (!reg_write && mem_write && !mem_read) begin
      // STORE operations => data_memory[rs1_data + sign_extend(immediate)] = sign_extended(rs2_data);
      alu_op = ALU_ADD;
      alu_a = rs1_data; // rs1 is set by decoder, so rs1_data = register_mem[rs1]
      alu_b = sign_extended_data;
      addr = alu_result; // memory_address = alu_a + alu_b

      case (f3)
        S_SW: begin
          sx_op2 = SX_3100;
          mem_access_type = WORD_MEM_ACCESS;
        end
        S_SH: begin
          sx_op2 = SX_1500;
          mem_access_type = HALF_MEM_ACCESS;
        end
        S_SB: begin
          sx_op2 = SX_0700;
          mem_access_type = BYTE_MEM_ACCESS;
        end
      endcase

      unextended_data2 = rs2_data;
      data_in = sign_extended_data2; // data to write to memory
  end
    else if (reg_write && !mem_write && !mem_read) begin
      // neither load nor store operations.
      case (opcode)
        JAL: begin
          alu_op = ALU_ADD;
          rd_data = pc + 4; // JAL writes the next PC value to rd
          next_pc = pc + sign_extended_data;
        end
        JALR: begin
          alu_op = ALU_ADD;
          alu_a = rs1_data;
          alu_b = sign_extended_data;
          rd_data = pc + 4;
          next_pc = alu_result & ~32'd1; // JALR requires the least significant bit to be zero
        end
        BRANCH: begin
          alu_a = rs1_data;
          alu_b = rs2_data;
          case (f3)
            B_BEQ: begin
              alu_op = ALU_EQUALS;
              if (alu_result == 1) begin
                next_pc = pc + sign_extended_data;
              end
            end
            B_BNE: begin
              alu_op = ALU_NOT_EQUALS;
              if (alu_result == 1) begin
                next_pc = pc + sign_extended_data;
              end
            end
            B_BLT: begin
              alu_op = ALU_LT;
              if (alu_result == 1) begin
                next_pc = pc + sign_extended_data;
              end
            end
            B_BGE: begin
              alu_op = ALU_GE;
              if (alu_result == 1) begin
                next_pc = pc + sign_extended_data;
              end
            end
            B_BLTU: begin
              alu_op = ALU_LTU;
              if (alu_result == 1) begin
                next_pc = pc + sign_extended_data;
              end
            end
            B_BGEU: begin
              alu_op = ALU_GEU;
              if (alu_result == 1) begin
                next_pc = pc + sign_extended_data;
              end
            end
            default: begin
            end
          endcase
        end
        REGISTER_IMM: begin
          alu_a = rs1_data;
          alu_b = sign_extended_data;
          case (f3)
            RI_ADDI: begin
              alu_op = ALU_ADD;
              rd_data = alu_result;
            end
            RI_SLTI: begin
              alu_op = ALU_LT;
              rd_data = alu_result;
            end
            RI_SLTIU: begin
              alu_op = ALU_LTU;
              rd_data = alu_result;
            end
            RI_XORI: begin
              alu_op = ALU_XOR;
              rd_data = alu_result;
            end
            RI_ORI: begin
              alu_op = ALU_OR;
              rd_data = alu_result;
            end
            RI_ANDI: begin
              alu_op = ALU_AND;
              rd_data = alu_result;
            end
          endcase
        end
        default: begin
          if(next_pc[1:0] != 2'b00) begin
            $display("[%0t] error: next_pc %h is not aligned to 4 bytes", $time, next_pc);
            // TODO: implement trap
          end
          rd_data = alu_result;
        end
      endcase
    end
    else if (reg_write && !mem_write && mem_read) begin
      // LOAD operations => rd_data = data_memory[rs1_data + sign_extended(immediate)];
      alu_op = ALU_ADD;
      alu_a = rs1_data; // rs1 is set by decoeder, so rs1_data = register_mem[rs1]
      alu_b = sign_extended_data; //
      addr = alu_result; // memory_address = alu_a + alu_b

      case (f3)
        I_LW: begin
          sx_op2 = SX_3100;
          mem_access_type = WORD_MEM_ACCESS;
        end
        I_LH: begin
          sx_op2 = SX_1500;
          mem_access_type = HALF_MEM_ACCESS;
        end
        I_LB: begin
          sx_op2 = SX_0700;
          mem_access_type = BYTE_MEM_ACCESS;
        end
        I_LBU: begin
          sx_op2 = SXU_0700;
          mem_access_type = BYTE_MEM_ACCESS;
        end
        I_LHU: begin
          sx_op2 = SXU_1500;
          mem_access_type = HALF_MEM_ACCESS;
        end
        default: begin
          sx_op2 = SX_NOP; // no operation
          mem_access_type = WORD_MEM_ACCESS; // default access type
          unextended_data2 = '0; // default case, no operation
        end
      endcase

      unextended_data2 = data_out;
      rd_data = sign_extended_data2;
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
    .sx_op(sx_op),
    .opcode(opcode),
    .mem_write(mem_write),
    .reg_write(reg_write),
    .mem_read(mem_read),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .unextended_data(unextended_data)
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
