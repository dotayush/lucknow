`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module control #(
  parameter DATA_WIDTH = 32,
  parameter WORDS = 64,
  parameter IMEM_INIT = "./memory/test_rom.hex", // program image loaded into instruction memory
  parameter DMEM_INIT = "" // optional image preloaded into data memory
) (
    input wire clk,
    input wire rst_n
);

  // central
  reg [DATA_WIDTH-1:0] pc;
  reg [DATA_WIDTH-1:0] next_pc; // combinational, registered into pc at the clock edge
  wire [DATA_WIDTH-1:0] instruction;

  logic [DATA_WIDTH-1:0] alu_a;
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
  wire [1:0] fetch_error;

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
  wire [DATA_WIDTH-1:0] trap_vector;
  reg mret;
  reg [DATA_WIDTH-1:0] inst_next_pc; // where the instruction itself sends the pc, before traps
  reg env_trap; // ecall or ebreak
  reg [3:0] env_cause;
  reg illegal; // the instruction is not a valid RV32I/Zicsr instruction
  wire illegal_store = mem_write && (f3 != S_SW && f3 != S_SH && f3 != S_SB); // reserved store width, must not write
  wire csr_to_rd = (opcode == SYSTEM) && (f3 != SYS_ECALL_EBREAK); // csr instructions return the old csr value in rd

  logic [DATA_WIDTH-1:0] temp;

  // pc is the only state held here. everything else (regfile, csrfile, memory) holds its own.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 0;
    end else begin
      pc <= next_pc;
    end
  end

  // block-local copies of the signals that loop back into the block below (see its end).
  logic [DATA_WIDTH-1:0] l_alu_a;
  logic [DATA_WIDTH-1:0] l_alu_b;
  logic [4:0] l_alu_op;
  logic [4:0] l_sx_op2;
  logic [DATA_WIDTH-1:0] l_unextended_data2;
  logic [DATA_WIDTH-1:0] l_addr;
  logic [1:0] l_mem_access_type;

  always_comb begin
    /*
    * is_system => reg_write=0, mem_write=0, mem_read = 0, rd_data=0 (branch (not system but doesn't touch anything else), fence, ecall, break)
    * is_store => reg_write=0, mem_write=1, mem_read = 0, rd_data=0
    * is_alu   => reg_write=1, mem_write=0, mem_read = 0, rd_data=alu_result
    * is_load  => reg_write=1, mem_write=0, mem_read = 1, rd_data=data_out
    */
    l_alu_a = '0;
    l_alu_b = '0;
    l_alu_op = ALU_NOP;
    l_sx_op2 = SX_NOP;
    l_mem_access_type = WORD_MEM_ACCESS;
    l_addr = '0;
    data_in = '0;
    rd_data = '0;
    l_unextended_data2 = '0;
    inst_next_pc = pc + 4;
    csr_op = CSR_NOP;
    csr_wdata = '0;
    mret = 0;
    illegal = 0;
    env_trap = 0;
    env_cause = TRAP_NONE;
    temp = '0;

    if (!reg_write && mem_write && !mem_read) begin
      // STORE operations => data_memory[rs1_data + sign_extend(immediate)] = sign_extended(rs2_data);
      l_alu_op = ALU_ADD;
      l_alu_a = rs1_data; // rs1 is set by decoder, so rs1_data = register_mem[rs1]
      l_alu_b = sign_extended_data;
      l_addr = alu_result; // memory_address = l_alu_a + l_alu_b

      case (f3)
        S_SW: begin
          l_sx_op2 = SX_3100;
          l_mem_access_type = WORD_MEM_ACCESS;
        end
        S_SH: begin
          l_sx_op2 = SX_1500;
          l_mem_access_type = HALF_MEM_ACCESS;
        end
        S_SB: begin
          l_sx_op2 = SX_0700;
          l_mem_access_type = BYTE_MEM_ACCESS;
        end
        default: illegal = 1;
      endcase

      l_unextended_data2 = rs2_data;
      data_in = sign_extended_data2; // data to write to memory
    end
    else if (reg_write && !mem_write && !mem_read) begin
      // neither load nor store operations.
      case (opcode)
        JAL: begin
          l_alu_op = ALU_ADD;
          rd_data = pc + 4; // JAL writes the next PC value to rd
          inst_next_pc = pc + sign_extended_data;
        end
        JALR: begin
          l_alu_op = ALU_ADD;
          l_alu_a = rs1_data;
          l_alu_b = sign_extended_data;
          rd_data = pc + 4;
          inst_next_pc = alu_result & ~32'd1; // JALR requires the least significant bit to be zero
        end
        REGISTER_IMM: begin
          case (f3)
            RI_ADDI: begin
              l_alu_a = rs1_data;
              l_alu_b = sign_extended_data;
              l_alu_op = ALU_ADD;
              rd_data = alu_result;
            end
            RI_SLTI: begin
              l_alu_a = rs1_data;
              l_alu_b = sign_extended_data;
              l_alu_op = ALU_LT;
              rd_data = alu_result;
            end
            RI_SLTIU: begin
              l_alu_a = rs1_data;
              l_alu_b = sign_extended_data;
              l_alu_op = ALU_LTU;
              rd_data = alu_result;
            end
            RI_XORI: begin
              l_alu_a = rs1_data;
              l_alu_b = sign_extended_data;
              l_alu_op = ALU_XOR;
              rd_data = alu_result;
            end
            RI_ORI: begin
              l_alu_a = rs1_data;
              l_alu_b = sign_extended_data;
              l_alu_op = ALU_OR;
              rd_data = alu_result;
            end
            RI_ANDI: begin
              l_alu_a = rs1_data;
              l_alu_b = sign_extended_data;
              l_alu_op = ALU_AND;
              rd_data = alu_result;
            end
            SH_SLLI: begin
              if (f7 == 7'b0000000) begin
                l_alu_op = ALU_SLL;
                l_alu_a = rs1_data;
                l_alu_b = {27'b0, shift_amount}; // zero-extend shift amount to 32 bits
                rd_data = alu_result;
              end else begin
                illegal = 1; // the upper f7 bits are reserved, bit 25 would be shamt[5] which RV32 doesn't have
              end
            end
            SH_SRLI: begin
              case (f7)
                SH_SRLI_F7: begin
                  l_alu_op = ALU_SRL;
                  l_alu_a = rs1_data;
                  l_alu_b = {27'b0, shift_amount}; // zero-extend shift amount to 32 bits
                  rd_data = alu_result;
                end
                SH_SRAI_F7: begin
                  l_alu_op = ALU_SRA;
                  l_alu_a = rs1_data;
                  l_alu_b = {27'b0, shift_amount}; // zero-extend shift amount to 32 bits
                  rd_data = alu_result;
                end
                default: illegal = 1;
              endcase
            end
          endcase
        end
        REGISTER: begin
          case (f3)
            R_ADDSUB: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              case (f7)
                R_ADD_F7: begin
                  l_alu_op = ALU_ADD;
                  rd_data = alu_result;
                end
                R_SUB_F7: begin
                  l_alu_op = ALU_SUB;
                  rd_data = alu_result;
                end
                default: illegal = 1;
              endcase
            end
            R_SLL: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              l_alu_op = ALU_SLL;
              rd_data = alu_result;
            end
            R_SLT: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              l_alu_op = ALU_LT;
              rd_data = alu_result;
            end
            R_SLTU: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              l_alu_op = ALU_LTU;
              rd_data = alu_result;
            end
            R_XOR: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              l_alu_op = ALU_XOR;
              rd_data = alu_result;
            end
            R_SRL_SRA: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              case (f7)
                R_SRL_F7: begin
                  l_alu_op = ALU_SRL;
                  rd_data = alu_result;
                end
                R_SRA_F7: begin
                  l_alu_op = ALU_SRA;
                  rd_data = alu_result;
                end
                default: illegal = 1;
              endcase
            end
            R_OR: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              l_alu_op = ALU_OR;
              rd_data = alu_result;
            end
            R_AND: begin
              l_alu_a = rs1_data;
              l_alu_b = rs2_data;
              l_alu_op = ALU_AND;
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
        default: illegal = 1;
      endcase
    end
    else if (reg_write && !mem_write && mem_read) begin
      // LOAD operations => rd_data = data_memory[rs1_data + sign_extended(immediate)];
      l_alu_op = ALU_ADD;
      l_alu_a = rs1_data; // rs1 is set by decoeder, so rs1_data = register_mem[rs1]
      l_alu_b = sign_extended_data; //
      l_addr = alu_result; // memory_address = l_alu_a + l_alu_b

      case (f3)
        I_LW: begin
          l_sx_op2 = SX_3100;
          l_mem_access_type = WORD_MEM_ACCESS;
        end
        I_LH: begin
          l_sx_op2 = SX_1500;
          l_mem_access_type = HALF_MEM_ACCESS;
        end
        I_LB: begin
          l_sx_op2 = SX_0700;
          l_mem_access_type = BYTE_MEM_ACCESS;
        end
        I_LBU: begin
          l_sx_op2 = SXU_0700;
          l_mem_access_type = BYTE_MEM_ACCESS;
        end
        I_LHU: begin
          l_sx_op2 = SXU_1500;
          l_mem_access_type = HALF_MEM_ACCESS;
        end
        default: illegal = 1;
      endcase

      l_unextended_data2 = data_out;
      rd_data = sign_extended_data2;
    end
    else if (!reg_write && !mem_write && !mem_read) begin
      case (opcode)
        BRANCH: begin
          l_alu_a = rs1_data;
          l_alu_b = rs2_data;
          case (f3)
            B_BEQ: begin
              l_alu_op = ALU_EQUALS;
              if (alu_result == 1) begin
                inst_next_pc = pc + sign_extended_data;
              end
            end
            B_BNE: begin
              l_alu_op = ALU_NOT_EQUALS;
              if (alu_result == 1) begin
                inst_next_pc = pc + sign_extended_data;
              end
            end
            B_BLT: begin
              l_alu_op = ALU_LT;
              if (alu_result == 1) begin
                inst_next_pc = pc + sign_extended_data;
              end
            end
            B_BGE: begin
              l_alu_op = ALU_GE;
              if (alu_result == 1) begin
                inst_next_pc = pc + sign_extended_data;
              end
            end
            B_BLTU: begin
              l_alu_op = ALU_LTU;
              if (alu_result == 1) begin
                inst_next_pc = pc + sign_extended_data;
              end
            end
            B_BGEU: begin
              l_alu_op = ALU_GEU;
              if (alu_result == 1) begin
                inst_next_pc = pc + sign_extended_data;
              end
            end
            default: illegal = 1;
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
              case (unextended_data[11:0])
                SYS_FUN_ECALL: begin
                  env_trap = 1;
                  env_cause = TRAP_ECALL_M;
                end
                SYS_FUN_EBREAK: begin
                  env_trap = 1;
                  env_cause = TRAP_EBREAK;
                end
                SYS_FUN_MRET: begin
                  mret = 1;
                  inst_next_pc = csr_rdata; // MEPC
                end
                SYS_FUN_WFI: begin
                  // no interrupts exist, so waiting for one is a no-op.
                end
                default: illegal = 1;
              endcase
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
            default: illegal = 1;
          endcase
        end
        default: illegal = 1;
      endcase
    end
    else begin // should never occur
      illegal = 1;
    end


    // the operands/selects are published once, at the end. writing a default and then the real
    // value would glitch alu_op & co, which feed alu_result/data_out back into this block and
    // never settles in event driven simulators.
    alu_a = l_alu_a;
    alu_b = l_alu_b;
    alu_op = l_alu_op;
    sx_op2 = l_sx_op2;
    unextended_data2 = l_unextended_data2;
    addr = l_addr;
    mem_access_type = l_mem_access_type;
  end

  // trap selection and the final next pc. kept apart from the block above because mem_error depends
  // on the address that block drives.
  always_comb begin
    trap = 0;
    trap_cause = TRAP_NONE;
    trap_value = '0;
    next_pc = inst_next_pc;

    // the first match wins, an instruction can only raise one.
    if (fetch_error != NO_MEM_ERROR) begin
      trap = 1;
      trap_cause = (fetch_error == OUT_OF_BOUNDS) ? TRAP_INST_ACCESS_FAULT : TRAP_INST_ADDR_MISALIGNED;
      trap_value = pc;
    end
    else if (env_trap) begin
      trap = 1;
      trap_cause = env_cause;
    end
    else if (illegal) begin
      trap = 1;
      trap_cause = TRAP_ILLEGAL_INSTRUCTION;
      trap_value = instruction;
    end
    else if (mem_error != NO_MEM_ERROR) begin
      trap = 1;
      trap_value = addr;
      if (mem_read) begin
        trap_cause = (mem_error == OUT_OF_BOUNDS) ? TRAP_LOAD_ACCESS_FAULT : TRAP_LOAD_ADDR_MISALIGNED;
      end else begin
        trap_cause = (mem_error == OUT_OF_BOUNDS) ? TRAP_STORE_ACCESS_FAULT : TRAP_STORE_ADDR_MISALIGNED;
      end
    end
    else if (inst_next_pc[1:0] != 2'b00) begin // jump, taken branch or mret to a target that isn't 4 byte aligned
      trap = 1;
      trap_cause = TRAP_INST_ADDR_MISALIGNED;
      trap_value = inst_next_pc;
    end

    if (trap) begin
      next_pc = trap_vector;
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
    .MEM_INIT(DMEM_INIT),
    .WORDS(WORDS)
  ) data_memory_inst (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .data_in(data_in),
    .mem_read(mem_read),
    .mem_write(mem_write && !illegal_store),
    .data_out(data_out),
    .mem_access_type(mem_access_type), // Use the access type from decoder
    .mem_error(mem_error)
  );

  // instruction memory (rom)
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_INIT(IMEM_INIT),
    .WORDS(WORDS)
  ) instruction_memory_inst (
    .clk(clk),
    .rst_n(rst_n),
    .addr(pc),
    .data_in(0), // No write to instruction memory
    .mem_read('1), // Always read from instruction memory
    .mem_write('0), // No write to instruction memory
    .data_out(instruction),
    .mem_access_type(isa_shared::WORD_MEM_ACCESS),
    .mem_error(fetch_error)
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
    .reg_write((reg_write || csr_to_rd) && !trap), // a trapping instruction does not retire
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
    .trap_pc(pc),
    .mret(mret),
    .trap_vector(trap_vector)
  );

endmodule
