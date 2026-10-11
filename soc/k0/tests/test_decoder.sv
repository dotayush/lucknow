`timescale 1ns/1ps

module test_decoder;

  localparam int DATA_WIDTH = 32;
  reg test_failed;

  task finish;
    begin
      if (test_failed) begin
        $display("Test failed!");
      end else begin
        $display("Test passed!");
      end
      $finish; // End simulation
    end
  endtask

  // dut io
  reg [DATA_WIDTH-1:0] instruction;
  wire [2:0] f3;
  wire [6:0] f7;
  wire [4:0] sx_op;
  wire [6:0] opcode;
  wire mem_write;
  wire reg_write;
  wire mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;
  wire [DATA_WIDTH-1:0] unextended_data;
  wire [4:0] shift_amount;
  wire [11:0] csr_addr;

  // dut instantiation
  decoder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
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

  // drive `inst` and compare every decoder output against the expected one
  task check(
    input string name,
    input [31:0] inst,
    input [6:0] e_opcode,
    input e_mem_write, input e_reg_write, input e_mem_read,
    input [4:0] e_rs1, input [4:0] e_rs2, input [4:0] e_rd,
    input [2:0] e_f3, input [6:0] e_f7,
    input [4:0] e_sx_op, input [31:0] e_unextended,
    input [11:0] e_csr_addr, input [4:0] e_shift_amount
  );
    begin
      instruction = inst;
      #1;
      if (opcode !== e_opcode || mem_write !== e_mem_write || reg_write !== e_reg_write || mem_read !== e_mem_read ||
          rs1 !== e_rs1 || rs2 !== e_rs2 || rd !== e_rd || f3 !== e_f3 || f7 !== e_f7 || sx_op !== e_sx_op ||
          unextended_data !== e_unextended || csr_addr !== e_csr_addr || shift_amount !== e_shift_amount) begin
        test_failed = 1;
        $display("[%0t] error: %s (%08x)", $time, name, inst);
        $display("    opcode=%b/%b mem_write=%b/%b reg_write=%b/%b mem_read=%b/%b rs1=%0d/%0d rs2=%0d/%0d rd=%0d/%0d",
                 opcode, e_opcode, mem_write, e_mem_write, reg_write, e_reg_write, mem_read, e_mem_read, rs1, e_rs1, rs2, e_rs2, rd, e_rd);
        $display("    f3=%b/%b f7=%b/%b sx_op=%b/%b unextended=%08x/%08x csr_addr=%03x/%03x shift_amount=%0d/%0d   (got/expected)",
                 f3, e_f3, f7, e_f7, sx_op, e_sx_op, unextended_data, e_unextended, csr_addr, e_csr_addr, shift_amount, e_shift_amount);
      end else begin
        $display("[%0t] OK: %s", $time, name);
      end
    end
  endtask

  localparam [6:0] OP_LOAD = 7'b0000011, OP_STORE = 7'b0100011, OP_BRANCH = 7'b1100011, OP_JAL = 7'b1101111,
                   OP_JALR = 7'b1100111, OP_IMM = 7'b0010011, OP_REG = 7'b0110011, OP_LUI = 7'b0110111,
                   OP_AUIPC = 7'b0010111, OP_FENCE = 7'b0001111, OP_SYSTEM = 7'b1110011;

  initial begin
    $dumpfile("./tests/results/test_decoder.vcd");
    $dumpvars(0, test_decoder);
    test_failed = 0;

    //     name                inst        opcode     mw rw mr rs1 rs2 rd  f3     f7         sx_op  unextended  csr   shamt
    check("lw x4, 0(x0)",      32'h00002203, OP_LOAD,   0, 1, 1, 0,  0,  4,  3'b010, 7'b0,      isa_shared::SX_1100, 32'h0,        12'h0,   5'd0);
    check("lbu x11, 3(x1)",    32'h0030c583, OP_LOAD,   0, 1, 1, 1,  0,  11, 3'b100, 7'b0,      isa_shared::SX_1100, 32'h3,        12'h0,   5'd0);
    check("lb x3, -9(x14)",    32'hff770183, OP_LOAD,   0, 1, 1, 14, 0,  3,  3'b000, 7'b0,      isa_shared::SX_1100, 32'hff7,      12'h0,   5'd0);
    check("sw x3, 0(x0)",      32'h00302023, OP_STORE,  1, 0, 0, 0,  3,  0,  3'b010, 7'b0,      isa_shared::SX_1100, 32'h0,        12'h0,   5'd0);
    check("sh x2, 6(x1)",      32'h00209323, OP_STORE,  1, 0, 0, 1,  2,  0,  3'b001, 7'b0,      isa_shared::SX_1100, 32'h6,        12'h0,   5'd0);
    check("sh x10, -30(x15)",  32'hfea79123, OP_STORE,  1, 0, 0, 15, 10, 0,  3'b001, 7'b0,      isa_shared::SX_1100, 32'hfe2,      12'h0,   5'd0);
    check("beq x3, x4, 8",     32'h00418463, OP_BRANCH, 0, 0, 0, 3,  4,  0,  3'b000, 7'b0,      isa_shared::SX_1200, 32'h8,        12'h0,   5'd0);
    check("bne x12, x7, -4",   32'hfe761ee3, OP_BRANCH, 0, 0, 0, 12, 7,  0,  3'b001, 7'b0,      isa_shared::SX_1200, 32'h1ffc,     12'h0,   5'd0);
    check("jal x1, 2",         32'h002000ef, OP_JAL,    0, 1, 0, 0,  0,  1,  3'b000, 7'b0,      isa_shared::SX_2000, 32'h2,        12'h0,   5'd0);
    check("jalr x3, 1(x9)",    32'h001481e7, OP_JALR,   0, 1, 0, 9,  0,  3,  3'b000, 7'b0,      isa_shared::SX_1100, 32'h1,        12'h0,   5'd0);
    check("addi x1, x0, 5",    32'h00500093, OP_IMM,    0, 1, 0, 0,  0,  1,  3'b000, 7'b0,      isa_shared::SX_1100, 32'h5,        12'h0,   5'd0);
    check("sltiu x13, x1, -1", 32'hfff0b693, OP_IMM,    0, 1, 0, 1,  0,  13, 3'b011, 7'b0,      isa_shared::SX_1100, 32'hfff,      12'h0,   5'd0);
    check("slli x9, x1, 3",    32'h00309493, OP_IMM,    0, 1, 0, 1,  0,  9,  3'b001, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h0,   5'd3);
    check("srai x10, x1, 3",   32'h4030d513, OP_IMM,    0, 1, 0, 1,  0,  10, 3'b101, 7'b0100000, isa_shared::SX_NOP, 32'h0,        12'h0,   5'd3);
    check("add x3, x1, x2",    32'h002081b3, OP_REG,    0, 1, 0, 1,  2,  3,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h0,   5'd0);
    check("sub x3, x1, x2",    32'h402081b3, OP_REG,    0, 1, 0, 1,  2,  3,  3'b000, 7'b0100000, isa_shared::SX_NOP, 32'h0,        12'h0,   5'd0);
    check("mul x3, x1, x2",    32'h022081b3, OP_REG,    0, 1, 0, 1,  2,  3,  3'b000, 7'b0000001, isa_shared::SX_NOP, 32'h0,        12'h0,   5'd0);
    check("mulhu x3, x1, x2",  32'h0220b1b3, OP_REG,    0, 1, 0, 1,  2,  3,  3'b011, 7'b0000001, isa_shared::SX_NOP, 32'h0,        12'h0,   5'd0);
    check("div x3, x1, x2",    32'h0220c1b3, OP_REG,    0, 1, 0, 1,  2,  3,  3'b100, 7'b0000001, isa_shared::SX_NOP, 32'h0,        12'h0,   5'd0);
    check("remu x3, x1, x2",   32'h0220f1b3, OP_REG,    0, 1, 0, 1,  2,  3,  3'b111, 7'b0000001, isa_shared::SX_NOP, 32'h0,        12'h0,   5'd0);
    // the whole 32 bit value is forwarded, the upper 20 bits must survive.
    check("lui x7, 0xabcde",   32'habcde3b7, OP_LUI,    0, 1, 0, 0,  0,  7,  3'b000, 7'b0,      isa_shared::SX_3100, 32'habcde000, 12'h0,   5'd0);
    check("auipc x12,0x12345", 32'h12345617, OP_AUIPC,  0, 1, 0, 0,  0,  12, 3'b000, 7'b0,      isa_shared::SX_3100, 32'h12345000, 12'h0,   5'd0);
    check("fence",             32'h0ff0000f, OP_FENCE,  0, 0, 0, 0,  0,  0,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h0,   5'd0);
    // csr instructions leave reg_write to the control (the csr value goes to rd)
    check("csrrw x8,mtvec,x1", 32'h30509473, OP_SYSTEM, 0, 0, 0, 1,  0,  8,  3'b001, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h305, 5'd0);
    check("csrrsi x14,mstatus,8", 32'h30046773, OP_SYSTEM, 0, 0, 0, 0, 0, 14, 3'b110, 7'b0,     isa_shared::SXU_0400, 32'h8,       12'h300, 5'd0);
    check("ecall",             32'h00000073, OP_SYSTEM, 0, 0, 0, 0,  0,  0,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h0,   5'd0);
    check("ebreak",            32'h00100073, OP_SYSTEM, 0, 0, 0, 0,  0,  0,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h1,        12'h0,   5'd0);
    // mret reads mepc
    check("mret",              32'h30200073, OP_SYSTEM, 0, 0, 0, 0,  0,  0,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h302,      isa_shared::CSR_MEPC, 5'd0);

    // unknown encodings decode to "does nothing"
    check("unknown opcode",    32'hFFFFFFFF, 7'b1111111, 0, 0, 0, 0, 0,  0,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h0,   5'd0);
    check("all zero",          32'h00000000, 7'b0000000, 0, 0, 0, 0, 0,  0,  3'b000, 7'b0,      isa_shared::SX_NOP,  32'h0,        12'h0,   5'd0);

    finish;
  end

endmodule
