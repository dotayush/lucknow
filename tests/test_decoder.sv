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
  wire [2:0] alu_op;
  wire [2:0] sx_op;
  wire [6:0] opcode;
  wire mem_write;
  wire reg_write;
  wire mem_read;
  wire [$clog2(DATA_WIDTH)-1:0] rs1;
  wire [$clog2(DATA_WIDTH)-1:0] rs2;
  wire [$clog2(DATA_WIDTH)-1:0] rd;
  wire [DATA_WIDTH-1:0] unextended_data;

  // dut instantiation
  decoder #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .instruction(instruction),
    .f3(f3),
    .f7(f7),
    .alu_op(alu_op),
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

  initial begin
    $dumpfile("./tests/results/test_decoder.vcd");
    $dumpvars(0, test_decoder);

    // case 1: line: lw   x5,   2(x10) | hex: 00252283 | bin: 00000000001001010010001010000011
    instruction = 32'b00000000001001010010001010000011; // lw x5, 2(x10)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0000011 || mem_write !== 0 || reg_write !== 1 || mem_read !==1 || rs1 !== 5'b01010 || rs2 !== 5'b0 || rd !== 5'b00101) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), opcode=0000011 (got %b), sx_op2=001 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=1 (got %b), rs1=01010 (got %b), rs2=0 (got %b), rd=00101 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory load instruction decoded correctly", $time);
    end

    // case 2: line: lh   x12,  3(x7) | hex: 00339603 | bin: 00000000001100111001011000000011
    instruction = 32'b00000000001100111001011000000011; // lh x12, 3(x7)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0000011 || mem_write !== 0 || reg_write !== 1 || mem_read !==1 || rs1 !== 5'b00111 || rs2 !== 5'b0 || rd !== 5'b01100) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got &b), opcode=0000011 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=1 (got %b), rs1=00111 (got %b), rs2=0 (got %b), rd=01100 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory load halfword instruction decoded correctly", $time);
    end

    // line: lb   x3,   -9(x14) | hex: ff770183 | bin: 11111111011101110000000110000011
    instruction = 32'b11111111011101110000000110000011; // lb x3, -9(x14)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0000011 || mem_write !== 0 || reg_write !== 1 || mem_read !==1 || rs1 !== 5'b01110 || rs2 !== 5'b0 || rd !== 5'b00011) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=0000011 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=1 (got %b), rs1=01110 (got %b), rs2=0 (got %b), rd=00011 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory load byte instruction decoded correctly", $time);
    end

    // line: lbu  x9,   12(x2) | hex: 00c14483 | bin: 00000000110000010100010010000011
    instruction = 32'b00000000110000010100010010000011; // lbu x9, 12(x2)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0000011 || mem_write !== 0 || reg_write !== 1 || mem_read !==1 || rs1 !== 5'b00010 || rs2 !== 5'b0 || rd !== 5'b01001) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=0000011 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=1 (got %b), rs1=00010 (got %b), rs2=0 (got %b), rd=01001 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory load byte unsigned instruction decoded correctly", $time);
    end

    // line: lhu  x17,  21(x6) | hex: 01535883 | bin: 00000001010100110101100010000011
    instruction = 32'b00000001010100110101100010000011; // lhu x17, 21(x6)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0000011 || mem_write !== 0 || reg_write !== 1 || mem_read !==1 || rs1 !== 5'b00110 || rs2 !== 5'b0 || rd !== 5'b10001) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=0000011 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=1 (got %b), rs1=00110 (got %b), rs2=0 (got %b), rd=10001 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory load halfword unsigned instruction decoded correctly", $time);
    end

    // line: sw   x16,  12(x8) | hex: 01042623 | bin: 00000001000001000010011000100011
    instruction = 32'b00000001000001000010011000100011; // sw x16, 12(x8)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0100011 || mem_write !== 1 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'b01000 || rs2 !== 5'b10000 || rd !== 5'b0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=0100011 (got %b), mem_write=1 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=01000 (got %b), rs2=10000 (got %b), rd=0 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory store instruction decoded correctly", $time);
    end

    // line: sh   x10,  -30(x15) | hex: fea79123 | bin: 11111110101001111001000100100011
    instruction = 32'b11111110101001111001000100100011; // sh x10, -30(x15)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0100011 || mem_write !== 1 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'b01111 || rs2 !== 5'b01010 || rd !== 5'b0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=0100011 (got %b), mem_write=1 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=01111 (got %b), rs2=01010 (got %b), rd=0 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory store halfword instruction decoded correctly", $time);
    end

    // line: sb   x22,  50(x17) | hex: 03688923 | bin: 00000011011010001000100100100011
    instruction = 32'b00000011011010001000100100100011; // sb x22, 50(x17)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b0100011 || mem_write !== 1 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'b10001 || rs2 !== 5'b10110 || rd !== 5'b0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=0100011 (got %b), mem_write=1 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=10001 (got %b), rs2=10110 (got %b), rd=0 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: memory store byte instruction decoded correctly", $time);
    end

    // line: jal  x1,   2 | hex: 002000ef | bin: 00000000001000000000000011101111
    instruction = 32'b00000000001000000000000011101111; // jal x1, 2
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b110 || opcode !==7'b1101111 || mem_write !== 0 || reg_write !== 1 || mem_read !==0 || rs1 !== 5'd0 || rs2 !== 5'd0 || rd !== 5'b00001) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=110 (got %b), opcode=1101111 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=0 (got %b), rs1=0 (got %d), rs2=0 (got %d), rd=00001 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: jump and link instruction decoded correctly", $time);
    end

    // line: jalr x3,   1(x9) | hex: 001481e7 | bin: 00000000000101001000000111100111
    instruction = 32'b00000000000101001000000111100111; // jalr x3, 1(x9)
    #1; // wait for dut to process
    if (alu_op !== 3'b000 || sx_op !== 3'b000 || opcode !==7'b1100111 || mem_write !== 0 || reg_write !== 1 || mem_read !==0 || rs1 !== 5'b01001 || rs2 !== 5'b0 || rd !== 5'b00011) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=000 (got %b), sx_op=000 (got %b), opcode=1100111 (got %b), mem_write=0 (got %b), reg_write=1 (got %b), mem_read=0 (got %b), rs1=01001 (got %b), rs2=0 (got %b), rd=00011 (got %b)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: jump and link register instruction decoded correctly", $time);
    end

    // unrecognized instructions
    instruction = 32'b111111111111_11111_111_11111_1111111; // Invalid instruction
    #1; // wait for dut to process
    if (alu_op !== 3'b111 || sx_op !== 3'b111 || opcode !==7'b1111111 || mem_write !== 0 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'd0 || rs2 !== 5'd0 || rd !== 5'd0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=111 (got %b), opcode=1111111 (got %b), sx_op2=001 (got %b), mem_write=0 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=0 (got %d), rs2=0 (got %d), rd=0 (got %d)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: invalid instruction handled correctly", $time);
    end
    instruction = 32'b000000000000_00000_000_00000_0000000; // 0 instruction
    #1; // wait for dut to process
    if (alu_op !== 3'b111 || sx_op !== 3'b111 || opcode !==7'b0000000 || mem_write !== 0 || reg_write !== 0 || mem_read !==0 || rs1 !== 5'd0 || rs2 !== 5'd0 || rd !== 5'd0) begin
      test_failed = 1;
      $display("[%0t] error: expected alu_op=111 (got %b), sx_op=111 (got %b), opcode=0000000 (got %b), mem_write=0 (got %b), reg_write=0 (got %b), mem_read=0 (got %b), rs1=0 (got %d), rs2=0 (got %d), rd=0 (got %d)",
               $time, alu_op, sx_op, opcode, mem_write, reg_write, mem_read, rs1, rs2, rd);
    end else begin
      $display("[%0t] OK: zero instruction handled correctly", $time);
    end

    finish;
  end


endmodule
