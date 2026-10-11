`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module control #(
  parameter DATA_WIDTH = 32,
  parameter RESET_VECTOR = 32'h0000_1000 // boot rom
) (
    // global signals
    input wire clk,
    input wire rst_n,

    // core id
    input wire [4:0] core_id,

    // instruction port. a fetch is always requested, imem_data/imem_error are valid when imem_ready is high.
    output wire [DATA_WIDTH-1:0] imem_addr,
    input wire [DATA_WIDTH-1:0] imem_data,
    input wire imem_ready,
    input wire [1:0] imem_error,

    // data port. a request (mem_read or mem_write) is held until mem_ready, the transfer
    // completes on the clock edge where request and mem_ready are both high. mem_error is
    // only looked at when mem_ready is high. requests are not issued while the instruction
    // itself is not available yet, so a transfer happens exactly once per instruction.
    output wire mem_read, // load in progress
    output wire mem_write, // store in progress (never set for a store that traps)
    output logic [1:0] mem_access_type,
    output wire [DATA_WIDTH-1:0] mem_addr,
    output wire [DATA_WIDTH-1:0] mem_data_out, // data to put in mem
    input wire [DATA_WIDTH-1:0] mem_data_in, // data to take from mem
    input wire mem_ready,
    input wire [1:0] mem_error,

    // interrupts and time, from the clint
    input wire irq_software,
    input wire irq_timer,
    input wire irq_external,
    input wire [63:0] time_value
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
  wire dec_mem_write;
  wire reg_write;
  wire dec_mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;

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
  wire [4:0] shift_amount;

  wire [11:0] csr_addr;
  reg [DATA_WIDTH-1:0] csr_wdata;
  wire [DATA_WIDTH-1:0] csr_rdata;
  reg [1:0] csr_op;
  reg trap;
  reg trap_interrupt;
  reg [3:0] trap_cause;
  reg [DATA_WIDTH-1:0] trap_value;
  wire [DATA_WIDTH-1:0] trap_vector;
  wire mtvec_vectored;
  wire irq_pending;
  wire [3:0] irq_code;
  reg mret;
  reg [DATA_WIDTH-1:0] inst_next_pc; // where the instruction itself sends the pc, before traps
  reg env_trap; // ecall or ebreak
  reg [3:0] env_cause;
  reg illegal; // the instruction is not a valid RV32I/Zicsr instruction
  wire illegal_store = dec_mem_write && (f3 != S_SW && f3 != S_SH && f3 != S_SB); // reserved store width, must not write
  wire illegal_load = dec_mem_read && (f3 != I_LW && f3 != I_LH && f3 != I_LB && f3 != I_LBU && f3 != I_LHU); // reserved load width

  // a extension. lr is one read, sc is one write (or nothing when it fails), the amos are a read
  // followed by a write of the new value, two transfers of the same instruction.
  wire is_amo = (opcode == AMO);
  wire [4:0] f5 = f7[6:2];
  wire is_lr = is_amo && (f5 == AMO_LR);
  wire is_sc = is_amo && (f5 == AMO_SC);
  wire is_rmw = is_amo && (f5 == AMO_SWAP || f5 == AMO_ADD || f5 == AMO_XOR || f5 == AMO_AND || f5 == AMO_OR ||
                           f5 == AMO_MIN || f5 == AMO_MAX || f5 == AMO_MINU || f5 == AMO_MAXU);
  wire illegal_amo = is_amo && (f3 != 3'b010 || !(is_lr || is_sc || is_rmw) || (is_lr && rs2 != 0));
  reg amo_phase; // read-modify-write: 0 = reading the old value, 1 = writing the new one
  reg [DATA_WIDTH-1:0] amo_old; // the value read in phase 0
  reg resv_valid; // lr/sc reservation, one word
  reg [DATA_WIDTH-1:0] resv_addr;
  wire sc_ok = is_sc && resv_valid && (resv_addr == rs1_data);
  wire amo_misaligned = (rs1_data[1:0] != 2'b00); // a misaligned sc must fault even when it would fail

  // an interrupt is taken between instructions: in front of this one, which then does nothing at all
  // (no transfer, no write back, mepc is its own pc). that includes the second half of an amo, whose
  // read has no effect, so the whole amo runs again after mret.
  wire irq_take = irq_pending && imem_ready;
  wire req_read = !irq_take && (is_amo ? (!illegal_amo && (is_lr || (is_rmw && !amo_phase))) : (dec_mem_read && !illegal_load));
  wire req_write = !irq_take && (is_amo ? (!illegal_amo && ((is_sc && (sc_ok || amo_misaligned)) || (is_rmw && amo_phase)))
                                        : (dec_mem_write && !illegal_store));
  wire data_req = (req_read || req_write) && imem_ready;
  // an amo read that came back fine is not the end of the instruction, the write is still to do
  wire rmw_next = !irq_take && is_rmw && !illegal_amo && !amo_phase && imem_ready && mem_ready && (mem_error == NO_MEM_ERROR);
  // the whole core waits (pc, registers, csrs, memory are not updated) until the instruction and its data are there
  wire stall = !imem_ready || (data_req && !mem_ready) || rmw_next;
  wire csr_to_rd = (opcode == SYSTEM) && (f3 != SYS_ECALL_EBREAK); // csr instructions return the old csr value in rd

  logic [DATA_WIDTH-1:0] temp;

  // the data side of the core is a plain port, the memory system lives outside
  assign data_out = mem_data_in;
  assign mem_addr = addr;
  assign mem_data_out = data_in;
  assign mem_read = req_read && imem_ready;
  assign mem_write = req_write && imem_ready;

  // the instruction side is a plain port too
  assign instruction = imem_data;
  assign imem_addr = pc;

  // pc is the only state held here. everything else (regfile, csrfile, memory) holds its own.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= RESET_VECTOR;
    end else begin
      pc <= next_pc;
    end
  end

  // atomics state: which half of a read-modify-write is going on, and the reservation
  wire store_like = is_amo ? (is_sc || is_rmw) : dec_mem_write; // anything that may write memory kills a reservation
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      amo_phase <= 0;
      amo_old <= 0;
      resv_valid <= 0;
      resv_addr <= 0;
    end else begin
      if (rmw_next) begin
        amo_phase <= 1;
        amo_old <= mem_data_in;
      end
      else if (!stall) begin
        amo_phase <= 0;
      end

      if (!stall) begin
        if (trap || mret || store_like) resv_valid <= 0;
        if (is_lr && !illegal_amo && !trap) begin
          resv_valid <= 1;
          resv_addr <= rs1_data;
        end
      end
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

  always @* begin
    /*
    * is_system => reg_write=0, dec_mem_write=0, dec_mem_read = 0, rd_data=0 (branch (not system but doesn't touch anything else), fence, ecall, break)
    * is_store => reg_write=0, dec_mem_write=1, dec_mem_read = 0, rd_data=0
    * is_alu   => reg_write=1, dec_mem_write=0, dec_mem_read = 0, rd_data=alu_result
    * is_load  => reg_write=1, dec_mem_write=0, dec_mem_read = 1, rd_data=data_out
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

    if (is_amo) begin
      // ATOMICS => address is rs1 as is
      l_addr = rs1_data;
      l_mem_access_type = WORD_MEM_ACCESS;
      if (illegal_amo) begin
        illegal = 1;
      end
      else if (is_lr) begin
        rd_data = data_out;
      end
      else if (is_sc) begin
        data_in = rs2_data;
        rd_data = sc_ok ? 32'd0 : 32'd1; // 0 = success
      end
      else begin
        // read-modify-write: rd gets the old value, memory gets the new one in phase 1
        l_alu_a = amo_old;
        l_alu_b = rs2_data;
        rd_data = amo_old;
        case (f5)
          AMO_SWAP: data_in = rs2_data;
          AMO_ADD: begin
            l_alu_op = ALU_ADD;
            data_in = alu_result;
          end
          AMO_XOR: begin
            l_alu_op = ALU_XOR;
            data_in = alu_result;
          end
          AMO_AND: begin
            l_alu_op = ALU_AND;
            data_in = alu_result;
          end
          AMO_OR: begin
            l_alu_op = ALU_OR;
            data_in = alu_result;
          end
          AMO_MIN: begin
            l_alu_op = ALU_LT;
            data_in = (alu_result == 1) ? amo_old : rs2_data;
          end
          AMO_MAX: begin
            l_alu_op = ALU_GE;
            data_in = (alu_result == 1) ? amo_old : rs2_data;
          end
          AMO_MINU: begin
            l_alu_op = ALU_LTU;
            data_in = (alu_result == 1) ? amo_old : rs2_data;
          end
          AMO_MAXU: begin
            l_alu_op = ALU_GEU;
            data_in = (alu_result == 1) ? amo_old : rs2_data;
          end
          default: begin
          end
        endcase
      end
    end
    else if (!reg_write && dec_mem_write && !dec_mem_read) begin
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
    else if (reg_write && !dec_mem_write && !dec_mem_read) begin
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
          if (f7 == R_MULDIV_F7) begin
            l_alu_a = rs1_data;
            l_alu_b = rs2_data;
            case (f3)
              RM_MUL: begin
                l_alu_op = ALU_MUL;
                rd_data = alu_result;
              end
              RM_MULH: begin
                l_alu_op = ALU_MULH;
                rd_data = alu_result;
              end
              RM_MULHSU: begin
                l_alu_op = ALU_MULHSU;
                rd_data = alu_result;
              end
              RM_MULHU: begin
                l_alu_op = ALU_MULHU;
                rd_data = alu_result;
              end
              RM_DIV: begin
                l_alu_op = ALU_DIV;
                rd_data = alu_result;
              end
              RM_DIVU: begin
                l_alu_op = ALU_DIVU;
                rd_data = alu_result;
              end
              RM_REM: begin
                l_alu_op = ALU_REM;
                rd_data = alu_result;
              end
              RM_REMU: begin
                l_alu_op = ALU_REMU;
                rd_data = alu_result;
              end
            endcase
          end
          else begin
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
    else if (reg_write && !dec_mem_write && dec_mem_read) begin
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
    else if (!reg_write && !dec_mem_write && !dec_mem_read) begin
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
                  // waiting for an interrupt is allowed to be a no-op, software loops around it.
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
  always @* begin
    trap = 0;
    trap_interrupt = 0;
    trap_cause = TRAP_NONE;
    trap_value = '0;
    next_pc = inst_next_pc;

    // the first match wins, an instruction can only raise one. interrupts come before everything.
    if (irq_take) begin
      trap = 1;
      trap_interrupt = 1;
      trap_cause = irq_code;
    end
    else if (imem_error != NO_MEM_ERROR) begin
      trap = 1;
      trap_cause = (imem_error == OUT_OF_BOUNDS) ? TRAP_INST_ACCESS_FAULT : TRAP_INST_ADDR_MISALIGNED;
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
      if (is_amo ? is_lr : dec_mem_read) begin // sc and amos report as stores
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
      if (trap_interrupt && mtvec_vectored) next_pc = trap_vector + {26'b0, trap_cause, 2'b00};
    end

    // nothing about this instruction is final until its fetch and data are in
    if (stall) begin
      trap = 0;
      next_pc = pc;
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
    .mem_write(dec_mem_write),
    .reg_write(reg_write),
    .mem_read(dec_mem_read),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .unextended_data(unextended_data),
    .shift_amount(shift_amount),
    .csr_addr(csr_addr)
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
    .reg_write((reg_write || csr_to_rd) && !trap && !stall), // a trapping or waiting instruction does not retire
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
    .csr_op(stall ? CSR_NOP : csr_op),
    .trap(trap),
    .trap_interrupt(trap_interrupt),
    .trap_cause(trap_cause),
    .trap_value(trap_value),
    .trap_pc(pc),
    .mret(mret && !stall),
    .trap_vector(trap_vector),
    .mtvec_vectored(mtvec_vectored),
    .irq_software(irq_software),
    .irq_timer(irq_timer),
    .irq_external(irq_external),
    .irq_pending(irq_pending),
    .irq_code(irq_code),
    .time_value(time_value),
    .retire(!stall && !trap)
  );

endmodule
