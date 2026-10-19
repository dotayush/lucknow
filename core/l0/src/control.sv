`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

// the l0 core without memories: instruction fetch, data access and their error codes go through ports,
// so it can be dropped into a design that owns the memory (an sram, a bus, a testbench).
// memory answers in the same cycle (combinational read); a write lands on the clock edge.
// `control` in l0.sv is this core plus the two memories of memory.sv.
module l0_core #(
  parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst_n,

    // instruction fetch: always a word read at pc
    output wire [DATA_WIDTH-1:0] imem_addr,
    input  wire [DATA_WIDTH-1:0] imem_data,
    input  wire [1:0]            imem_err,   // isa_shared NO_MEM_ERROR / OUT_OF_BOUNDS / ADDRESS_MISALIGNED

    // data access: a load, or a store with the byte/half/word size in dmem_size
    output wire [DATA_WIDTH-1:0] dmem_addr,
    output wire [DATA_WIDTH-1:0] dmem_wdata,
    output wire [1:0]            dmem_size,  // isa_shared BYTE / HALF / WORD_MEM_ACCESS
    output wire                  dmem_read,
    output wire                  dmem_write, // never set for a reserved store width
    input  wire [DATA_WIDTH-1:0] dmem_rdata, // the addressed lane, zero-extended, like memory.sv
    input  wire [1:0]            dmem_err
);

  // central
  reg [DATA_WIDTH-1:0] pc;
  reg [DATA_WIDTH-1:0] next_pc; // combinational, registered into pc at the clock edge
  wire [DATA_WIDTH-1:0] instruction = imem_data;

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
  reg [DATA_WIDTH-1:0] data_in;
  wire [DATA_WIDTH-1:0] data_out = dmem_rdata;
  wire [1:0] mem_error = dmem_err;
  wire [1:0] fetch_error = imem_err;

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
  reg trap_early; // trap without the taken-branch case: decode, fetch and memory errors, jump targets
  reg trap_pre;   // trap_early without the memory error: known from the instruction alone
  reg mem_fault;  // a load or store the memory refuses, and nothing earlier trapped: the latest of the early traps
  reg br_taken; // a conditional branch is taken: the only decision that comes from the late alu compare
  wire [DATA_WIDTH-1:0] br_target = pc + sign_extended_data; // jal and taken branches go here
  // load and store addresses and the jalr target have their own adder, off the alu's operand and result muxes: the address is
  // the longest thing between the instruction and the memory
  // its offset comes straight from the instruction bits: a store (opcode[6:5] == 01) has the low five bits in [11:7], loads and
  // jalr in [24:20]. no decode in front of the adder.
  wire [DATA_WIDTH-1:0] addr_off = {{20{instruction[31]}}, instruction[31:25], (!instruction[6] && instruction[5]) ? instruction[11:7] : instruction[24:20]};
  wire [DATA_WIDTH-1:0] addr_sum = rs1_data + addr_off;
  wire [DATA_WIDTH-1:0] addr = addr_sum; // not selected by the instruction: memory only looks at it while mem_read or mem_write is set
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
  logic [1:0] l_mem_access_type;

  always @* begin
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
    data_in = '0;
    rd_data = '0;
    l_unextended_data2 = '0;
    inst_next_pc = pc + 4;
    br_taken = 0;
    csr_op = CSR_NOP;
    csr_wdata = '0;
    mret = 0;
    illegal = 0;
    env_trap = 0;
    env_cause = TRAP_NONE;
    temp = '0;

    if (!reg_write && mem_write && !mem_read) begin
      // STORE operations => data_memory[rs1_data + sign_extend(immediate)] = sign_extended(rs2_data);

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
          inst_next_pc = br_target;
        end
        JALR: begin
          rd_data = pc + 4;
          inst_next_pc = addr_sum & ~32'd1; // JALR requires the least significant bit to be zero
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
                br_taken = 1;
              end
            end
            B_BNE: begin
              l_alu_op = ALU_NOT_EQUALS;
              if (alu_result == 1) begin
                br_taken = 1;
              end
            end
            B_BLT: begin
              l_alu_op = ALU_LT;
              if (alu_result == 1) begin
                br_taken = 1;
              end
            end
            B_BGE: begin
              l_alu_op = ALU_GE;
              if (alu_result == 1) begin
                br_taken = 1;
              end
            end
            B_BLTU: begin
              l_alu_op = ALU_LTU;
              if (alu_result == 1) begin
                br_taken = 1;
              end
            end
            B_BGEU: begin
              l_alu_op = ALU_GEU;
              if (alu_result == 1) begin
                br_taken = 1;
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
    mem_access_type = l_mem_access_type;
  end

  // trap selection and the final next pc. kept apart from the block above because mem_error depends
  // on the address that block drives.
  //
  // the trap is split by when it is known. everything except a taken branch to a misaligned target comes from the
  // decode, the fetch and memory errors or the low bits of a jump target, which are known early. only the branch
  // decision (the full width compare in the alu) is late, so it is kept out of what the register file and most
  // csrs see: trap_early is the trap without it, and a taken branch writes neither a register nor a csr.
  // the memory error comes back from outside, after the address, so it is kept apart too (mem_fault) and enters the write
  // enables as the last term; synthesis treats every input as arriving at time zero and would otherwise bury it.
  logic [3:0] cause_early;
  logic [DATA_WIDTH-1:0] value_early;
  logic late_misaligned; // taken branch to a target that isn't 4 byte aligned, and nothing else trapped first

  always @* begin
    trap_early = 0;
    trap_pre = 0;
    mem_fault = 0;
    cause_early = TRAP_NONE;
    value_early = '0;

    // the first match wins, an instruction can only raise one. the misaligned jump or mret target is last,
    // as it was when branches were part of it.
    if (fetch_error != NO_MEM_ERROR) begin
      trap_pre = 1;
      cause_early = (fetch_error == OUT_OF_BOUNDS) ? TRAP_INST_ACCESS_FAULT : TRAP_INST_ADDR_MISALIGNED;
      value_early = pc;
    end
    else if (env_trap) begin
      trap_pre = 1;
      cause_early = env_cause;
    end
    else if (illegal) begin
      trap_pre = 1;
      cause_early = TRAP_ILLEGAL_INSTRUCTION;
      value_early = instruction;
    end
    else if (mem_error != NO_MEM_ERROR) begin
      mem_fault = 1;
      value_early = addr;
      if (mem_read) begin
        cause_early = (mem_error == OUT_OF_BOUNDS) ? TRAP_LOAD_ACCESS_FAULT : TRAP_LOAD_ADDR_MISALIGNED;
      end else begin
        cause_early = (mem_error == OUT_OF_BOUNDS) ? TRAP_STORE_ACCESS_FAULT : TRAP_STORE_ADDR_MISALIGNED;
      end
    end
    else if (inst_next_pc[1:0] != 2'b00) begin // jal, jalr or mret to a target that isn't 4 byte aligned
      trap_pre = 1;
      cause_early = TRAP_INST_ADDR_MISALIGNED;
      value_early = inst_next_pc;
    end

    trap_early = trap_pre || mem_fault;

    late_misaligned = !trap_early && br_taken && (br_target[1:0] != 2'b00);
    trap = trap_early || late_misaligned;
    trap_cause = late_misaligned ? TRAP_INST_ADDR_MISALIGNED : cause_early;
    trap_value = late_misaligned ? br_target : value_early;

    // the late decision is the last mux: a taken branch goes to its target, or to the handler when that is misaligned
    if (trap_early) next_pc = trap_vector;
    else if (br_taken) next_pc = (br_target[1:0] != 2'b00) ? trap_vector : br_target;
    else next_pc = inst_next_pc;
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

  assign imem_addr = pc;
  assign dmem_addr = addr;
  assign dmem_wdata = data_in;
  assign dmem_size = mem_access_type;
  assign dmem_read = mem_read;
  assign dmem_write = mem_write && !illegal_store;

  // register file
  regfile #(
    .DATA_WIDTH(DATA_WIDTH)
  ) regfile_inst (
    .clk(clk),
    .rst_n(rst_n),
    .rs1(instruction[19:15]), // the register file reads whatever the fields say; the decoder's rs1/rs2 (zero when unused) would put decode in front of the read
    .rs2(instruction[24:20]),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .reg_write(((reg_write || csr_to_rd) && !trap_pre) && !mem_fault), // a trapping instruction does not retire (a taken branch writes nothing); the memory error is the last term
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
    .DATA_WIDTH(DATA_WIDTH)
  ) csrfile_inst (
    .clk(clk),
    .rst_n(rst_n),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .csr_op(csr_op),
    .trap(trap),
    .trap_pre(trap_pre),
    .mem_fault(mem_fault),
    .trap_cause(trap_cause),
    .trap_value(trap_value),
    .trap_pc(pc),
    .mret(mret),
    .trap_vector(trap_vector)
  );

endmodule
