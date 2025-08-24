`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module decoder #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] instruction,

    output reg [2:0] f3,
    output reg [6:0] f7,
    output logic [4:0] sx_op,
    output reg [6:0] opcode,
    output reg mem_write,
    output reg reg_write,
    output reg mem_read,
    output reg [$clog2(DATA_WIDTH)-1:0] rs1,
    output reg [$clog2(DATA_WIDTH)-1:0] rs2,
    output reg [$clog2(DATA_WIDTH)-1:0] rd,
    output logic [DATA_WIDTH-1:0] unextended_data,
    output reg [4:0] shift_amount,
    output reg [11:0] csr_addr
);

  wire [6:0] inst_op; // opcode present in raw instruction
  assign inst_op = instruction[6:0];

  always @* begin
    sx_op = SX_NOP;
    mem_write = 0;
    reg_write = 0;
    mem_read = 0;
    rs1 = '0;
    rs2 = '0;
    rd = '0;
    f3 = '0;
    f7 = '0;
    unextended_data = '0;
    opcode = instruction[6:0];
    shift_amount = '0;
    csr_addr = '0;
    case (inst_op)
      LOAD: begin // memory load instructions
        sx_op = SX_1100;
        unextended_data = instruction[31:20];
        rs1 = instruction[19:15];
        rd = instruction[11:7];
        f3 = instruction[14:12];
        reg_write = 1;
        mem_read = 1;
      end
      STORE: begin
        sx_op = SX_1100;
        unextended_data = {{(DATA_WIDTH-1-11){1'b0}},instruction[31:25], instruction[11:7]}; // 31 - 11 * zeros + 7 bits from instruction[31:25] + 5 bits from instruction[11:7]
        rs1 = instruction[19:15];
        rs2 = instruction[24:20];
        f3 = instruction[14:12];
        mem_write = 1;
      end
      JAL: begin
        sx_op = SX_2000;
        // FUCK THIS IMMEDIATE FORMATTING
        unextended_data = {instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0}; // 1 + 10 + 1 + 8 + 1 = 21 bits
        rd = instruction[11:7];
        reg_write = 1;
      end
      JALR: begin
        sx_op = SX_1100;
        unextended_data = instruction[31:20];
        rs1 = instruction[19:15];
        rd = instruction[11:7];
        f3 = instruction[14:12];
        reg_write = 1;
      end
      BRANCH: begin
        sx_op = SX_1200;
        unextended_data = {instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0}; // 1 + 1 + 6 + 4 + 1 = 13 bits
        rs1 = instruction[19:15];
        rs2 = instruction[24:20];
        f3 = instruction[14:12];
      end
      REGISTER_IMM: begin
        rs1 = instruction[19:15];
        rd = instruction[11:7];
        f3 = instruction[14:12];
        reg_write = 1;
        case (instruction[14:12])
          SH_SLLI: begin
            f7 = instruction[31:25];
            shift_amount = instruction[24:20];
          end
          SH_SRLI: begin
            f7 = instruction[31:25];
            shift_amount = instruction[24:20];
          end
          default: begin
            unextended_data = instruction[31:20];
            sx_op = SX_1100;
          end
        endcase
      end
      REGISTER: begin
        rd = instruction[11:7];
        f3 = instruction[14:12];
        rs1 = instruction[19:15];
        rs2 = instruction[24:20];
        f7 = instruction[31:25];
        reg_write = 1;
      end
      LUI, AUIPC: begin
        rd = instruction[11:7];
        sx_op = SX_1900;
        unextended_data = instruction[31:12] << 12;
        reg_write = 1;
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
        rd = instruction[11:7];
        f3 = instruction[14:12];
        case (instruction[14:12])
          SYS_ECALL_EBREAK: begin
            rs1 = instruction[19:15]; // should be 0...TODO: enforce a check
            unextended_data = instruction[31:20]; // either 0 (ECALL) or 1 (EBREAK)
          end
          SYS_CSRRW, SYS_CSRRS, SYS_CSRRC: begin
            rs1 = instruction[19:15];
            csr_addr = instruction[31:20];
          end
          SYS_CSRRWI, SYS_CSRRSI, SYS_CSRRCI: begin
            csr_addr = instruction[31:20];
            unextended_data = instruction[19:15];
            sx_op = SX_0400;
          end
          default: begin
          end
        endcase
      end
      default: begin
      end
    endcase
  end

endmodule
