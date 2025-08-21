`ifndef ISA_SHARED_IMPORT
  `define ISA_SHARED_IMPORT
  import isa_shared::*;
`endif

module decoder #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] instruction,

    output reg [2:0] f3,
    output reg [6:0] f7,
    output reg [2:0] alu_op,
    output logic [2:0] sx_op,
    output logic [2:0] sx_op2,
    output reg mem_write,
    output reg reg_write,
    output reg mem_read,
    output reg [$clog2(DATA_WIDTH)-1:0] rs1,
    output reg [$clog2(DATA_WIDTH)-1:0] rs2,
    output reg [$clog2(DATA_WIDTH)-1:0] rd,
    output logic [DATA_WIDTH-1:0] unextended_data,
    output reg [1:0] mem_access_type
);

  wire [6:0] inst_op; // opcode present in raw instruction
  assign inst_op = instruction[6:0];

  always @* begin
    alu_op = ALU_NOP;
    sx_op = SX_NOP;
    sx_op2 = SX_NOP;
    mem_write = 0;
    reg_write = 0;
    mem_read = 0;
    rs1 = '0;
    rs2 = '0;
    rd = '0;
    f3 = '0;
    f7 = '0;
    unextended_data = '0;
    case (inst_op)
      7'b0000011: begin // memory load instructions
        sx_op = SX_1100;
        rs1 = instruction[19:15];
        rd = instruction[11:7];
        unextended_data = instruction[31:20];
        f3 = instruction[14:12];
        alu_op = ALU_ADD;
        mem_write = 0;
        reg_write = 1;
        mem_read = 1;
        case (f3) // funct3
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
          end
        endcase
      end
      default: begin
      end
    endcase

    if (alu_op != ALU_NOP || sx_op != SX_NOP) begin
      if (mem_write && mem_read) begin
        $display("[%0t] error: instruction %b cannot be both a memory write and read at the same time. mem_write=%b, mem_read=%b", $time, instruction, mem_write, mem_read);
        // TODO: implement TRAP
      end
    end
  end

endmodule
