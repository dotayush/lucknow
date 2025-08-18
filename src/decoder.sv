import isa_shared::*;

module decoder #(parameter DATA_WIDTH = 32) (
    input wire [DATA_WIDTH-1:0] instruction,

    output reg [2:0] alu_op,
    output reg [2:0] imm_op,
    output reg mem_write,
    output reg reg_write,
    output reg mem_read,
    output reg [$clog2(DATA_WIDTH)-1:0] rs1,
    output reg [$clog2(DATA_WIDTH)-1:0] rs2,
    output reg [$clog2(DATA_WIDTH)-1:0] rd
);

  wire [6:0] inst_op; // opcode present in raw instruction
  assign inst_op = instruction[6:0];

  always @* begin
    alu_op = ALU_NOP;
    imm_op = IMM_NOP;
    mem_write = 0;
    reg_write = 0;
    mem_read = 0;
    rs1 = '0;
    rs2 = '0;
    rd = '0;
    case (inst_op)
      7'b0000011: begin // memory load instructions
        imm_op = IMM_3120;
        rs1 = instruction[19:15];
        rd = instruction[11:7];
        case (instruction[14:12]) // funct3
          3'b010: begin // lw
            alu_op = ALU_ADD;
            mem_write = 0;
            reg_write = 1;
            mem_read = 1;
          end
          default: begin
          end
        endcase
      end
      default: begin
      end
    endcase

    if (alu_op != ALU_NOP || imm_op != IMM_NOP) begin
      assert (!(mem_write && mem_read)) else begin
        $display("[%0t] error: instruction %b cannot be both a memory write and read at the same time. mem_write=%b, mem_read=%b", $time, instruction, mem_write, mem_read);
        $fatal(1);
      end
    end
  end

endmodule
