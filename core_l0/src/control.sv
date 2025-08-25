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
  wire [1:0] mem_error;
  wire [1:0] mem_error2;

  wire [DATA_WIDTH-1:0] rs1_data;
  wire [DATA_WIDTH-1:0] rs2_data;
  reg [DATA_WIDTH-1:0] rd_data;

  logic [DATA_WIDTH-1:0] unextended_data;
  logic [DATA_WIDTH-1:0] unextended_data2; // not driven by decoder but by control itself.
  logic [DATA_WIDTH-1:0] sign_extended_data;
  logic [DATA_WIDTH-1:0] sign_extended_data2;
  wire [4:0] shift_amount;

  wire [11:0] csr_addr;
  reg [DATA_WIDTH-1:0] csr_wdata;
  wire [DATA_WIDTH-1:0] csr_rdata;
  reg [1:0] csr_op;
  reg trap;
  reg [3:0] trap_cause;
  reg [DATA_WIDTH-1:0] trap_value;
  reg [DATA_WIDTH-1:0] trap_pc;
  wire trap_handled;
  wire [DATA_WIDTH-1:0] trap_target_pc;
  reg manual_pc_set;

  logic [DATA_WIDTH-1:0] temp;
  localparam int ADDR_WIDTH = $clog2(WORDS);

  // state machine for control logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 0;
      alu_a <= 0;
      alu_b <= 0;
      alu_op <= ALU_NOP;
      sx_op2 <= SX_NOP;
      mem_access_type <= WORD_MEM_ACCESS;
      addr <= 0;
      data_in <= 0;
      rd_data <= 0;
      next_pc <= 4;
      trap <= 0;
      trap_cause <= TRAP_NONE;
      trap_value <= 0;
      trap_pc <= 0;
      csr_wdata <= 0;
      csr_op <= CSR_NOP;
      temp <= 0;
      manual_pc_set <= 0;
    end else begin
        pc = next_pc; // warning: blocking assign, we want pc to update immediately. DO NOT UPDATE PC ANYWHERE ELSE.

        // if next_pc is manually set (by branch, jump, trap), do not increment it by 4.
        if (!manual_pc_set) begin
          next_pc <= next_pc + 4; // warning: non-blocking assign, we want next_pc to be updated at the end of the current clock cycle.
          manual_pc_set <= 0;
        end
        // handle traps
        if (trap_handled) begin
          next_pc <= trap_target_pc;
          trap <= 0;
          trap_cause <= TRAP_NONE;
          trap_value <= 0;
          trap_pc <= 0;
          $display("[%0t] info: trap handled, jumping to trap handler at %h", $time, trap_target_pc);
        end

        case (mem_error)
          NO_MEM_ERROR: begin
            // do nothing
          end
          ADDRESS_MISALIGNED: begin
            manual_pc_set <= 1;
            trap <= 1;
            trap_cause <= TRAP_MEMORY_ADDR_MISALIGNED;
            trap_value <= addr;
            trap_pc <= pc;
          end
          OUT_OF_BOUNDS: begin
            manual_pc_set <= 1;
            trap <= 1;
            trap_cause <= TRAP_MEMORY_ADDR_MISALIGNED;
            trap_value <= addr;
            trap_pc <= pc;
          end
          default: begin
          end
        endcase
    end
  end

  always @* begin
    /*
    * is_system => reg_write=0, mem_write=0, mem_read = 0, rd_data=0 (branch (not system but doesn't touch anything else), fence, ecall, break)
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
          manual_pc_set = 1;
        end
        JALR: begin
          alu_op = ALU_ADD;
          alu_a = rs1_data;
          alu_b = sign_extended_data;
          rd_data = pc + 4;
          next_pc = alu_result & ~32'd1; // JALR requires the least significant bit to be zero
          manual_pc_set = 1;
        end
        REGISTER_IMM: begin
          case (f3)
            RI_ADDI: begin
              alu_a = rs1_data;
              alu_b = sign_extended_data;
              alu_op = ALU_ADD;
              rd_data = alu_result;
            end
            RI_SLTI: begin
              alu_a = rs1_data;
              alu_b = sign_extended_data;
              alu_op = ALU_LT;
              rd_data = alu_result;
            end
            RI_SLTIU: begin
              alu_a = rs1_data;
              alu_b = sign_extended_data;
              alu_op = ALU_LTU;
              rd_data = alu_result;
            end
            RI_XORI: begin
              alu_a = rs1_data;
              alu_b = sign_extended_data;
              alu_op = ALU_XOR;
              rd_data = alu_result;
            end
            RI_ORI: begin
              alu_a = rs1_data;
              alu_b = sign_extended_data;
              alu_op = ALU_OR;
              rd_data = alu_result;
            end
            RI_ANDI: begin
              alu_a = rs1_data;
              alu_b = sign_extended_data;
              alu_op = ALU_AND;
              rd_data = alu_result;
            end
            SH_SLLI: begin
              alu_op = ALU_SLL;
              alu_a = rs1_data;
              alu_b = {27'b0, shift_amount}; // zero-extend shift amount to 32 bits
              rd_data = alu_result;
            end
            SH_SRLI: begin
              case (f7)
                SH_SRLI_F7: begin
                  alu_op = ALU_SRL;
                  alu_a = rs1_data;
                  alu_b = {27'b0, shift_amount}; // zero-extend shift amount to 32 bits
                  rd_data = alu_result;
                end
                SH_SRAI_F7: begin
                  alu_op = ALU_SRA;
                  alu_a = rs1_data;
                  alu_b = {27'b0, shift_amount}; // zero-extend shift amount to 32 bits
                  rd_data = alu_result;
                end
                default: begin
                end
              endcase
            end
          endcase
        end
        REGISTER: begin
          case (f3)
            R_ADDSUB: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              case (f7)
                R_ADD_F7: begin
                  alu_op = ALU_ADD;
                  rd_data = alu_result;
                end
                R_SUB_F7: begin
                  alu_op = ALU_SUB;
                  rd_data = alu_result;
                end
              endcase
            end
            R_SLL: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              alu_op = ALU_SLL;
              rd_data = alu_result;
            end
            R_SLT: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              alu_op = ALU_LT;
              rd_data = alu_result;
            end
            R_SLTU: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              alu_op = ALU_LTU;
              rd_data = alu_result;
            end
            R_XOR: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              alu_op = ALU_XOR;
              rd_data = alu_result;
            end
            R_SRL_SRA: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              case (f7)
                R_SRL_F7: begin
                  alu_op = ALU_SRL;
                  rd_data = alu_result;
                end
                R_SRA_F7: begin
                  alu_op = ALU_SRA;
                  rd_data = alu_result;
                end
                default: begin
                end
              endcase
            end
            R_OR: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              alu_op = ALU_OR;
              rd_data = alu_result;
            end
            R_AND: begin
              alu_a = rs1_data;
              alu_b = rs2_data;
              alu_op = ALU_AND;
              rd_data = alu_result;
            end
          endcase
        end
        LUI: begin
          rd_data = sign_extended_data;
        end
        AUIPC: begin
          rd_data = pc + sign_extended_data;
        end
        default: begin
          if(next_pc[1:0] != 2'b00) begin
            $display("[%0t] error: next_pc %h is not aligned to 4 bytes", $time, next_pc);

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
    else if (!reg_write && !mem_write && !mem_read) begin
      case (opcode)
        BRANCH: begin
          alu_a = rs1_data;
          alu_b = rs2_data;
          manual_pc_set = 1;
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
        FENCE: begin
          // FENCE is a no-op in this implementation.
          // It is used when synchronizing memory operations in a multi-core
          // system, out of order execution, or memory-mapped I/O. Bascially,
          // they must be ready to accept the next instruction. In this
          // core, all instructions are executed in order and within a single
          // cycle, so FENCE is not needed.
        end
        SYSTEM: begin
          case (f3)
            SYS_ECALL_EBREAK: begin
              manual_pc_set = 1;
              if (unextended_data == 32'b0) begin
                trap = 1;
                trap_cause = TRAP_ECALL_M;
                trap_value = 0; // not used for ECALL
                trap_pc = pc;
              end
              else if (unextended_data == 32'b1) begin
                trap = 1;
                trap_cause = TRAP_EBREAK;
                trap_value = 0;
                trap_pc = pc;
              end
            end
            SYS_CSRRW: begin
              // always write, but only read if rd != x0
              if (rd != 'b0) begin
                temp = csr_rdata;
                rd_data = temp;
              end
              csr_op = CSR_WRITE;
              csr_wdata = rs1_data;
            end
            SYS_CSRRS: begin
              // always read, but only write if rs1 != x0
              temp = csr_rdata;
              rd_data = temp;
              if (rs1 != 'b0) begin
                csr_op = CSR_SET;
                csr_wdata = rs1_data;
              end
            end
            SYS_CSRRC: begin
              // always read, but only write if rs1 != x0
              temp = csr_rdata;
              rd_data = temp;
              if (rs1 != 'b0) begin
                csr_op = CSR_CLEAR;
                csr_wdata = rs1_data;
              end
            end
            SYS_CSRRWI: begin
              // always write, but only read if rd != x0
              if (rd != 'b0) begin
                temp = csr_rdata;
                rd_data = temp;
              end
              csr_op = CSR_WRITE;
              csr_wdata = sign_extended_data;
            end
            SYS_CSRRSI: begin
              // always read, but only write if sign_extended_data != 0
              temp = csr_rdata;
              rd_data = temp;
              if (sign_extended_data != 'b0) begin
                csr_op = CSR_SET;
                csr_wdata = sign_extended_data;
              end
            end
            SYS_CSRRCI: begin
              // always read, but only write if sign_extended_data != 0
              temp = csr_rdata;
              rd_data = temp;
              if (sign_extended_data != 'b0) begin
                csr_op = CSR_CLEAR;
                csr_wdata = sign_extended_data;
              end
            end
          endcase
        end
        default: begin
        end
      endcase
    end
    else begin // should never occur
      manual_pc_set = 1;
      trap = 1;
      trap_cause = TRAP_ILLEGAL_INSTRUCTION;
      trap_value = instruction;
      trap_pc = pc;
      rd_data = 0;
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
    .unextended_data(unextended_data),
    .shift_amount(shift_amount),
    .csr_addr(csr_addr)
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
    .mem_access_type(mem_access_type), // Use the access type from decoder
    .mem_error(mem_error)
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
    .mem_access_type(isa_shared::WORD_MEM_ACCESS),
    .mem_error(mem_error2)
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

  csrfile #(
    .DATA_WIDTH(DATA_WIDTH),
    .COUNT(4096)
  ) csrfile_inst (
    .clk(clk),
    .rst_n(rst_n),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .csr_op(csr_op),
    .trap(trap),
    .trap_cause(trap_cause),
    .trap_value(trap_value),
    .trap_pc(trap_pc),
    .trap_handled(trap_handled),
    .trap_target_pc(trap_target_pc)
  );

endmodule
